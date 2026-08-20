import Foundation
import Testing
@testable import Keynoter

@Suite("History")
struct HistoryTests {

    private func entry(_ index: Int) -> HistoryEntry {
        HistoryEntry(
            applied: .addSlide(index: index, spec: SlideSpec(title: "S\(index)")),
            inverse: .deleteSlide(index: index)
        )
    }

    @Test("A fresh history offers nothing to undo or redo")
    func initialState() {
        let history = History()
        #expect(history.canUndo == false)
        #expect(history.canRedo == false)
        #expect(history.undoDepth == 0)
        #expect(history.redoDepth == 0)
        #expect(history.nextUndo == nil)
        #expect(history.nextRedo == nil)
    }

    @Test("Recording makes the newest entry the next one to undo")
    func recordPushesOntoUndoStack() {
        var history = History()
        history.record(entry(1))
        history.record(entry(2))

        #expect(history.undoDepth == 2)
        #expect(history.nextUndo == entry(2))
    }

    @Test("Peeking does not change the stacks")
    func peekIsNonDestructive() {
        var history = History()
        history.record(entry(1))

        #expect(history.nextUndo == entry(1))
        #expect(history.nextUndo == entry(1))
        #expect(history.undoDepth == 1)
    }

    @Test("Committing an undo moves the entry over to the redo stack")
    func commitUndo() {
        var history = History()
        history.record(entry(1))
        history.commitUndo()

        #expect(history.canUndo == false)
        #expect(history.redoDepth == 1)
        #expect(history.nextRedo == entry(1))
    }

    @Test("Committing a redo moves the entry back")
    func commitRedo() {
        var history = History()
        history.record(entry(1))
        history.commitUndo()
        history.commitRedo()

        #expect(history.undoDepth == 1)
        #expect(history.canRedo == false)
        #expect(history.nextUndo == entry(1))
    }

    @Test("Committing against an empty stack is a no-op, not a crash")
    func commitOnEmptyStack() {
        var history = History()
        history.commitUndo()
        history.commitRedo()

        #expect(history.undoDepth == 0)
        #expect(history.redoDepth == 0)
    }

    @Test("A new action makes the undone future unreachable")
    func recordClearsRedoStack() {
        var history = History()
        history.record(entry(1))
        history.commitUndo()
        #expect(history.canRedo)

        history.record(entry(2))

        #expect(history.canRedo == false)
        #expect(history.nextUndo == entry(2))
    }

    @Test("An irreversible action discards the whole history")
    func recordIrreversible() {
        var history = History()
        history.record(entry(1))
        history.record(entry(2))
        history.commitUndo()

        history.recordIrreversible()

        #expect(history.canUndo == false)
        #expect(history.canRedo == false)
    }

    @Test("The undo stack drops its oldest entries once it hits the limit")
    func undoStackIsBounded() {
        var history = History()
        for index in 1...(History.limit + 5) {
            history.record(entry(index))
        }

        #expect(history.undoDepth == History.limit)
        #expect(history.nextUndo == entry(History.limit + 5))
        // The five oldest were dropped, so the bottom is now entry 6.
        #expect(history.undoStack.first == entry(6))
    }

    @Test("Clearing empties both stacks")
    func clear() {
        var history = History()
        history.record(entry(1))
        history.commitUndo()
        history.record(entry(2))

        history.clear()

        #expect(history.undoDepth == 0)
        #expect(history.redoDepth == 0)
    }
}