import Foundation

enum ActionRunnerError: Error, Equatable {
    case nothingToUndo
    case nothingToRedo
}

/// Applies `PresentationAction`s to the open document, and walks the undo/redo
/// stacks back and forth.
///
/// This is the one place the whole pipeline is assembled:
///
/// ```
/// validate → snapshot the "before" state → render → execute → record history
/// ```
///
/// Undo and redo are not a separate mechanism — they render and execute an
/// action just like `apply(_:)` does, so `/script` stays meaningful after one
/// and the rule that only the renderer produces AppleScript still holds.
///
/// Deliberately does *not* refresh `Session.slideMetadata`. Reading the deck
/// back is a per-command decision the REPL already makes (and reports failures
/// for); doing it here would hide an Apple Event behind every action and cost a
/// full re-read per action once Phase 4 applies plans in batches.
@MainActor
struct ActionRunner {

    let session: Session
    let controller: KeynoteController

    init(session: Session, controller: KeynoteController) {
        self.session = session
        self.controller = controller
    }

    // MARK: - Apply

    /// Validates, applies and records `action`. Returns the AppleScript that ran.
    ///
    /// Nothing is recorded unless the script actually succeeded, and the
    /// "before" snapshot is taken before any mutation, so a failure anywhere
    /// leaves both Keynote and the history untouched.
    @discardableResult
    func apply(_ action: PresentationAction) async throws -> String {
        try ValidationEngine.validate(action, in: validationContext)

        let snapshot = try await captureSnapshot(for: action)
        let script = try await execute(action)

        if let inverse = InverseBuilder.inverse(of: action, snapshot: snapshot) {
            session.recordHistory(HistoryEntry(applied: action, inverse: inverse))
        } else {
            session.recordIrreversibleAction()
        }
        return script
    }

    // MARK: - Undo / redo

    /// Runs the inverse of the most recent action. Returns the action that was
    /// undone, for reporting.
    @discardableResult
    func undo() async throws -> PresentationAction {
        guard let entry = session.history.nextUndo else {
            throw ActionRunnerError.nothingToUndo
        }
        // Re-validate: the deck may have moved under us (an edit made directly
        // in Keynote, say). A validation error here is a far clearer message
        // than the -1728 that AppleScript would raise instead.
        try ValidationEngine.validate(entry.inverse, in: validationContext)
        _ = try await execute(entry.inverse)
        session.commitUndo()
        return entry.applied
    }

    /// Re-runs the most recently undone action. Returns it, for reporting.
    @discardableResult
    func redo() async throws -> PresentationAction {
        guard let entry = session.history.nextRedo else {
            throw ActionRunnerError.nothingToRedo
        }
        try ValidationEngine.validate(entry.applied, in: validationContext)
        _ = try await execute(entry.applied)
        session.commitRedo()
        return entry.applied
    }

    // MARK: - Shared steps

    private var validationContext: ValidationContext {
        ValidationContext(slideCount: session.slideCount)
    }

    /// Reads the slide `action` is about to change, when its inverse needs it.
    private func captureSnapshot(for action: PresentationAction) async throws -> SlideSpec? {
        guard let index = InverseBuilder.snapshotIndex(for: action) else { return nil }
        return try await controller.readSlide(at: index)
    }

    /// Renders, runs, and records the script for `/script`. Returns the script.
    private func execute(_ action: PresentationAction) async throws -> String {
        let script = AppleScriptRenderer.render(action)
        try await controller.execute(script)
        session.recordAppleScript(script)
        session.markModified()
        return script
    }
}

extension ActionRunnerError {

    var userMessage: String {
        switch self {
        case .nothingToUndo: "Nothing to undo."
        case .nothingToRedo: "Nothing to redo."
        }
    }
}