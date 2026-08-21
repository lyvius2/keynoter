import Foundation
import Testing
@testable import Keynoter

/// Fixed id so the pinned scripts stay byte-stable.
private let deck = DocumentRef(id: "TEST-DOC-ID")
private let deckSpecifier = "document id \"TEST-DOC-ID\""

@Suite("KeynoteController scripts")
struct KeynoteControllerScriptTests {

    @Test("createScript pins its exact AppleScript")
    func createScript() {
        let expected = """
        tell application "Keynote"
            activate
            set newDoc to make new document
            save newDoc in POSIX file "/tmp/demo.key"
            return id of newDoc
        end tell
        """
        #expect(KeynoteController.createScript(path: "/tmp/demo.key") == expected)
    }

    @Test("openScript pins its exact AppleScript")
    func openScript() {
        let expected = """
        tell application "Keynote"
            activate
            set openedDoc to open POSIX file "/tmp/demo.key"
            return id of openedDoc
        end tell
        """
        #expect(KeynoteController.openScript(path: "/tmp/demo.key") == expected)
    }

    @Test("saveScript targets the tracked document, not the front one")
    func saveScript() {
        let expected = """
        tell application "Keynote"
            save \(deckSpecifier)
        end tell
        """
        #expect(KeynoteController.saveScript(document: deck) == expected)
    }

    @Test("saveAsScript writes the copy, drops the original, and reopens the copy")
    func saveAsScript() {
        let expected = """
        tell application "Keynote"
            set sourceDoc to \(deckSpecifier)
            save sourceDoc in POSIX file "/tmp/copy.key"
            close sourceDoc saving no
            set newDoc to open POSIX file "/tmp/copy.key"
            return id of newDoc
        end tell
        """
        #expect(KeynoteController.saveAsScript(document: deck, path: "/tmp/copy.key") == expected)
    }

