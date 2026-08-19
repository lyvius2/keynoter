import Foundation

/// Talks to Keynote through AppleScript for the operations `/create`, `/edit`,
/// `/open`, `/save`, `/save-as`, `/close`, and `/status` need.
///
/// Every operation is a two-step composition: a `static` builder produces the
/// AppleScript string, then `executor.run(_:)` runs it. Splitting it that way
/// keeps the AppleScript text testable without ever touching a live Keynote —
/// the tests pin exact scripts, following the same pattern that Phase 3's
/// `AppleScriptRenderer` will use for every `PresentationAction`.
struct KeynoteController: Sendable {

    let executor: AppleScriptExecutor

    init(executor: AppleScriptExecutor = AppleScriptExecutor()) {
        self.executor = executor
    }

    // MARK: - Operations

    /// Creates a new empty document and saves it at `path`.
    func createDocument(at path: URL) async throws {
        _ = try await executor.run(Self.createScript(path: path.path))
    }

    /// Opens the document at `path`.
    func openDocument(at path: URL) async throws {
        _ = try await executor.run(Self.openScript(path: path.path))
    }

    /// Saves the front document in place.
    func saveDocument() async throws {
        _ = try await executor.run(Self.saveScript())
    }

    /// Saves the front document to a new path.
    func saveDocumentAs(at path: URL) async throws {
        _ = try await executor.run(Self.saveAsScript(path: path.path))
    }

    /// Closes the front document. `save == true` writes pending changes,
    /// `false` discards them.
    func closeDocument(save: Bool) async throws {
        _ = try await executor.run(Self.closeScript(save: save))
    }

    /// Brings Keynote to the foreground.
    func activate() async throws {
        _ = try await executor.run(Self.activateScript())
    }

    /// Reads the front document's slides in order, one `SlideInfo` per slide.
    func readSlideMetadata() async throws -> [SlideInfo] {
        let output = try await executor.run(Self.readSlidesScript())
        return Self.parseSlideMetadata(output)
    }

    // MARK: - Script builders (internal for tests)

    static func createScript(path: String) -> String {
        let quoted = escapeAppleScriptString(path)
        return """
        tell application "Keynote"
            activate
            set newDoc to make new document
            save newDoc in POSIX file "\(quoted)"
        end tell
        """
    }

    static func openScript(path: String) -> String {
        let quoted = escapeAppleScriptString(path)
        return """
        tell application "Keynote"
            activate
            open POSIX file "\(quoted)"
        end tell
        """
    }

    static func saveScript() -> String {
        """
        tell application "Keynote"
            save front document
        end tell
        """
    }

    static func saveAsScript(path: String) -> String {
        let quoted = escapeAppleScriptString(path)
        return """
        tell application "Keynote"
            save front document in POSIX file "\(quoted)"
        end tell
        """
    }

    static func closeScript(save: Bool) -> String {
        let savingClause = save ? "yes" : "no"
        return """
        tell application "Keynote"
            close front document saving \(savingClause)
        end tell
        """
    }

    static func activateScript() -> String {
        """
        tell application "Keynote"
            activate
        end tell
        """
    }

    /// Emits `<index>\t<title>\n` per slide. `default title item` is wrapped
    /// in `try`/`end try` so layouts without a title placeholder still produce
    /// a row (title = "") instead of aborting the loop.
    static func readSlidesScript() -> String {
        """
        tell application "Keynote"
            set output to ""
            set doc to front document
            set slideCount to count of slides of doc
            repeat with i from 1 to slideCount
                set slideTitle to ""
                try
                    set slideTitle to object text of default title item of slide i of doc
                end try
                set output to output & i & tab & slideTitle & linefeed
            end repeat
            return output
        end tell
        """
    }

    // MARK: - Parsing / escaping (internal for tests)

    /// Parses the output of `readSlidesScript()`: one slide per line, index
    /// and title separated by a tab. Lines whose first field is not an Int
    /// are skipped. A title may contain tabs — only the first tab is treated
    /// as a delimiter.
    static func parseSlideMetadata(_ output: String) -> [SlideInfo] {
        var result: [SlideInfo] = []
        for line in output.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard let indexPart = parts.first,
                  let index = Int(indexPart.trimmingCharacters(in: .whitespaces))
            else { continue }
            let title = parts.count > 1 ? String(parts[1]) : ""
            result.append(SlideInfo(index: index, title: title))
        }
        return result
    }

    /// Escapes a string for safe interpolation into an AppleScript `"..."`
    /// literal. Backslash must be handled first; the other replacements must
    /// not re-escape backslashes we just wrote.
    static func escapeAppleScriptString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
