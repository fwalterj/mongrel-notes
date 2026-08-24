import Foundation
import AppKit

// MARK: – LSP Types

struct LSPCompletionItem: Identifiable, Equatable {
    let id:     UUID      = UUID()
    let label:  String
    let detail: String?   // type info / signature
    let kind:   CompletionKind
    let insertText: String

    enum CompletionKind: Int {
        case text       = 1, method, function, constructor, field,
             variable   = 6, `class`, interface, module, property,
             unit       = 11, value, `enum`, keyword, snippet,
             color      = 16, file, reference, folder, enumMember,
             constant   = 21, `struct`, event, `operator`, typeParameter

        var icon: String {
            switch self {
            case .function, .method, .constructor: return "function"
            case .variable, .field, .property:     return "f.cursive"
            case .class, .struct, .interface:      return "cube"
            case .keyword:                         return "key"
            case .snippet:                         return "text.badge.star"
            case .module, .folder:                 return "folder"
            case .constant, .enumMember, .value:   return "number"
            default:                               return "doc.text"
            }
        }
    }
}

// MARK: – IntellisenseManager

/// Manages Language Server Protocol (LSP) sessions for Python and JavaScript.
/// Each language server runs as a child `Process`, communicating via JSON-RPC
/// over stdio (the standard LSP transport).
///
/// Architecture
/// ────────────
/// • One `LSPSession` per active language (lazily started, auto-restarted on crash).
/// • JSON-RPC messages are sent/received on a background serial queue.
/// • Completions arrive via an async continuation and are published on `@MainActor`.
///
/// Setup for end-users
/// ───────────────────
///   brew install pyright                  # Python (fast, no Python env needed)
///   npm install -g typescript-language-server typescript   # JS/TS
@MainActor
final class IntellisenseManager: ObservableObject {

    @Published var completions:  [LSPCompletionItem] = []
    @Published var isActive:     Bool                = false
    @Published var serverStatus: [String: String]    = [:]  // language → "running"|"stopped"|"error"

    static let shared = IntellisenseManager()
    private var sessions: [String: LSPSession] = [:]

    private init() {}

    // MARK: – Public API

    /// Request completions for `text` at `line`:`character` in the given `language`.
    /// Results are published on `self.completions`.
    func requestCompletions(
        text: String,
        language: String,
        line: Int,
        character: Int,
        fileURL: URL? = nil
    ) {
        let lang = canonicalLanguage(language)
        let session = sessionFor(language: lang)

        Task.detached(priority: .userInitiated) { [weak self] in
            let items = await session.completion(
                text: text, language: lang,
                line: line, character: character,
                fileURL: fileURL
            )
            await MainActor.run {
                self?.completions = items
                self?.isActive    = true
            }
        }
    }

    func dismiss() {
        completions = []
        isActive    = false
    }

    /// Stop all language server processes (e.g. on app quit).
    func shutdown() {
        sessions.values.forEach { $0.stop() }
        sessions.removeAll()
    }

    // MARK: – Session management

    private func sessionFor(language: String) -> LSPSession {
        if let existing = sessions[language] { return existing }
        let session = LSPSession(language: language)
        sessions[language] = session
        session.start { [weak self] status in
            Task { @MainActor in
                self?.serverStatus[language] = status
            }
        }
        return session
    }

    private func canonicalLanguage(_ lang: String) -> String {
        let l = lang.lowercased()
        if ["py", "python3", "python"].contains(l) { return "python" }
        if ["js", "ts", "typescript", "jsx", "tsx"].contains(l) { return "javascript" }
        return l
    }
}

// MARK: – LSPSession

/// Manages a single LSP server child process.
/// Uses JSON-RPC 2.0 over stdin/stdout per the LSP spec.
final class LSPSession {

    private let language: String
    private var process:  Process?
    private var inPipe:   Pipe?
    private var outPipe:  Pipe?
    private var errPipe:  Pipe?
    private var msgID:    Int = 1
    private let queue     = DispatchQueue(label: "com.mongrel.lsp.\(UUID().uuidString)",
                                          qos: .userInitiated)
    private var pendingRequests: [Int: CheckedContinuation<Any?, Never>] = [:]
    private var readBuffer = Data()
    private var statusCallback: ((String) -> Void)?

    // Cached temp file URL for the open document
    private var documentURI: String = ""

    init(language: String) { self.language = language }

    // MARK: – Server lifecycle

    func start(statusCallback: @escaping (String) -> Void) {
        self.statusCallback = statusCallback
        guard let serverPath = serverExecutablePath() else {
            statusCallback("stopped")
            return
        }
        queue.async { [weak self] in self?.launchServer(path: serverPath) }
    }

    func stop() {
        process?.terminate()
        process = nil
        statusCallback?("stopped")
    }

    // MARK: – Completions

    func completion(text: String, language: String,
                    line: Int, character: Int,
                    fileURL: URL?) async -> [LSPCompletionItem] {
        guard process?.isRunning == true else { return [] }

        // Ensure the document is open in the server
        let uri = fileURL.map { "file://\($0.path)" } ?? "untitled://\(language)"
        if documentURI != uri {
            openDocument(text: text, uri: uri, language: language)
            documentURI = uri
        } else {
            didChangeDocument(text: text, uri: uri)
        }

        // Request completions
        let params: [String: Any] = [
            "textDocument": ["uri": uri],
            "position": ["line": line, "character": character],
            "context": ["triggerKind": 1]
        ]

        guard let response = await sendRequest(method: "textDocument/completion",
                                               params: params) else { return [] }

        return parseCompletions(response)
    }

