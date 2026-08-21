import Foundation

/// A file format Keynote can write a document out to.
///
/// Deliberately *not* a `PresentationAction`. Exporting reads the deck and
/// writes a separate file; it changes nothing inside the presentation, so it
/// belongs with `/save` and `/open` on the session side rather than in the
/// content pipeline. Routing it through `ActionRunner` would mark the session
/// modified and — having no inverse — discard the whole undo history, which is
/// a steep price for producing a PDF.
enum ExportFormat: String, Sendable, CaseIterable, Equatable {
    case pdf
    case pptx

    /// Extension for the written file, and what `PathResolver` appends when the
    /// user's path doesn't already carry it.
    var fileExtension: String { rawValue }

    /// The `export … as <constant>` enumerator. An AppleScript *enumerator*,
    /// not a string literal — it is never quoted and never escaped, and it is a
    /// compile-time constant, so no caller-supplied text reaches it.
    var appleScriptConstant: String {
        switch self {
        case .pdf: "PDF"
        case .pptx: "Microsoft PowerPoint"
        }
    }

    /// How the format is named in REPL output.
    var displayName: String {
        switch self {
        case .pdf: "PDF"
        case .pptx: "PowerPoint"
        }
    }

    /// Parses the keyword typed after `/export`. Case-insensitive, and accepts
    /// the two names people reach for besides the extension itself.
    static func parse(_ text: String) -> ExportFormat? {
        switch text.lowercased() {
        case "pdf": .pdf
        case "pptx", "ppt", "powerpoint": .pptx
        default: nil
        }
    }

    /// The canonical keywords, for usage strings and error messages.
    static var keywordList: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }
}
