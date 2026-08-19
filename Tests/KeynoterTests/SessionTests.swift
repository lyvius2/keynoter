import Foundation
import Testing
@testable import Keynoter

@Suite("Session")
@MainActor
struct SessionTests {

    private let deck = URL(fileURLWithPath: "/tmp/demo.key")

    @Test("A fresh session holds no document")
    func initialState() {
        let session = Session()
        #expect(session.hasDocument == false)
        #expect(session.documentPath == nil)
        #expect(session.documentName == nil)
        #expect(session.isModified == false)
        #expect(session.slideCount == 0)
        #expect(session.lastAppleScript == nil)
        #expect(session.shouldExit == false)
    }

    @Test("Attaching a document records its path and mode")
    func attach() {
        let session = Session()
        session.attach(documentPath: deck, mode: .edit)

        #expect(session.hasDocument)
        #expect(session.documentPath == deck)
        #expect(session.documentName == "demo.key")
        #expect(session.mode == .edit)
        #expect(session.isModified == false)
    }

    @Test("Attaching clears state carried over from the previous document")
    func attachResetsPreviousState() {
        let session = Session()
        session.attach(documentPath: deck, mode: .create)
        session.updateSlideMetadata([SlideInfo(index: 1, title: "Intro")])
        session.recordAppleScript("tell application \"Keynote\"")
        session.markModified()

        session.attach(documentPath: URL(fileURLWithPath: "/tmp/other.key"), mode: .edit)

        #expect(session.slideCount == 0)
        #expect(session.lastAppleScript == nil)
        #expect(session.isModified == false)
    }

    @Test("Slide metadata drives the slide count")
    func slideMetadata() {
        let session = Session()
        session.updateSlideMetadata([
            SlideInfo(index: 1, title: "Intro"),
            SlideInfo(index: 2, title: "Architecture")
        ])

        #expect(session.slideCount == 2)
        #expect(session.slideMetadata.last?.title == "Architecture")
    }

    @Test("The modified flag toggles both ways")
    func modifiedFlag() {
        let session = Session()
        session.markModified()
        #expect(session.isModified)

        session.markModified(false)
        #expect(session.isModified == false)
    }

    @Test("Renaming preserves slide metadata and resets the modified flag")
    func renameDocument() {
        let session = Session()
        session.attach(documentPath: deck, mode: .edit)
        session.updateSlideMetadata([
            SlideInfo(index: 1, title: "Intro"),
            SlideInfo(index: 2, title: "Architecture")
        ])
        session.markModified()

        let newPath = URL(fileURLWithPath: "/tmp/copy.key")
        session.renameDocument(to: newPath)

        #expect(session.documentPath == newPath)
        #expect(session.documentName == "copy.key")
        #expect(session.mode == .edit)
        #expect(session.isModified == false)
        #expect(session.slideCount == 2)
        #expect(session.slideMetadata.first?.title == "Intro")
    }

    @Test("Closing the document leaves the session usable")
    func closeDocument() {
        let session = Session()
        session.attach(documentPath: deck, mode: .edit)
        session.updateSlideMetadata([SlideInfo(index: 1, title: "Intro")])
        session.recordAppleScript("tell application \"Keynote\"")
        session.markModified()

        session.closeDocument()

        #expect(session.hasDocument == false)
        #expect(session.mode == .create)
        #expect(session.isModified == false)
        #expect(session.slideCount == 0)
        #expect(session.lastAppleScript == nil)
        // /close keeps the REPL running.
        #expect(session.shouldExit == false)
    }
}
