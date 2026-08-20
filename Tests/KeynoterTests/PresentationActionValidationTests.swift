import Testing
@testable import Keynoter

@Suite("ValidationEngine – index bounds")
struct ValidationIndexTests {

    private let context3 = ValidationContext(slideCount: 3)
    private let contextEmpty = ValidationContext(slideCount: 0)

    // MARK: - updateSlide / deleteSlide / updateSpeakerNotes share the 1...N rule

    @Test("An index inside 1...count passes for updateSlide")
    func updateInBounds() throws {
        try ValidationEngine.validate(
            .updateSlide(index: 2, title: "x", body: nil),
            in: context3
        )
    }

    @Test("Index 0 is rejected", arguments: [
        PresentationAction.updateSlide(index: 0, title: "x", body: nil),
        .deleteSlide(index: 0),
        .updateSpeakerNotes(index: 0, notes: "x")
    ])
    func indexZero(action: PresentationAction) {
        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(action, in: context3)
        }
    }

    @Test("Index above count is rejected", arguments: [
        PresentationAction.updateSlide(index: 4, title: "x", body: nil),
        .deleteSlide(index: 4),
        .updateSpeakerNotes(index: 4, notes: "x")
    ])
    func indexBeyond(action: PresentationAction) {
        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(action, in: context3)
        }
    }

    @Test("Any index against an empty document is rejected")
    func indexOnEmpty() {
        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(.deleteSlide(index: 1), in: contextEmpty)
        }
    }

    // MARK: - moveSlide checks both endpoints

    @Test("moveSlide with valid from and to passes")
    func moveInBounds() throws {
        try ValidationEngine.validate(.moveSlide(from: 1, to: 3), in: context3)
    }

    @Test("moveSlide rejects an out-of-range `from`")
    func moveBadFrom() {
        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(.moveSlide(from: 0, to: 2), in: context3)
        }
    }

    @Test("moveSlide rejects an out-of-range `to`")
    func moveBadTo() {
        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(.moveSlide(from: 1, to: 4), in: context3)
        }
    }

    // MARK: - addSlide allows count + 1

    @Test("addSlide accepts 1 (prepend) through count + 1 (append)")
    func addAtEdges() throws {
        try ValidationEngine.validate(.addSlide(index: 1, spec: SlideSpec()), in: context3)
        try ValidationEngine.validate(.addSlide(index: 4, spec: SlideSpec()), in: context3)
    }

    @Test("addSlide rejects index = count + 2")
    func addTooFar() {
        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(.addSlide(index: 5, spec: SlideSpec()), in: context3)
        }
    }

    @Test("addSlide onto an empty document accepts index 1")
    func addToEmpty() throws {
        try ValidationEngine.validate(.addSlide(index: 1, spec: SlideSpec()), in: contextEmpty)
    }
}

@Suite("ValidationEngine – text content")
struct ValidationTextTests {

    private let context3 = ValidationContext(slideCount: 3)

    @Test("Title at the length limit passes")
    func titleAtLimit() throws {
        let title = String(repeating: "a", count: ValidationEngine.maxTitleLength)
        try ValidationEngine.validate(
            .updateSlide(index: 1, title: title, body: nil),
            in: context3
        )
    }

    @Test("Title one character over the limit fails")
    func titleOverLimit() {
        let title = String(repeating: "a", count: ValidationEngine.maxTitleLength + 1)
        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(
                .updateSlide(index: 1, title: title, body: nil),
                in: context3
            )
        }
    }

    @Test("An oversize body item fails and the error names its position")
    func bodyOverLimit() throws {
        let long = String(repeating: "a", count: ValidationEngine.maxBodyItemLength + 1)
        do {
            try ValidationEngine.validate(
                .updateSlide(index: 1, title: nil, body: ["short", long]),
                in: context3
            )
            Issue.record("expected a validation error")
        } catch let ValidationError.textTooLong(field, _, _) {
            #expect(field == "body[1]")
        }
    }

    @Test("A NUL byte is rejected")
    func nullByte() {
        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(
                .updateSlide(index: 1, title: "hi\u{0000}there", body: nil),
                in: context3
            )
        }
    }

    @Test("Non-whitespace control characters are rejected")
    func controlChar() {
        // U+0007 (bell)
        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(
                .updateSlide(index: 1, title: "hi\u{0007}there", body: nil),
                in: context3
            )
        }
    }

    @Test("Tab, LF, and CR are allowed inside text")
    func whitespaceAllowed() throws {
        try ValidationEngine.validate(
            .updateSlide(index: 1, title: "line one\nline two\ttab\rcarriage", body: nil),
            in: context3
        )
    }

    @Test("Quotes, backslashes, and ampersands pass — escaping is the renderer's job")
    func metacharactersAllowed() throws {
        try ValidationEngine.validate(
            .updateSlide(index: 1, title: #"she said "hi \& bye""#, body: nil),
            in: context3
        )
    }

    @Test("updateSlide with both title and body nil is an error")
    func emptyUpdate() {
        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(
                .updateSlide(index: 1, title: nil, body: nil),
                in: context3
            )
        }
    }

    @Test("Empty string is a valid title (means clear the placeholder)")
    func emptyStringClears() throws {
        try ValidationEngine.validate(
            .updateSlide(index: 1, title: "", body: nil),
            in: context3
        )
    }

    @Test("Empty body array is valid (means clear all bullets)")
    func emptyBodyClears() throws {
        try ValidationEngine.validate(
            .updateSlide(index: 1, title: nil, body: []),
            in: context3
        )
    }

    // MARK: - createPresentation

    @Test("createPresentation with only a title passes")
    func createNoTheme() throws {
        try ValidationEngine.validate(
            .createPresentation(title: "My deck", theme: nil),
            in: ValidationContext(slideCount: 0)
        )
    }

    @Test("createPresentation with an oversize theme fails")
    func createBadTheme() {
        let theme = String(repeating: "a", count: ValidationEngine.maxThemeLength + 1)
        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(
                .createPresentation(title: "T", theme: theme),
                in: ValidationContext(slideCount: 0)
            )
        }
    }

    // MARK: - updateSpeakerNotes

    @Test("Speaker notes at the limit pass")
    func notesAtLimit() throws {
        let notes = String(repeating: "n", count: ValidationEngine.maxSpeakerNotesLength)
        try ValidationEngine.validate(.updateSpeakerNotes(index: 1, notes: notes), in: context3)
    }

    @Test("Speaker notes over the limit fail")
    func notesOverLimit() {
        let notes = String(repeating: "n", count: ValidationEngine.maxSpeakerNotesLength + 1)
        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(.updateSpeakerNotes(index: 1, notes: notes), in: context3)
        }
    }

    // MARK: - SlideSpec direct validation

    @Test("A well-formed SlideSpec validates")
    func validSpec() throws {
        try ValidationEngine.validate(
            SlideSpec(
                layout: .titleAndBody,
                title: "Intro",
                body: ["one", "two"],
                speakerNotes: "say hello"
            )
        )
    }

    @Test("A SlideSpec with a bad body item fails")
    func badSpec() {
        let long = String(repeating: "a", count: ValidationEngine.maxBodyItemLength + 1)
        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(SlideSpec(body: [long]))
        }
    }
}