    // MARK: – JSON-RPC I/O

    private func sendRequest(method: String, params: [String: Any]) async -> Any? {
        let id = msgID; msgID += 1
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id":      id,
            "method":  method,
            "params":  params
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return nil }

        let payload = "Content-Length: \(json.utf8.count)\r\n\r\n\(json)"

        return await withCheckedContinuation { (cont: CheckedContinuation<Any?, Never>) in
            queue.async { [weak self] in
                guard let self else { cont.resume(returning: nil); return }
                self.pendingRequests[id] = cont
                self.inPipe?.fileHandleForWriting.write(
                    payload.data(using: .utf8) ?? Data()
                )
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any]) {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "method":  method,
            "params":  params
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }
        let payload = "Content-Length: \(json.utf8.count)\r\n\r\n\(json)"
        queue.async { [weak self] in
            self?.inPipe?.fileHandleForWriting.write(
                payload.data(using: .utf8) ?? Data()
            )
        }
    }

    // MARK: – Server launch

    private func launchServer(path: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments     = serverArguments()

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        proc.environment = env

        let inP  = Pipe(); let outP = Pipe(); let errP = Pipe()
        proc.standardInput  = inP
        proc.standardOutput = outP
        proc.standardError  = errP

        self.inPipe  = inP
        self.outPipe = outP
        self.errPipe = errP
        self.process = proc

        // Read responses asynchronously
        outP.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.queue.async { self?.handleData(handle.availableData) }
        }

        proc.terminationHandler = { [weak self] _ in
            self?.statusCallback?("stopped")
        }

        do {
            try proc.run()
            statusCallback?("running")
            initializeServer()
        } catch {
            statusCallback?("error: \(error.localizedDescription)")
        }
    }

    private func initializeServer() {
        let rootURI = "file://\(FileManager.default.homeDirectoryForCurrentUser.path)"
        let params: [String: Any] = [
            "processId":    ProcessInfo.processInfo.processIdentifier,
            "rootUri":      rootURI,
            "capabilities": [
                "textDocument": [
                    "completion": [
                        "completionItem": ["snippetSupport": false]
                    ]
                ]
            ],
            "trace": "off"
        ]
        Task {
            _ = await sendRequest(method: "initialize", params: params)
            sendNotification(method: "initialized", params: [:])
        }
    }

    // MARK: – Document notifications

    private func openDocument(text: String, uri: String, language: String) {
        sendNotification(method: "textDocument/didOpen", params: [
            "textDocument": [
                "uri":        uri,
                "languageId": language,
                "version":    1,
                "text":       text
            ]
        ])
    }

    private func didChangeDocument(text: String, uri: String) {
        sendNotification(method: "textDocument/didChange", params: [
            "textDocument": ["uri": uri, "version": msgID],
            "contentChanges": [["text": text]]
        ])
    }

    // MARK: – Response parsing

    private func handleData(_ data: Data) {
        guard !data.isEmpty else { return }
        readBuffer.append(data)
        while let msg = extractNextMessage() {
            dispatchMessage(msg)
        }
    }

    private func extractNextMessage() -> [String: Any]? {
        guard let headerEnd = readBuffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = readBuffer[readBuffer.startIndex..<headerEnd.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8),
              let lenRange = header.range(of: "Content-Length: "),
              let len = Int(header[lenRange.upperBound...].trimmingCharacters(in: .newlines)) else {
            return nil
        }
        let bodyStart  = headerEnd.upperBound
        let bodyEnd    = readBuffer.index(bodyStart, offsetBy: len, limitedBy: readBuffer.endIndex)
        guard let end  = bodyEnd, readBuffer.count >= readBuffer.distance(from: readBuffer.startIndex, to: end) else {
            return nil
        }
        let bodyData   = readBuffer[bodyStart..<end]
        readBuffer.removeSubrange(..<end)
        return (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
    }

    private func dispatchMessage(_ msg: [String: Any]) {
        guard let id = msg["id"] as? Int else { return } // skip notifications
        if let cont = pendingRequests.removeValue(forKey: id) {
            cont.resume(returning: msg["result"])
        }
    }

    private func parseCompletions(_ response: Any?) -> [LSPCompletionItem] {
        let itemsRaw: [[String: Any]]
        if let dict = response as? [String: Any], let items = dict["items"] as? [[String: Any]] {
            itemsRaw = items
        } else if let list = response as? [[String: Any]] {
            itemsRaw = list
        } else { return [] }

        return itemsRaw.prefix(50).compactMap { item in
            guard let label = item["label"] as? String else { return nil }
            let kind       = LSPCompletionItem.CompletionKind(
                rawValue: (item["kind"] as? Int) ?? 1) ?? .text
            let detail     = item["detail"] as? String
            let insertText = (item["insertText"] as? String) ?? label
            return LSPCompletionItem(label: label, detail: detail,
                                     kind: kind, insertText: insertText)
        }
    }

    // MARK: – Server path resolution

    private func serverExecutablePath() -> String? {
        switch language {
        case "python":
            // Prefer pyright (faster, no virtualenv needed), fall back to pylsp
            return Process.which("pyright-langserver")
                ?? Process.which("pylsp")
                ?? Process.which("python-language-server")
        case "javascript":
            return Process.which("typescript-language-server")
                ?? Process.which("javascript-typescript-langserver")
        default:
            return Process.which("\(language)-language-server")
        }
    }

    private func serverArguments() -> [String] {
        switch language {
        case "python":     return ["--stdio"]
        case "javascript": return ["--stdio"]
        default:           return ["--stdio"]
        }
    }
}
