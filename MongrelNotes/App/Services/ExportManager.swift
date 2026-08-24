import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers
import SharedFoundation

// MARK: – ExportFormat

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf        = "PDF"
    case html       = "HTML"
    case markdown   = "Markdown"
    case css        = "CSS Stylesheet"
    case docx       = "Word Document"
    case python     = "Python"
    case javascript = "JavaScript"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .pdf:        return "pdf"
        case .html:       return "html"
        case .markdown:   return "md"
        case .css:        return "css"
        case .docx:       return "docx"
        case .python:     return "py"
        case .javascript: return "js"
        }
    }

    var contentType: UTType {
        switch self {
        case .pdf:        return .pdf
        case .html:       return .html
        case .markdown:   return UTType(filenameExtension: "md") ?? .plainText
        case .css:        return UTType(filenameExtension: "css") ?? .plainText
        case .docx:       return UTType(filenameExtension: "docx") ?? .data
        case .python:     return UTType(filenameExtension: "py") ?? .plainText
        case .javascript: return UTType(filenameExtension: "js") ?? .plainText
        }
    }

    var icon: String {
        switch self {
        case .pdf:        return "doc.richtext"
        case .html:       return "globe"
        case .markdown:   return "doc.plaintext"
        case .css:        return "paintpalette"
        case .docx:       return "doc.fill"
        case .python:     return "chevron.left.forwardslash.chevron.right"
        case .javascript: return "curlybraces"
        }
    }

    var requiresCodeBlocks: Bool { self == .python || self == .javascript }
}

// MARK: – ExportDelegate

protocol ExportDelegate: AnyObject {
    func exportDidStart(format: ExportFormat)
    func exportDidSucceed(format: ExportFormat, url: URL)
    func exportDidFail(format: ExportFormat, error: Error)
}

// MARK: – ExportManager

/// Central export coordinator.
/// All heavy work runs on a background `DispatchQueue` (efficiency cores on
/// Apple Silicon) to keep the UI responsive.
/// PDF generation re-uses `WKWebView` which is Metal-accelerated on macOS.
@MainActor
final class ExportManager: ObservableObject {

    @Published var isExporting  = false
    @Published var lastExported: URL? = nil
    @Published var errorMessage: String? = nil

    weak var delegate: ExportDelegate?

    private let queue = DispatchQueue(label: "com.mongrel.export", qos: .utility)

    // MARK: – Public entry point

