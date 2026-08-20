import Foundation
import Testing
@testable import Keynoter

@Suite("AppleScriptRenderer — createPresentation")
struct AppleScriptRendererCreatePresentationTests {

    @Test("without a theme, makes a plain document and titles slide 1")
    func withoutTheme() {
        let expected = """
        tell application "Keynote"
            set newDoc to make new document
            tell slide 1 of newDoc
                set object text of default title item to "Q3 Review"
            end tell
        end tell
        """
        #expect(AppleScriptRenderer.render(.createPresentation(title: "Q3 Review", theme: nil)) == expected)
    }

    @Test("with a theme, names it in the document properties")
    func withTheme() {
        let expected = """
        tell application "Keynote"
            set newDoc to make new document with properties {document theme:theme "Modern Portfolio"}
            tell slide 1 of newDoc
                set object text of default title item to "Q3 Review"
            end tell
        end tell
        """
        let action = PresentationAction.createPresentation(title: "Q3 Review", theme: "Modern Portfolio")
        #expect(AppleScriptRenderer.render(action) == expected)
    }

    @Test("an empty title leaves the theme's placeholder alone")
    func emptyTitle() {
        let expected = """
        tell application "Keynote"
            set newDoc to make new document
        end tell
        """
        #expect(AppleScriptRenderer.render(.createPresentation(title: "", theme: nil)) == expected)
    }
}

@Suite("AppleScriptRenderer — addSlide")
struct AppleScriptRendererAddSlideTests {

    @Test("index 3 inserts after slide 2")
    func insertsAfterPreviousSlide() {
        let spec = SlideSpec(layout: .titleAndBody, title: "Agenda", body: ["Scope", "Timeline"])
        let expected = """
        tell application "Keynote"
            set newSlide to make new slide at after slide 2 of document 1
            tell newSlide
                set object text of default title item to "Agenda"
                set object text of default body item to "Scope\\nTimeline"
            end tell
        end tell
        """
        #expect(AppleScriptRenderer.render(.addSlide(index: 3, spec: spec)) == expected)
    }

    @Test("index 1 inserts at the beginning, which works on an empty document")
    func insertsAtBeginning() {
        let spec = SlideSpec(layout: .title, title: "Keynoter")
        let expected = """
        tell application "Keynote"
            set newSlide to make new slide at beginning of document 1
            tell newSlide
                set object text of default title item to "Keynoter"
            end tell
        end tell
        """
        #expect(AppleScriptRenderer.render(.addSlide(index: 1, spec: spec)) == expected)
    }

    @Test("bullets join with newlines into the body placeholder")
    func bulletsJoinWithNewlines() {
        let spec = SlideSpec(layout: .titleAndBody, title: "Steps", body: ["One", "Two", "Three"])
        let rendered = AppleScriptRenderer.render(.addSlide(index: 2, spec: spec))
        #expect(rendered.contains(#"set object text of default body item to "One\nTwo\nThree""#))
    }

    @Test("speaker notes render as presenter notes")
    func speakerNotes() {
        let spec = SlideSpec(layout: .title, title: "Intro", speakerNotes: "Pause here.")
        let expected = """
        tell application "Keynote"
            set newSlide to make new slide at after slide 1 of document 1
            tell newSlide
                set object text of default title item to "Intro"
                set presenter notes to "Pause here."
            end tell
        end tell
        """
        #expect(AppleScriptRenderer.render(.addSlide(index: 2, spec: spec)) == expected)
    }

    @Test("a blank layout writes no placeholders")
    func blankLayout() {
        let spec = SlideSpec(layout: .blank)
        let expected = """
        tell application "Keynote"
            set newSlide to make new slide at after slide 4 of document 1
        end tell
        """
        #expect(AppleScriptRenderer.render(.addSlide(index: 5, spec: spec)) == expected)
    }

    @Test("a blank layout ignores title and body even when the spec carries them")
    func blankLayoutIgnoresContent() {
        let spec = SlideSpec(layout: .blank, title: "Ignored", body: ["Also ignored"])
        let rendered = AppleScriptRenderer.render(.addSlide(index: 2, spec: spec))
        #expect(!rendered.contains("Ignored"))
        #expect(!rendered.contains("default body item"))
    }

    @Test("a title layout ignores body items")
    func titleLayoutIgnoresBody() {
        let spec = SlideSpec(layout: .title, title: "Section", body: ["Dropped"])
        let rendered = AppleScriptRenderer.render(.addSlide(index: 2, spec: spec))
        #expect(rendered.contains(#"default title item to "Section""#))
        #expect(!rendered.contains("default body item"))
    }

