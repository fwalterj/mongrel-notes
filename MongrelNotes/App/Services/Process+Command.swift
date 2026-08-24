import Foundation

// MARK: – Process.runCommand

/// Synchronously runs a shell command and returns stdout, stderr, and exit code.
/// Designed for Apple Silicon — runs on efficiency cores when dispatched on a
/// background queue (`DispatchQueue.global(qos: .utility)`).
///
/// Usage:
/// ```swift
/// let result = Process.runCommand("/usr/bin/pandoc", args: ["--version"])
/// if result.exitCode == 0 { print(result.stdout) }
/// ```
extension Process {

    struct CommandResult {
        let stdout:   String
        let stderr:   String
        let exitCode: Int32
        var succeeded: Bool { exitCode == 0 }
    }

    /// Run a command at `launchPath` with `args`, optionally feeding `stdin` data.
    /// - Returns: `CommandResult` with stdout, stderr, and exit code.
    @discardableResult
    static func runCommand(
        _ launchPath: String,
        args: [String] = [],
        stdin stdinData: Data? = nil,
        environment: [String: String]? = nil
    ) -> CommandResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments     = args

        // Merge caller env with a clean $PATH that finds Homebrew on Apple Silicon
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = [
            "/opt/homebrew/bin",        // Apple Silicon Homebrew
            "/usr/local/bin",           // Intel Homebrew
            "/usr/bin", "/bin",
            "/usr/sbin", "/sbin",
        ].joined(separator: ":")
        if let extra = environment { env.merge(extra) { _, new in new } }
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError  = errPipe

        if let data = stdinData {
            let inPipe = Pipe()
            proc.standardInput = inPipe
            inPipe.fileHandleForWriting.write(data)
            inPipe.fileHandleForWriting.closeFile()
        }

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return CommandResult(stdout: "", stderr: error.localizedDescription, exitCode: -1)
        }

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8) ?? ""
        return CommandResult(stdout: out, stderr: err, exitCode: proc.terminationStatus)
    }

    // MARK: – Tool discovery

    /// Returns the full path to a CLI tool, searching Homebrew locations first.
    static func which(_ tool: String) -> String? {
        let searchPaths = [
            "/opt/homebrew/bin/\(tool)",
            "/usr/local/bin/\(tool)",
            "/usr/bin/\(tool)",
            "/bin/\(tool)",
        ]
        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        // Last-resort: ask the shell
        let result = runCommand("/usr/bin/which", args: [tool])
        let found  = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return found.isEmpty ? nil : found
    }

    static var pandocPath:      String? { which("pandoc") }
    static var libreOfficePath: String? { which("soffice") ?? which("libreoffice") }
    static var nodePath:        String? { which("node") }
    static var pythonPath:      String? { which("python3") ?? which("python") }
}