    /// Export `note` in `format`, showing a save panel.
    func export(_ note: SharedFoundation.Note, format: ExportFormat,
                mood: EditorMood = .glass) {
        // .py and .js need code blocks; warn if none found
        if format.requiresCodeBlocks {
            let language = format == .python ? "python" : "javascript"
            let blocks = extractCodeBlocks(from: note.body, languages: codeAliases(for: language))
            if blocks.isEmpty {
                errorMessage = "No \(language) code blocks found in this note. Wrap code in ```\(language) fences."
                return
            }
        }

        // Show save panel on main thread first, then do heavy work in background
        guard let url = presentSavePanel(for: note, format: format) else { return }
        isExporting = true
        delegate?.exportDidStart(format: format)

        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.performExport(note, format: format, mood: mood, to: url)
                DispatchQueue.main.async {
                    self.isExporting  = false
                    self.lastExported = url
                    self.delegate?.exportDidSucceed(format: format, url: url)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExporting  = false
                    self.errorMessage = error.localizedDescription
                    self.delegate?.exportDidFail(format: format, error: error)
                }
            }
        }
    }

    /// Export to an explicit URL (for batch / programmatic use, no panel).
    func export(_ note: SharedFoundation.Note, format: ExportFormat,
                mood: EditorMood = .glass, to url: URL,
                completion: ((Result<URL, Error>) -> Void)? = nil) {
        isExporting = true
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.performExport(note, format: format, mood: mood, to: url)
                DispatchQueue.main.async {
                    self.isExporting = false
                    completion?(.success(url))
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExporting = false
                    completion?(.failure(error))
                }
            }
        }
    }

    // MARK: – Format dispatch

    private func performExport(_ note: SharedFoundation.Note, format: ExportFormat,
                               mood: EditorMood, to url: URL) throws {
        switch format {
        case .pdf:        try exportPDF(note, mood: mood, to: url)
        case .html:       try exportHTML(note, mood: mood, to: url)
        case .markdown:   try exportMarkdown(note, to: url)
        case .css:        try exportCSS(mood: mood, to: url)
        case .docx:       try exportDocx(note, to: url)
        case .python:     try exportCode(note, language: "python", to: url)
        case .javascript: try exportCode(note, language: "javascript", to: url)
        }
    }

    // MARK: – PDF

    private func exportPDF(_ note: SharedFoundation.Note, mood: EditorMood, to url: URL) throws {
        let html = HTMLBuilder.build(from: note.body, title: note.title, mood: mood)
        // PDF rendering must happen on the main thread (WKWebView)
        var renderError: Error?
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            PDFRenderer.render(html: html, to: url) { error in
                renderError = error; sem.signal()
            }
        }
        sem.wait()
        if let err = renderError { throw err }
    }

    // MARK: – HTML

    private func exportHTML(_ note: SharedFoundation.Note, mood: EditorMood, to url: URL) throws {
        let html = HTMLBuilder.build(from: note.body, title: note.title, mood: mood)
        try html.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: – Markdown

    private func exportMarkdown(_ note: SharedFoundation.Note, to url: URL) throws {
        try note.body.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: – CSS

    private func exportCSS(mood: EditorMood, to url: URL) throws {
        let css = CSSExporter.export(mood: mood)
        try css.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: – DOCX

    private func exportDocx(_ note: SharedFoundation.Note, to url: URL) throws {
        // Strategy 1: Pandoc (higher fidelity)
        if let pandoc = Process.pandocPath {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("mongrel_\(UUID().uuidString).md")
            try note.body.write(to: tmp, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let result = Process.runCommand(pandoc, args: [
                "--from", "markdown", "--to", "docx",
                "--standalone", "-o", url.path, tmp.path
            ])
            if result.succeeded && FileManager.default.fileExists(atPath: url.path) { return }
        }
        // Strategy 2: Native OOXML generator
        try DocxGenerator.generate(from: note.body, title: note.title, outputURL: url)
    }

    // MARK: – Python / JavaScript code extraction

    private func exportCode(_ note: SharedFoundation.Note, language: String, to url: URL) throws {
        let blocks = extractCodeBlocks(from: note.body, languages: codeAliases(for: language))
        guard !blocks.isEmpty else {
            throw ExportError.noCodeBlocks(language)
        }

        let header = language == "python"
            ? "# Exported from MongrelNotes: \(note.title)\n# Generated: \(formattedDate())\n\n"
            : "// Exported from MongrelNotes: \(note.title)\n// Generated: \(formattedDate())\n\n"

        let separator = language == "python"
            ? "\n\n# ──────────────────────────────────────────\n\n"
            : "\n\n// ──────────────────────────────────────────\n\n"

        let output = header + blocks.joined(separator: separator)
        try output.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: – Helpers

    /// Extract all fenced code blocks for a given language from Markdown source.
    func extractCodeBlocks(from markdown: String, language: String) -> [String] {
        extractCodeBlocks(from: markdown, languages: [language])
    }

    private func extractCodeBlocks(from markdown: String, languages: [String]) -> [String] {
        var blocks: [String] = []
        var current: [String]? = nil
        let accepted = Set(languages.map { $0.lowercased() })

        for line in markdown.components(separatedBy: "\n") {
            if let curr = current {
                if line.hasPrefix("```") {
                    blocks.append(curr.joined(separator: "\n"))
                    current = nil
                } else {
                    current = curr + [line]
                }
            } else if line.hasPrefix("```") {
                let info = line.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
                let fenceLanguage = info.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
                if accepted.contains(fenceLanguage) {
                    current = []
                }
            }
        }
        return blocks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func codeAliases(for language: String) -> [String] {
        switch language {
        case "python":     return ["python", "py", "python3"]
        case "javascript": return ["javascript", "js", "typescript", "ts"]
        default:           return [language]
        }
    }

    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: Date())
    }

    // MARK: – Save panel

    private func presentSavePanel(for note: SharedFoundation.Note,
                                  format: ExportFormat) -> URL? {
        // Must run on main thread; `export()` is @MainActor so this is fine
        let panel = NSSavePanel()
        let sanitised = note.title
            .replacingOccurrences(of: #"[/\\:*?\"<>|]"#, with: "-",
                                   options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = "\(sanitised).\(format.fileExtension)"
        panel.allowedContentTypes  = [format.contentType]
        panel.canCreateDirectories = true
        panel.message              = "Export note as \(format.rawValue)"
        panel.prompt               = "Export"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    enum ExportError: LocalizedError {
        case noCodeBlocks(String)
        var errorDescription: String? {
            switch self {
            case .noCodeBlocks(let lang):
                return "No \(lang) code blocks found. Wrap code in ```\(lang) fences."
            }
        }
    }
}

// MARK: – HTMLBuilder

/// Converts Markdown → self-contained HTML with embedded mood CSS.
/// Used by both the HTML and PDF exporters.
enum HTMLBuilder {

    static func build(from markdown: String, title: String, mood: EditorMood,
                      includeMetaViewport: Bool = true) -> String {
        let body    = convertMarkdown(markdown)
        let css     = CSSExporter.export(mood: mood, forEmbed: true)
        let meta    = includeMetaViewport
            ? "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            : ""
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        \(meta)
        <title>\(esc(title))</title>
        <style>\(css)</style>
        </head>
        <body>
        <main class="content">
        \(body)
        </main>
        </body>
        </html>
        """
    }

    // MARK: – Markdown → HTML

    private static func convertMarkdown(_ md: String) -> String {
        var out     = ""
        var inCode  = false
        var codeBuf : [String] = []
        var codeLang = ""
        var inPara  = false

        for line in md.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inCode {
                    if inPara { out += "</p>\n"; inPara = false }
                    let lang = codeLang.isEmpty ? "" : " class=\"language-\(esc(codeLang))\""
                    out += "<pre><code\(lang)>\(codeBuf.map { esc($0) }.joined(separator: "\n"))</code></pre>\n"
                    codeBuf = []; codeLang = ""; inCode = false
                } else {
                    if inPara { out += "</p>\n"; inPara = false }
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCode = true
                }
                continue
            }
            if inCode { codeBuf.append(line); continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if inPara { out += "</p>\n"; inPara = false }
                continue
            }

            func closeP() { if inPara { out += "</p>\n"; inPara = false } }

            if      line.hasPrefix("#### ") { closeP(); out += "<h4>\(inline(String(line.dropFirst(5))))</h4>\n" }
            else if line.hasPrefix("### ")  { closeP(); out += "<h3>\(inline(String(line.dropFirst(4))))</h3>\n" }
            else if line.hasPrefix("## ")   { closeP(); out += "<h2>\(inline(String(line.dropFirst(3))))</h2>\n" }
            else if line.hasPrefix("# ")    { closeP(); out += "<h1>\(inline(String(line.dropFirst(2))))</h1>\n" }
            else if line.hasPrefix("> ")    { closeP(); out += "<blockquote><p>\(inline(String(line.dropFirst(2))))</p></blockquote>\n" }
            else if trimmed == "---" || trimmed == "***" { closeP(); out += "<hr>\n" }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                closeP()
                out += "<ul><li>\(inline(String(line.dropFirst(2))))</li></ul>\n"
            }
            else if line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                closeP()
                let content = line.replacingOccurrences(of: #"^\d+\.\s+"#, with: "",
                                                         options: .regularExpression)
                out += "<ol><li>\(inline(content))</li></ol>\n"
            }
            else {
                if !inPara { out += "<p>"; inPara = true } else { out += " " }
                out += inline(line)
            }
        }
        if inPara  { out += "</p>\n" }
        if inCode  { out += "<pre><code>\(codeBuf.map { esc($0) }.joined(separator: "\n"))</code></pre>\n" }
        return out
    }

    private static func inline(_ s: String) -> String {
        var t = s
        // Preserve <span style="color:…"> from colour tool
        t = t.replacingOccurrences(of: #"\*\*(.+?)\*\*"#,
                                   with: "<strong>$1</strong>", options: .regularExpression)
        t = t.replacingOccurrences(of: #"__(.+?)__"#,
                                   with: "<strong>$1</strong>", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#,
                                   with: "<em>$1</em>", options: .regularExpression)
        t = t.replacingOccurrences(of: #"`([^`]+)`"#,
                                   with: "<code>$1</code>", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#,
                                   with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[\[([^\]]+)\]\]"#,
                                   with: "<span class=\"wikilink\">$1</span>",
                                   options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<!\w)#([A-Za-z][A-Za-z0-9_/-]*)"#,
                                   with: "<span class=\"tag\">#$1</span>",
                                   options: .regularExpression)
        return t
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: – CSSExporter

/// Generates a CSS stylesheet from an `EditorMood`.
/// `forEmbed: true` adds minimal global resets and typography;
/// `forEmbed: false` (standalone .css export) adds a richer base.
enum CSSExporter {

    static func export(mood: EditorMood, forEmbed: Bool = false) -> String {
        let (r0,g0,b0,_) = mood.background.sRGBComponents
        let (r1,g1,b1,_) = mood.text.sRGBComponents
        let (r2,g2,b2,_) = mood.accent.sRGBComponents
        let (r3,g3,b3,_) = mood.dimText.sRGBComponents

        let maxW  = UserDefaults.standard.double(forKey: Prefs.editorMaxWidth)
        let lh    = UserDefaults.standard.double(forKey: Prefs.editorLineHeight)
        let fs    = UserDefaults.standard.double(forKey: Prefs.editorFontSize)
        let maxWv = maxW > 0 ? "\(Int(maxW))px" : "740px"
        let lhV   = lh   > 0 ? "\(lh)"          : "1.6"
        let fsV   = fs   > 0 ? "\(Int(fs))px"   : "14px"

        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> String {
            "rgb(\(Int(r*255)),\(Int(g*255)),\(Int(b*255)))"
        }

        let header = forEmbed ? "" : """
        /*
         * MongrelNotes — "\(mood.name)" export stylesheet
         * Generated: \(Date())
         * Apply to any HTML document that contains Markdown-rendered content.
         */\n
        """

        return header + """
        :root {
          --mn-bg:      \(rgb(r0,g0,b0));
          --mn-text:    \(rgb(r1,g1,b1));
          --mn-accent:  \(rgb(r2,g2,b2));
          --mn-dim:     \(rgb(r3,g3,b3));
          --mn-max-w:   \(maxWv);
          --mn-lh:      \(lhV);
          --mn-fs:      \(fsV);
          --mn-radius:  6px;
          --mn-code-bg: color-mix(in srgb, var(--mn-accent) 12%, transparent);
        }
        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
        html { font-size: var(--mn-fs); }
        body {
          background-color: var(--mn-bg);
          color: var(--mn-text);
          font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
          font-size:   var(--mn-fs);
          line-height: var(--mn-lh);
          padding: 3rem 1.5rem;
          -webkit-font-smoothing: antialiased;
        }
        .content { max-width: var(--mn-max-w); margin: 0 auto; }
        h1 { font-size: 2em;   color: var(--mn-accent); margin: 1em 0 .4em; font-weight: 700; }
        h2 { font-size: 1.5em; color: var(--mn-accent); opacity:.88; margin:.9em 0 .35em; font-weight:600; }
        h3 { font-size: 1.2em; color: var(--mn-accent); opacity:.75; margin:.8em 0 .3em; font-weight:600; }
        h4 { font-size: 1em;   color: var(--mn-accent); opacity:.65; margin:.7em 0 .25em; font-weight:600; font-style:italic; }
        p  { margin: .6em 0; }
        a  { color: var(--mn-accent); text-underline-offset: 3px; }
        strong { font-weight: 700; }
        em     { font-style: italic; color: var(--mn-dim); }
        code {
          font-family: "SF Mono", Menlo, Consolas, monospace;
          font-size: .875em;
          background: var(--mn-code-bg);
          border-radius: 3px;
          padding: .1em .4em;
        }
        pre {
          background: color-mix(in srgb, var(--mn-text) 6%, transparent);
          border: 1px solid color-mix(in srgb, var(--mn-accent) 20%, transparent);
          border-radius: var(--mn-radius);
          padding: 1rem 1.25rem;
          overflow-x: auto;
          margin: 1em 0;
          font-size: .875em;
          line-height: 1.6;
        }
        pre code { background: none; padding: 0; border-radius: 0; }
        blockquote {
          border-left: 3px solid var(--mn-accent);
          margin: 1em 0;
          padding: .4em 1em;
          opacity: .75;
          font-style: italic;
        }
        ul, ol { margin: .6em 0 .6em 1.5em; }
        li     { margin: .2em 0; }
        hr {
          border: none;
          border-top: 1px solid color-mix(in srgb, var(--mn-accent) 30%, transparent);
          margin: 1.5em 0;
        }
        table { border-collapse: collapse; width: 100%; margin: 1em 0; font-size: .9em; }
        th, td { border: 1px solid color-mix(in srgb, var(--mn-dim) 40%, transparent);
                 padding: .45em .85em; text-align: left; }
        th { background: color-mix(in srgb, var(--mn-text) 8%, transparent);
             font-weight: 600; color: var(--mn-accent); }
        .wikilink { color: var(--mn-accent); text-decoration: underline dotted;
                    text-underline-offset: 3px; }
        .tag { color: var(--mn-accent); opacity: .85; font-size: .9em; }
        @media (prefers-color-scheme: light) {
          /* Invert Paper/Parchment moods in dark-mode HTML context */
        }
        @media print {
          body { background: #fff; color: #000; }
          a    { color: #0066cc; }
          pre  { border: 1px solid #ccc; background: #f8f8f8; }
        }
        """
    }
}

// MARK: – PDFRenderer

/// Renders HTML to PDF via a hidden WKWebView.
/// WKWebView rendering is Metal-accelerated on Apple Silicon.
final class PDFRenderer: NSObject, WKNavigationDelegate {
    private let webView:   WKWebView
    private let outputURL: URL
    private let callback:  (Error?) -> Void
    private var retained:  PDFRenderer?

    private init(html: String, outputURL: URL, completion: @escaping (Error?) -> Void) {
        let config = WKWebViewConfiguration()
        self.webView   = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1200),
                                   configuration: config)
        self.outputURL = outputURL
        self.callback  = completion
        super.init()
        self.retained  = self
        webView.navigationDelegate = self

        // Attach to an off-screen window for layout
        let win = NSWindow(contentRect: NSRect(x: -9999, y: -9999, width: 800, height: 1200),
                           styleMask: .borderless, backing: .buffered, defer: true)
        win.contentView?.addSubview(webView)
        webView.loadHTMLString(html, baseURL: FileManager.default.homeDirectoryForCurrentUser)
    }

    static func render(html: String, to url: URL,
                       completion: @escaping (Error?) -> Void) {
        _ = PDFRenderer(html: html, outputURL: url, completion: completion)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let config     = WKPDFConfiguration()
        // A4 in points (595 × 842)
        config.rect    = CGRect(x: 0, y: 0, width: 595, height: 842)
        let dest       = outputURL
        webView.createPDF(configuration: config) { [weak self] result in
            switch result {
            case .success(let data):
                do {
                    try data.write(to: dest)
                    self?.callback(nil)
                } catch {
                    self?.callback(error)
                }
            case .failure(let err):
                self?.callback(err)
            }
            self?.retained = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        callback(error); retained = nil
    }
}