    @Test("exportScript names the document by id, never the front one", arguments: [
        (ExportFormat.pdf, "/tmp/deck.pdf", "PDF"),
        (.pptx, "/tmp/deck.pptx", "Microsoft PowerPoint")
    ])
    func exportScript(format: ExportFormat, path: String, constant: String) {
        let expected = """
        tell application "Keynote"
            export \(deckSpecifier) to POSIX file "\(path)" as \(constant)
        end tell
        """
        #expect(KeynoteController.exportScript(document: deck, path: path, format: format) == expected)
        // The whole point of the id: an export must not follow whichever window
        // the user last clicked.
        #expect(!KeynoteController.exportScript(document: deck, path: path, format: format)
            .contains("front document"))
    }

    @Test("An export path with quotes is escaped like every other literal")
    func exportScriptEscapesPath() {
        let script = KeynoteController.exportScript(
            document: deck,
            path: #"/tmp/say "hi".pdf"#,
            format: .pdf
        )
        #expect(script.contains(#"POSIX file "/tmp/say \"hi\".pdf""#))
    }

    @Test("closeScript with save uses `saving yes`")
    func closeScriptSave() {
        let expected = """
        tell application "Keynote"
            close \(deckSpecifier) saving yes
        end tell
        """
        #expect(KeynoteController.closeScript(document: deck, save: true) == expected)
    }

    @Test("closeScript without save uses `saving no`")
    func closeScriptDiscard() {
        let expected = """
        tell application "Keynote"
            close \(deckSpecifier) saving no
        end tell
        """
        #expect(KeynoteController.closeScript(document: deck, save: false) == expected)
    }

    @Test("activateScript raises the tracked document, not just the app")
    func activateScript() {
        let expected = """
        tell application "Keynote"
            activate
            set targetFile to file of \(deckSpecifier)
            open targetFile
        end tell
        """
        #expect(KeynoteController.activateScript(document: deck) == expected)
    }

    @Test("readSlidesScript emits index\\ttitle\\n rows and tolerates missing titles")
    func readSlidesScript() {
        let expected = """
        tell application "Keynote"
            set output to ""
            set doc to \(deckSpecifier)
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
        #expect(KeynoteController.readSlidesScript(document: deck) == expected)
    }
}

@Suite("KeynoteController escaping")
struct KeynoteControllerEscapingTests {

    @Test("A plain string is untouched")
    func plainString() {
        #expect(KeynoteController.escapeAppleScriptString("/tmp/demo.key") == "/tmp/demo.key")
    }

    @Test("A double quote is prefixed with a backslash")
    func escapeQuote() {
        // Input: a"b   → Output: a\"b
        #expect(KeynoteController.escapeAppleScriptString(#"a"b"#) == #"a\"b"#)
    }

    @Test("A literal backslash doubles up")
    func escapeBackslash() {
        // Input: a\b   → Output: a\\b
        #expect(KeynoteController.escapeAppleScriptString(#"a\b"#) == #"a\\b"#)
    }

    @Test("Backslash is escaped before quote, so an already-escaped quote is preserved")
    func escapeBackslashBeforeQuote() {
        // Input: a\"b (three chars: a, \, ", b) → Output: a\\\"b
        #expect(KeynoteController.escapeAppleScriptString(#"a\"b"#) == #"a\\\"b"#)
    }

    @Test("Newlines and tabs escape into their AppleScript forms")
    func escapeControls() {
        #expect(KeynoteController.escapeAppleScriptString("a\nb") == #"a\nb"#)
        #expect(KeynoteController.escapeAppleScriptString("a\rb") == #"a\rb"#)
        #expect(KeynoteController.escapeAppleScriptString("a\tb") == #"a\tb"#)
    }

    @Test("Paths with spaces flow through untouched")
    func pathWithSpaces() {
        let path = "/Users/me/My Documents/deck one.key"
        #expect(KeynoteController.escapeAppleScriptString(path) == path)
    }

    @Test("A path containing a quote embeds cleanly into the AppleScript template")
    func escapingInTemplate() {
        let path = #"/tmp/weird "name".key"#
        let script = KeynoteController.createScript(path: path)
        // The literal that lands inside the AppleScript `"..."` must be:
        //     /tmp/weird \"name\".key
        #expect(script.contains(#"POSIX file "/tmp/weird \"name\".key""#))
    }
}

@Suite("KeynoteController slide metadata parsing")
struct KeynoteControllerParsingTests {

    @Test("Empty output produces no slides")
    func empty() {
        #expect(KeynoteController.parseSlideMetadata("") == [])
    }

    @Test("A single row parses into one SlideInfo")
    func singleSlide() {
        let output = "1\tIntro\n"
        #expect(KeynoteController.parseSlideMetadata(output) == [
            SlideInfo(index: 1, title: "Intro")
        ])
    }

    @Test("Multiple rows preserve order")
    func multipleSlides() {
        let output = "1\tIntro\n2\tArchitecture\n3\tMigration Plan\n"
        #expect(KeynoteController.parseSlideMetadata(output) == [
            SlideInfo(index: 1, title: "Intro"),
            SlideInfo(index: 2, title: "Architecture"),
            SlideInfo(index: 3, title: "Migration Plan")
        ])
    }

    @Test("A missing title becomes an empty string")
    func missingTitle() {
        let output = "1\t\n2\tHas title\n"
        #expect(KeynoteController.parseSlideMetadata(output) == [
            SlideInfo(index: 1, title: ""),
            SlideInfo(index: 2, title: "Has title")
        ])
    }

    @Test("A title containing a tab keeps the rest of the field intact")
    func titleWithTab() {
        let output = "1\thas\ttab\n"
        #expect(KeynoteController.parseSlideMetadata(output) == [
            SlideInfo(index: 1, title: "has\ttab")
        ])
    }

    @Test("Rows whose first field is not an Int are skipped")
    func invalidIndex() {
        let output = "one\tbad\n2\tgood\n"
        #expect(KeynoteController.parseSlideMetadata(output) == [
            SlideInfo(index: 2, title: "good")
        ])
    }

    @Test("Blank and CR-only lines are ignored")
    func blankLines() {
        let output = "\n1\tIntro\n\n2\tArch\n\n"
        #expect(KeynoteController.parseSlideMetadata(output) == [
            SlideInfo(index: 1, title: "Intro"),
            SlideInfo(index: 2, title: "Arch")
        ])
    }
}
