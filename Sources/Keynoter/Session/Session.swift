import Foundation

enum SessionMode: String, Sendable {
    case create
    case edit
}

/// Title and position of a slide in the active document, refreshed from Keynote
/// after each action (Phase 2).
struct SlideInfo: Equatable, Sendable {
    let index: Int
    let title: String
}

/// In-memory state for one Keynoter session.
///
/// Main-actor isolated: the REPL is the only owner, and keeping it on one actor
/// avoids sharing concerns once AI calls start suspending mid-loop.
@MainActor
final class Session {

    private(set) var documentPath: URL?

    /// Which Keynote document this session drives. Every command targets it by
    /// id, so clicking another deck in Keynote cannot redirect Keynoter at it.
    private(set) var documentRef: DocumentRef?
    private(set) var mode: SessionMode = .create
    private(set) var isModified = false
    private(set) var slideMetadata: [SlideInfo] = []
    private(set) var lastAppleScript: String?

    /// Undo/redo stacks for the active document. Entries pair each applied
    /// action with the action that reverses it — see `HistoryEntry`.
    private(set) var history = History()

    /// Set by `requestExit()` to end the REPL loop.
    private(set) var shouldExit = false

    /// Armed when a quit request was held back because of unsaved changes.
    /// Cleared by `cancelExitRequest()` on any other input, so the confirmation
    /// always answers the request immediately before it.
    private(set) var isExitPending = false

    var hasDocument: Bool { documentPath != nil }

    var documentName: String? { documentPath?.lastPathComponent }

    var slideCount: Int { slideMetadata.count }

    // MARK: - Mutation

    func attach(documentPath: URL, ref: DocumentRef, mode: SessionMode) {
        self.documentPath = documentPath
        self.documentRef = ref
        self.mode = mode
        self.isModified = false
        self.slideMetadata = []
        self.lastAppleScript = nil
        // History belongs to a document, not to the process: replaying slide 3's
        // old text into a different deck is exactly the corruption undo exists
        // to avoid.
        self.history.clear()
    }

    /// Follows `/save-as` into the copy. The slide metadata and history carry
    /// over untouched — same deck, same slide indices — but the reference does
    /// not: `save … in` leaves the original bound to its old file, so Keynoter
    /// closes it and opens the copy, which Keynote gives a fresh id.
    func switchDocument(to path: URL, ref: DocumentRef) {
        self.documentPath = path
        self.documentRef = ref
        self.isModified = false
    }

    func updateSlideMetadata(_ slides: [SlideInfo]) {
        slideMetadata = slides
    }

    func recordAppleScript(_ script: String) {
        lastAppleScript = script
    }

    func markModified(_ modified: Bool = true) {
        isModified = modified
    }

    // MARK: - Quitting

    /// Answers a quit request: `true` to leave now, `false` to hold once so the
    /// user can save first.
    ///
    /// Unsaved changes buy exactly one refusal — the second request goes
    /// through whatever the state of the document — so nothing here can trap
    /// the user inside the REPL.
    func requestExit() -> Bool {
        if isModified && !isExitPending {
            isExitPending = true
            return false
        }
        shouldExit = true
        return true
    }

    /// Withdraws a held-back quit request: anything the user does other than
    /// asking again answers "not yet".
    func cancelExitRequest() {
        isExitPending = false
    }

    // MARK: - History

    func recordHistory(_ entry: HistoryEntry) {
        history.record(entry)
    }

    /// Records an action with no inverse, which discards the history — see
    /// `History.recordIrreversible()`.
    func recordIrreversibleAction() {
        history.recordIrreversible()
    }

    func commitUndo() {
        history.commitUndo()
    }

    func commitRedo() {
        history.commitRedo()
    }

    /// Drops the active document but leaves the REPL running (`/close`).
    func closeDocument() {
        documentPath = nil
        documentRef = nil
        mode = .create
        isModified = false
        slideMetadata = []
        lastAppleScript = nil
        history.clear()
    }
}
