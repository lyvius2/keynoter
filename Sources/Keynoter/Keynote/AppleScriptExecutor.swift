import Foundation

/// Errors from `AppleScriptExecutor.run(_:)`.
enum AppleScriptError: Error, Equatable {
    /// osascript ran but exited non-zero. `errorCode` is the AppleScript error
    /// number parsed from stderr when present (e.g. `-1743` = automation denied).
    case executionFailed(exitCode: Int32, errorCode: Int?, stdout: String, stderr: String)
    /// The osascript subprocess itself could not be launched.
    case launchFailed(reason: String)
}

/// Runs a pre-rendered AppleScript through `/usr/bin/osascript`.
///
/// Owns nothing but the subprocess invocation: string in, string out (or a
/// structured error). It never generates AppleScript itself — that is
/// `AppleScriptRenderer`'s job — and it never talks to Keynote directly.
struct AppleScriptExecutor: Sendable {

    static let osascriptPath = "/usr/bin/osascript"

    /// Runs `script` and returns its stdout, stripped of a single trailing
    /// newline. Throws `AppleScriptError.executionFailed` on non-zero exit.
    func run(_ script: String) async throws -> String {
        // The Process work blocks its thread; hop off the calling actor so a
        // long-running script cannot freeze the REPL.
        try await Task.detached(priority: .userInitiated) {
            try Self.runSync(script)
        }.value
    }

    // MARK: - Implementation

    /// Internal for tests; production callers use `run(_:)`.
    static func runSync(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: osascriptPath)
        // `-` tells osascript to read the program from stdin, so no shell
        // quoting rules ever get applied to the script text.
        process.arguments = ["-"]

        let stdin = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw AppleScriptError.launchFailed(reason: "\(error)")
        }

        // Feed the script and close stdin so osascript sees EOF and starts running.
        try? stdin.fileHandleForWriting.write(contentsOf: Data(script.utf8))
        try? stdin.fileHandleForWriting.close()

        // Synchronous reads are safe here because our scripts and their output
        // are small (a few slides of metadata at most) — well under the OS
        // pipe buffer, so neither side can ever block waiting for the other.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return stripTrailingNewline(stdoutText)
        }
        throw AppleScriptError.executionFailed(
            exitCode: process.terminationStatus,
            errorCode: parseErrorCode(from: stderrText),
            stdout: stdoutText.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - Helpers (internal for testability)

    /// Pulls the trailing `(-1234)` error number out of osascript's stderr.
    /// Returns nil if no such code is present.
    static func parseErrorCode(from stderr: String) -> Int? {
        guard let lastLine = stderr
            .split(whereSeparator: \.isNewline)
            .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }
        let trimmed = lastLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(")") else { return nil }
        guard let open = trimmed.lastIndex(of: "(") else { return nil }
        let start = trimmed.index(after: open)
        let end = trimmed.index(before: trimmed.endIndex)
        guard start < end else { return nil }
        return Int(trimmed[start..<end])
    }

    /// Strips a single trailing newline (LF or CRLF) so callers see the
    /// AppleScript return value without osascript's tail newline. `"\r\n"` is
    /// a single grapheme in Swift, so one `dropLast()` handles both forms.
    static func stripTrailingNewline(_ text: String) -> String {
        guard let last = text.last, last.isNewline else { return text }
        return String(text.dropLast())
    }
}

extension AppleScriptError {

    /// A one-line, human-readable rendering of the error suitable for the
    /// REPL. Well-known Apple Events codes get bespoke text; anything else
    /// falls back to osascript's stderr.
    var userMessage: String {
        switch self {
        case .executionFailed(_, let code, _, let stderr):
            switch code {
            case -1743:
                return "Automation permission denied. Grant this terminal permission to control Keynote in System Settings > Privacy & Security > Automation."
            case -1728:
                return "Keynote couldn't find that object — is a document open?"
            case -1712:
                return "Keynote didn't respond in time."
            default:
                return stderr.isEmpty ? "AppleScript execution failed." : stderr
            }
        case .launchFailed(let reason):
            return "Could not launch osascript: \(reason)"
        }
    }
}