    @Test("empty content on a new slide writes nothing — there is nothing to clear")
    func emptyContentIsSkipped() {
        let spec = SlideSpec(layout: .titleAndBody, title: "", body: [], speakerNotes: "")
        let expected = """
        tell application "Keynote"
            set newSlide to make new slide at after slide 1 of document 1
        end tell
        """
        #expect(AppleScriptRenderer.render(.addSlide(index: 2, spec: spec)) == expected)
    }
}

@Suite("AppleScriptRenderer — updateSlide")
struct AppleScriptRendererUpdateSlideTests {

    @Test("sets both fields when both are given")
    func bothFields() {
        let expected = """
        tell application "Keynote"
            tell slide 3 of document 1
                set object text of default title item to "Results"
                set object text of default body item to "Up 12%"
            end tell
        end tell
        """
        let action = PresentationAction.updateSlide(index: 3, title: "Results", body: ["Up 12%"])
        #expect(AppleScriptRenderer.render(action) == expected)
    }

    @Test("a nil field is left alone")
    func nilFieldIsSkipped() {
        let expected = """
        tell application "Keynote"
            tell slide 2 of document 1
                set object text of default title item to "Renamed"
            end tell
        end tell
        """
        let action = PresentationAction.updateSlide(index: 2, title: "Renamed", body: nil)
        #expect(AppleScriptRenderer.render(action) == expected)
    }

    @Test("an empty body clears the placeholder rather than skipping it")
    func emptyBodyClears() {
        let expected = """
        tell application "Keynote"
            tell slide 2 of document 1
                set object text of default body item to ""
            end tell
        end tell
        """
        let action = PresentationAction.updateSlide(index: 2, title: nil, body: [])
        #expect(AppleScriptRenderer.render(action) == expected)
    }

    @Test("an empty title clears the placeholder rather than skipping it")
    func emptyTitleClears() {
        let expected = """
        tell application "Keynote"
            tell slide 2 of document 1
                set object text of default title item to ""
            end tell
        end tell
        """
        let action = PresentationAction.updateSlide(index: 2, title: "", body: nil)
        #expect(AppleScriptRenderer.render(action) == expected)
    }
}

@Suite("AppleScriptRenderer — deleteSlide, moveSlide, updateSpeakerNotes")
struct AppleScriptRendererRemainingActionTests {

    @Test("deleteSlide pins its exact AppleScript")
    func deleteSlide() {
        let expected = """
        tell application "Keynote"
            delete slide 4 of document 1
        end tell
        """
        #expect(AppleScriptRenderer.render(.deleteSlide(index: 4)) == expected)
    }

    @Test("moving down the deck lands after the destination slide")
    func moveDown() {
        let expected = """
        tell application "Keynote"
            move slide 2 of document 1 to after slide 5 of document 1
        end tell
        """
        #expect(AppleScriptRenderer.render(.moveSlide(from: 2, to: 5)) == expected)
    }

    @Test("moving up the deck lands before the destination slide")
    func moveUp() {
        let expected = """
        tell application "Keynote"
            move slide 5 of document 1 to before slide 2 of document 1
        end tell
        """
        #expect(AppleScriptRenderer.render(.moveSlide(from: 5, to: 2)) == expected)
    }

    @Test("moving a slide onto itself renders a no-op")
    func moveToSamePosition() {
        let expected = """
        tell application "Keynote"
            -- slide 3 is already at position 3; nothing to do
        end tell
        """
        #expect(AppleScriptRenderer.render(.moveSlide(from: 3, to: 3)) == expected)
    }

    @Test("updateSpeakerNotes pins its exact AppleScript")
    func updateSpeakerNotes() {
        let expected = """
        tell application "Keynote"
            set presenter notes of slide 3 of document 1 to "Slow down here."
        end tell
        """
        let action = PresentationAction.updateSpeakerNotes(index: 3, notes: "Slow down here.")
        #expect(AppleScriptRenderer.render(action) == expected)
    }

    @Test("empty speaker notes clear the field")
    func emptySpeakerNotesClear() {
        let expected = """
        tell application "Keynote"
            set presenter notes of slide 1 of document 1 to ""
        end tell
        """
        #expect(AppleScriptRenderer.render(.updateSpeakerNotes(index: 1, notes: "")) == expected)
    }
}

@Suite("AppleScriptRenderer — escaping")
struct AppleScriptRendererEscapingTests {

