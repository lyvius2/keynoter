import Foundation
import Testing
@testable import Keynoter

@Suite("Session")
@MainActor
struct SessionTests {

    private let deck = URL(fileURLWithPath: "/tmp/demo.key")
    private let ref = DocumentRef(id: "DOC-1")
    private let otherRef = DocumentRef(id: "DOC-2")

    @Test("A fresh session holds no document")
    func initialState() {
        let session = Session()
        #expect(session.hasDocument == false)
        #expect(session.documentPath == nil)
        #expect(session.documentName == nil)
        #expect(session.isModified == false)
        #expect(session.slideCount == 0)
        #expect(session.lastAppleScript == nil)
        #expect(session.history.canUndo == false)
        #expect(session.history.canRedo == false)
        #expect(session.shouldExit == false)
    }

    @Test("Attaching a document records its path and mode")
    func attach() {
        let session = Session()
        session.attach(documentPath: deck, ref: ref, mode: .edit)

        #expect(session.hasDocument)
        #expect(session.documentPath == deck)
        #expect(session.documentName == "demo.key")
        #expect(session.mode == .edit)
        #expect(session.isModified == false)
    }

    @Test("Attaching clears state carried over from the previous document")
    func attachResetsPreviousState() {
        let session = Session()
        session.attach(documentPath: deck, ref: ref, mode: .create)
        session.updateSlideMetadata([SlideInfo(index: 1, title: "Intro")])
        session.recordAppleScript("tell application \"Keynote\"")
        session.markModified()

        session.attach(documentPath: URL(fileURLWithPath: "/tmp/other.key"), ref: otherRef, mode: .edit)

        #expect(session.slideCount == 0)
        #expect(session.lastAppleScript == nil)
        #expect(session.isModified == false)
    }

    @Test("History belongs to a document, so attaching a new one discards it")
    func attachClearsHistory() {
        let session = Session()
        session.attach(documentPath: deck, ref: ref, mode: .edit)
        session.recordHistory(
            HistoryEntry(applied: .deleteSlide(index: 1), inverse: .addSlide(index: 1, spec: SlideSpec()))
        )

        session.attach(documentPath: URL(fileURLWithPath: "/tmp/other.key"), ref: otherRef, mode: .edit)

        #expect(session.history.canUndo == false)
    }

    @Test("Recording, undoing and redoing move entries between the stacks")
    func historyRoundTrip() {
        let session = Session()
        let entry = HistoryEntry(
            applied: .addSlide(index: 1, spec: SlideSpec(title: "Intro")),
            inverse: .deleteSlide(index: 1)
        )
        session.recordHistory(entry)
        #expect(session.history.undoDepth == 1)

        session.commitUndo()
        #expect(session.history.canUndo == false)
        #expect(session.history.nextRedo == entry)

        session.commitRedo()
        #expect(session.history.nextUndo == entry)
    }

    @Test("An irreversible action clears the history")
    func irreversibleActionClearsHistory() {
        let session = Session()
        session.recordHistory(
            HistoryEntry(applied: .moveSlide(from: 1, to: 2), inverse: .moveSlide(from: 2, to: 1))
        )

        session.recordIrreversibleAction()

        #expect(session.history.canUndo == false)
    }

    @Test("Closing the document discards the history")
    func closeClearsHistory() {
        let session = Session()
        session.attach(documentPath: deck, ref: ref, mode: .edit)
        session.recordHistory(
            HistoryEntry(applied: .moveSlide(from: 1, to: 2), inverse: .moveSlide(from: 2, to: 1))
        )

        session.closeDocument()

        #expect(session.history.canUndo == false)
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

    @Test("/save-as follows the copy: new path and reference, same slides")
    func switchDocument() {
        let session = Session()
        session.attach(documentPath: deck, ref: ref, mode: .edit)
        session.updateSlideMetadata([
            SlideInfo(index: 1, title: "Intro"),
            SlideInfo(index: 2, title: "Architecture")
        ])
        session.markModified()

        let newPath = URL(fileURLWithPath: "/tmp/copy.key")
        session.switchDocument(to: newPath, ref: otherRef)

        #expect(session.documentPath == newPath)
        #expect(session.documentName == "copy.key")
        // Keynote gives the reopened copy a fresh id.
        #expect(session.documentRef == otherRef)
        #expect(session.mode == .edit)
        #expect(session.isModified == false)
        #expect(session.slideCount == 2)
        #expect(session.slideMetadata.first?.title == "Intro")
    }

    @Test("Closing the document leaves the session usable")
    func closeDocument() {
        let session = Session()
        session.attach(documentPath: deck, ref: ref, mode: .edit)
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
