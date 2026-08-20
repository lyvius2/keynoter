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

    /// Every mutating operation returns the AppleScript it ran, so the caller
    /// can hand it to `Session.recordAppleScript(_:)` and `/script` shows what
    /// actually executed rather than a rebuilt approximation.

    /// Creates a new empty document and saves it at `path`.
    @discardableResult
    func createDocument(at path: URL) async throws -> String {
        try await run(Self.createScript(path: path.path))
    }

    /// Opens the document at `path`.
    @discardableResult
    func openDocument(at path: URL) async throws -> String {
        try await run(Self.openScript(path: path.path))
    }

    /// Saves the front document in place.
    @discardableResult
    func saveDocument() async throws -> String {
        try await run(Self.saveScript())
    }

    /// Saves the front document to a new path.
    @discardableResult
    func saveDocumentAs(at path: URL) async throws -> String {
        try await run(Self.saveAsScript(path: path.path))
    }

    /// Closes the front document. `save == true` writes pending changes,
    /// `false` discards them.
    @discardableResult
    func closeDocument(save: Bool) async throws -> String {
        try await run(Self.closeScript(save: save))
    }

    /// Brings Keynote to the foreground.
    @discardableResult
    func activate() async throws -> String {
        try await run(Self.activateScript())
    }

    /// Runs a script `AppleScriptRenderer` produced and returns the same script.
    /// Routing rendered actions through the controller keeps every Apple Event
    /// the app sends behind one type.
    @discardableResult
    func execute(_ script: String) async throws -> String {
        try await run(script)
    }

    /// Reads the front document's slides in order, one `SlideInfo` per slide.
    func readSlideMetadata() async throws -> [SlideInfo] {
        let output = try await executor.run(Self.readSlidesScript())
        return Self.parseSlideMetadata(output)
    }

    /// Reads one slide's full text content back out of the front document.
    ///
    /// Used to capture the "before" state that `InverseBuilder` needs to make
    /// a destructive action undoable.
    func readSlide(at index: Int) async throws -> SlideSpec {
        let output = try await executor.run(Self.readSlideScript(index: index))
        return Self.parseSlide(output)
    }

    /// Runs `script` and returns it unchanged, discarding stdout. Every
    /// mutating operation above is this plus a script builder.
    @discardableResult
    private func run(_ script: String) async throws -> String {
        _ = try await executor.run(script)
        return script
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

    /// Reads title, body, presenter notes and placeholder presence for one slide.
    ///
    /// Fields are joined with ASCII unit separator (0x1F) rather than newlines:
    /// titles, body text and notes can all contain line breaks, which would make
    /// `readSlidesScript()`'s line-per-slide format ambiguous here.
    ///
    /// The two leading flags record whether the title / body placeholder exists
    /// at all. A missing placeholder and an empty one both read back as "",
    /// and the difference matters — it is how `parseSlide(_:)` infers the
    /// layout, and therefore which placeholders a restored slide may write to.
    static func readSlideScript(index: Int) -> String {
        """
        tell application "Keynote"
            set sep to ASCII character 31
            set theSlide to slide \(index) of front document
            set titleFlag to "0"
            set slideTitle to ""
            try
                set slideTitle to object text of default title item of theSlide
                set titleFlag to "1"
            end try
            set bodyFlag to "0"
            set slideBody to ""
            try
                set slideBody to object text of default body item of theSlide
                set bodyFlag to "1"
            end try
            set slideNotes to ""
            try
                set slideNotes to presenter notes of theSlide
            end try
            return titleFlag & sep & bodyFlag & sep & slideTitle & sep & slideBody & sep & slideNotes
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

    /// Field separator used by `readSlideScript(index:)`.
    static let slideFieldSeparator: Character = "\u{1F}"

    /// Parses the output of `readSlideScript(index:)`.
    ///
    /// Malformed output yields a blank spec rather than throwing: the caller
    /// uses this to build an undo step, and an empty spec makes that undo
    /// obviously wrong rather than silently half-right.
    static func parseSlide(_ output: String) -> SlideSpec {
        let parts = output.split(
            separator: slideFieldSeparator,
            maxSplits: 4,
            omittingEmptySubsequences: false
        )
        guard parts.count == 5 else { return SlideSpec(layout: .blank) }

        let hasTitle = parts[0] == "1"
        let hasBody = parts[1] == "1"
        let notes = String(parts[4])

        return SlideSpec(
            layout: hasTitle ? (hasBody ? .titleAndBody : .title) : .blank,
            title: hasTitle ? String(parts[2]) : nil,
            body: hasBody ? parseBodyText(String(parts[3])) : [],
            speakerNotes: notes.isEmpty ? nil : notes
        )
    }

    /// Splits a body placeholder's text back into bullets — the inverse of the
    /// renderer joining them with newlines. Keynote returns CR, LF or CRLF
    /// depending on how the text was entered, so any newline splits.
    /// Trailing blank lines are dropped; interior ones are kept, because an
    /// empty bullet in the middle of a list was deliberate.
    static func parseBodyText(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }

    /// Escapes a string for safe interpolation into an AppleScript `"..."`
    /// literal. Forwards to `AppleScriptString`, which `AppleScriptRenderer`
    /// also uses — there is one escaper in the project, not two.
    static func escapeAppleScriptString(_ s: String) -> String {
        AppleScriptString.escape(s)
    }
}