    @Test("quotes in a title are escaped, not dropped")
    func escapesQuotes() {
        let action = PresentationAction.updateSlide(index: 1, title: #"The "Big" Idea"#, body: nil)
        let expected = """
        tell application "Keynote"
            tell slide 1 of document 1
                set object text of default title item to "The \\"Big\\" Idea"
            end tell
        end tell
        """
        #expect(AppleScriptRenderer.render(action) == expected)
    }

    @Test("backslashes are escaped before anything else")
    func escapesBackslashes() {
        let action = PresentationAction.updateSlide(index: 1, title: #"C:\path"#, body: nil)
        #expect(AppleScriptRenderer.render(action).contains(#"to "C:\\path""#))
    }

    @Test("a backslash followed by a quote does not double-escape")
    func escapesBackslashThenQuote() {
        let action = PresentationAction.updateSlide(index: 1, title: #"a\"b"#, body: nil)
        #expect(AppleScriptRenderer.render(action).contains(#"to "a\\\"b""#))
    }

    @Test("a quote cannot break out of the string literal")
    func quoteCannotBreakOut() {
        // Text engineered to close the literal and append a shell call. Every
        // quote in it must come back escaped, so the payload stays inert data.
        let hostile = #"" & (do shell script "echo pwned") & ""#
        let expected = """
        tell application "Keynote"
            tell slide 1 of document 1
                set object text of default title item to "\\" & (do shell script \\"echo pwned\\") & \\""
            end tell
        end tell
        """
        let rendered = AppleScriptRenderer.render(.updateSlide(index: 1, title: hostile, body: nil))
        #expect(rendered == expected)

        // Belt and braces: inside the value, no quote stands unescaped.
        let value = rendered.components(separatedBy: "default title item to ")[1]
        #expect(unescapedQuoteCount(in: value) == 2, "only the two delimiters may be unescaped")
    }

    /// Counts `"` characters not preceded by a backslash.
    private func unescapedQuoteCount(in s: String) -> Int {
        var count = 0
        var previous: Character?
        for character in s {
            if character == "\"", previous != "\\" { count += 1 }
            // A doubled backslash is itself escaped, so it cannot shield a quote.
            previous = (character == "\\" && previous == "\\") ? nil : character
        }
        return count
    }

    @Test("tabs and carriage returns are escaped in body items")
    func escapesWhitespaceControls() {
        let action = PresentationAction.updateSlide(index: 1, title: nil, body: ["a\tb", "c\rd"])
        #expect(AppleScriptRenderer.render(action).contains(#"to "a\tb\nc\rd""#))
    }

    @Test("a theme name is escaped too")
    func escapesTheme() {
        let action = PresentationAction.createPresentation(title: "T", theme: #"My "Theme""#)
        #expect(AppleScriptRenderer.render(action).contains(#"{document theme:theme "My \"Theme\""}"#))
    }

    @Test("speaker notes are escaped")
    func escapesSpeakerNotes() {
        let action = PresentationAction.updateSpeakerNotes(index: 1, notes: "Say \"hello\".")
        #expect(AppleScriptRenderer.render(action).contains(#"to "Say \"hello\".""#))
    }
}

/// One action of every kind, for the properties that must hold across all of them.
private let everyActionKind: [PresentationAction] = [
    .createPresentation(title: "T", theme: "White"),
    .createPresentation(title: "", theme: nil),
    .addSlide(index: 1, spec: SlideSpec(layout: .titleAndBody, title: "A", body: ["b"])),
    .addSlide(index: 4, spec: SlideSpec(layout: .blank)),
    .updateSlide(index: 2, title: "X", body: ["y"]),
    .deleteSlide(index: 2),
    .moveSlide(from: 1, to: 3),
    .moveSlide(from: 2, to: 2),
    .updateSpeakerNotes(index: 1, notes: "n"),
]

@Suite("AppleScriptRenderer — general properties")
struct AppleScriptRendererShapeTests {

    @Test("every action renders a balanced Keynote-only tell block", arguments: everyActionKind)
    func balancedTellBlock(action: PresentationAction) {
        let rendered = AppleScriptRenderer.render(action)
        let lines = rendered.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.first == #"tell application "Keynote""#)
        #expect(lines.last == "end tell")

        let opens = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("tell ") }.count
        let closes = lines.filter { $0.trimmingCharacters(in: .whitespaces) == "end tell" }.count
        #expect(opens == closes)
    }

    @Test("rendering is deterministic", arguments: everyActionKind)
    func deterministic(action: PresentationAction) {
        #expect(AppleScriptRenderer.render(action) == AppleScriptRenderer.render(action))
    }

    @Test("no action reaches for the shell or the system", arguments: everyActionKind)
    func noShellAccess(action: PresentationAction) {
        let rendered = AppleScriptRenderer.render(action)
        for forbidden in ["do shell script", "System Events", "tell application \"Finder\""] {
            #expect(!rendered.contains(forbidden))
        }
    }
}
