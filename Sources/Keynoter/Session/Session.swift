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
    private(set) var mode: SessionMode = .create
    private(set) var isModified = false
    private(set) var slideMetadata: [SlideInfo] = []
    private(set) var lastAppleScript: String?

    /// Set by `/exit` (and by EOF on stdin) to end the REPL loop.
    var shouldExit = false

    // Phase 3 adds `undoStack` / `redoStack` here, once `PresentationAction` exists.

    var hasDocument: Bool { documentPath != nil }

    var documentName: String? { documentPath?.lastPathComponent }

    var slideCount: Int { slideMetadata.count }

    // MARK: - Mutation

    func attach(documentPath: URL, mode: SessionMode) {
        self.documentPath = documentPath
        self.mode = mode
        self.isModified = false
        self.slideMetadata = []
        self.lastAppleScript = nil
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

    /// Drops the active document but leaves the REPL running (`/close`).
    func closeDocument() {
        documentPath = nil
        mode = .create
        isModified = false
        slideMetadata = []
        lastAppleScript = nil
    }
}
