import Foundation
import Testing
@testable import Keynoter

private let deck = DocumentRef(id: "TEST-DOC-ID")
private let deckSpecifier = "document id \"TEST-DOC-ID\""

/// Covers reading one slide back out of Keynote — the script that asks for it
/// and the parser that turns the answer into a `SlideSpec`. This is the input
/// `InverseBuilder` needs to make a destructive action undoable.
@Suite("Slide readback")
struct SlideReadbackTests {

    private let separator = String(KeynoteController.slideFieldSeparator)

    private func output(
        titleFlag: String,
        bodyFlag: String,
        title: String,
        body: String,
        notes: String
    ) -> String {
        [titleFlag, bodyFlag, title, body, notes].joined(separator: separator)
    }

    // MARK: - Script

    @Test("readSlideScript pins its exact AppleScript")
    func readSlideScript() {
        let expected = """
        tell application "Keynote"
            set sep to ASCII character 31
            set theSlide to slide 3 of \(deckSpecifier)
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
        #expect(KeynoteController.readSlideScript(document: deck, index: 3) == expected)
    }

    // MARK: - Parsing

    @Test("A slide with a title and bullets parses as titleAndBody")
    func parseTitleAndBody() {
        let spec = KeynoteController.parseSlide(
            output(
                titleFlag: "1",
                bodyFlag: "1",
                title: "Architecture",
                body: "AS-IS\nTO-BE",
                notes: "Keep it short"
            )
        )

        #expect(spec.layout == .titleAndBody)
        #expect(spec.title == "Architecture")
        #expect(spec.body == ["AS-IS", "TO-BE"])
        #expect(spec.speakerNotes == "Keep it short")
    }

    @Test("A slide with only a title placeholder parses as title")
    func parseTitleOnly() {
        let spec = KeynoteController.parseSlide(
            output(titleFlag: "1", bodyFlag: "0", title: "Section", body: "", notes: "")
        )

        #expect(spec.layout == .title)
        #expect(spec.title == "Section")
        #expect(spec.body.isEmpty)
        #expect(spec.speakerNotes == nil)
    }

    @Test("A slide with no placeholders parses as blank")
    func parseBlank() {
        let spec = KeynoteController.parseSlide(
            output(titleFlag: "0", bodyFlag: "0", title: "", body: "", notes: "")
        )

        #expect(spec.layout == .blank)
        #expect(spec.title == nil)
        #expect(spec.body.isEmpty)
    }

    @Test("An empty title placeholder is not the same as a missing one")
    func emptyPlaceholderIsNotMissing() {
        let empty = KeynoteController.parseSlide(
            output(titleFlag: "1", bodyFlag: "0", title: "", body: "", notes: "")
        )
        let missing = KeynoteController.parseSlide(
            output(titleFlag: "0", bodyFlag: "0", title: "", body: "", notes: "")
        )

        #expect(empty.title == "")
        #expect(missing.title == nil)
    }

    @Test("Newlines inside a title survive, because fields are separator-delimited")
    func multilineTitle() {
        let spec = KeynoteController.parseSlide(
            output(
                titleFlag: "1",
                bodyFlag: "1",
                title: "Two\nlines",
                body: "One",
                notes: "A\nB\nC"
            )
        )

        #expect(spec.title == "Two\nlines")
        #expect(spec.body == ["One"])
        #expect(spec.speakerNotes == "A\nB\nC")
    }

    @Test("Malformed output yields a blank spec instead of a wrong one")
    func malformedOutput() {
        let spec = KeynoteController.parseSlide("not a slide")

        #expect(spec.layout == .blank)
        #expect(spec.title == nil)
        #expect(spec.body.isEmpty)
        #expect(spec.speakerNotes == nil)
    }

    // MARK: - Body text

    @Test("Body text splits on any newline form Keynote returns")
    func bodySplitsOnEveryNewline() {
        #expect(KeynoteController.parseBodyText("a\nb") == ["a", "b"])
        #expect(KeynoteController.parseBodyText("a\rb") == ["a", "b"])
        #expect(KeynoteController.parseBodyText("a\r\nb") == ["a", "b"])
    }

    @Test("Trailing blank lines are dropped, interior ones are kept")
    func bodyTrimsTrailingBlanks() {
        #expect(KeynoteController.parseBodyText("a\n\nb\n\n") == ["a", "", "b"])
        #expect(KeynoteController.parseBodyText("") == [])
        #expect(KeynoteController.parseBodyText("\n\n") == [])
    }

    @Test("Body text round-trips through the renderer's newline join")
    func bodyRoundTripsWithRenderer() {
        let bullets = ["First point", "Second point", "Third point"]
        #expect(KeynoteController.parseBodyText(bullets.joined(separator: "\n")) == bullets)
    }
}