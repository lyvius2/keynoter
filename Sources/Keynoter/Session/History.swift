import Foundation

/// One applied action paired with the action that reverses it.
///
/// The pair is what makes undo possible at all: a `PresentationAction` on its
/// own is not invertible, because `deleteSlide(3)` does not carry what slide 3
/// held. The inverse is therefore computed *before* the action runs, while the
/// old state is still readable, and stored alongside it.
struct HistoryEntry: Equatable, Sendable {
    /// What the user (or the planner) asked for. Re-run on `/redo`.
    let applied: PresentationAction
    /// What puts the document back. Run on `/undo`.
    let inverse: PresentationAction
}

/// The undo/redo stacks for one document.
///
/// A plain value type with no knowledge of Keynote: `ActionRunner` decides when
/// to record and when to commit, and executes the scripts. That split keeps the
/// stack behaviour testable on its own.
struct History: Equatable, Sendable {

    /// Upper bound on remembered actions, so a long session cannot grow without
    /// bound. Oldest entries fall off the bottom.
    static let limit = 100

    private(set) var undoStack: [HistoryEntry] = []
    private(set) var redoStack: [HistoryEntry] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoDepth: Int { undoStack.count }
    var redoDepth: Int { redoStack.count }

    /// The entry `/undo` would act on, without removing it. Execution can fail,
    /// so the stack is only changed afterwards via `commitUndo()`.
    var nextUndo: HistoryEntry? { undoStack.last }

    /// The entry `/redo` would act on. Same peek-then-commit contract.
    var nextRedo: HistoryEntry? { redoStack.last }

    // MARK: - Mutation

    /// Records a freshly applied action.
    ///
    /// Clears the redo stack: once a new action lands, the undone future is no
    /// longer reachable from the current document state.
    mutating func record(_ entry: HistoryEntry) {
        undoStack.append(entry)
        if undoStack.count > Self.limit {
            undoStack.removeFirst(undoStack.count - Self.limit)
        }
        redoStack.removeAll()
    }

    /// Records an action that cannot be reversed (today, only
    /// `createPresentation`).
    ///
    /// Drops *all* history rather than just skipping the entry. An irreversible
    /// action means the document the earlier entries described no longer
    /// exists, so replaying their inverses would corrupt whatever is open now.
    mutating func recordIrreversible() {
        clear()
    }

    /// Moves the top undo entry onto the redo stack. Call only after its
    /// inverse has actually run.
    mutating func commitUndo() {
        guard let entry = undoStack.popLast() else { return }
        redoStack.append(entry)
    }

    /// Moves the top redo entry back onto the undo stack. Call only after its
    /// action has actually re-run.
    mutating func commitRedo() {
        guard let entry = redoStack.popLast() else { return }
        undoStack.append(entry)
    }

    mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
