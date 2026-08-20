import Foundation

/// A stable AppleScript reference to one open Keynote document.
///
/// Keynote gives every open document a UUID, and it is the only identifier that
/// holds still: it survives saving, window reordering, and two documents that
/// happen to share a file name.
///
/// The alternative — `front document` / `document 1` — means "whichever window
/// the user last clicked". Clicking another deck in Keynote silently redirected
/// every Keynoter command at it, which is survivable for `/status` and ruinous
/// once a plan starts writing slides.
///
/// A reference to a document the user has since closed fails loudly with
/// AppleScript error `-1728` rather than hitting the wrong deck. That is the
/// whole point: wrong-document is a far worse failure than no-document.
struct DocumentRef: Equatable, Sendable {

    /// Keynote's per-document UUID, e.g. `C29AB346-3939-4EA4-82F9-B840292C80FD`.
    let id: String

    /// The AppleScript specifier — `document id "C29AB346-…"`.
    ///
    /// Escaped through `AppleScriptString` like every other interpolated value,
    /// even though Keynote only ever hands back UUIDs.
    var specifier: String {
        "document id \(AppleScriptString.literal(id))"
    }
}
