import Foundation

/// Turns one validated `PresentationAction` into a fixed AppleScript template.
///
/// Two properties the rest of the pipeline depends on:
///
/// - **Deterministic.** The same action always renders byte-identical script,
///   which is what makes the renderer testable without a live Keynote and what
///   makes `/script` trustworthy.
/// - **Total.** Every action renders something. The renderer trusts that
///   `ValidationEngine` already ran, so it never re-checks indices or text
///   lengths — its only defensive job is escaping, via `AppleScriptString`.
///
/// Every template names its target document explicitly (`DocumentRef`), never
/// `document 1`. See `DocumentRef` for why.
///
/// Two deliberate omissions:
///
/// - No `activate`. Content edits should not steal focus; foregrounding is
///   `/open`'s job.
/// - No `base slide` / master selection. `SlideLayout` is a hint about *which
///   placeholders to populate*, not a theme-master selector — master names vary
///   by theme, so naming one here would break on any theme that lacks it.
enum AppleScriptRenderer {

    /// `document` is the deck every slide reference is resolved against.
    /// `createPresentation` ignores it — it makes its own document and works
    /// through a local variable, so there is nothing to target yet.
    static func render(_ action: PresentationAction, in document: DocumentRef) -> String {
        switch action {
        case .createPresentation(let title, let theme):
            return renderCreatePresentation(title: title, theme: theme)
        case .addSlide(let index, let spec):
            return renderAddSlide(index: index, spec: spec, in: document)
        case .updateSlide(let index, let title, let body):
            return renderUpdateSlide(index: index, title: title, body: body, in: document)
        case .deleteSlide(let index):
            return renderDeleteSlide(index: index, in: document)
        case .moveSlide(let from, let to):
            return renderMoveSlide(from: from, to: to, in: document)
        case .updateSpeakerNotes(let index, let notes):
            return renderUpdateSpeakerNotes(index: index, notes: notes, in: document)
        }
    }

    // MARK: - Per-action templates

    /// Makes a new document and titles its first slide. An empty `title` skips
    /// the title block: on a brand-new document there is nothing to clear, so
    /// an empty title means "leave the theme's placeholder alone".
    ///
    /// Note this leaves the document unsaved — writing it to disk is
    /// `KeynoteController`'s job, not an action's.
    ///
    /// `theme` is passed through verbatim, and **Keynote theme names are
    /// localized**: on a Korean system `theme "White"` fails with -1728 while
    /// `theme "흰색"` succeeds. No model-supplied name reaches here today — the
    /// planner cannot emit `createPresentation` — so mapping English names onto
    /// the installed themes becomes real work only when a caller starts passing
    /// one. The renderer only escapes.
    private static func renderCreatePresentation(title: String, theme: String?) -> String {
        var make = "set newDoc to make new document"
        if let theme {
            make += " with properties {document theme:theme \(AppleScriptString.literal(theme))}"
        }

        var lines = [make]
        if let title = title.nonEmpty {
            lines += tell(
                "slide 1 of newDoc",
                ["set object text of default title item to \(AppleScriptString.literal(title))"]
            )
        }
        return tellKeynote(lines)
    }

    /// `index` is the position the new slide will occupy, so index 1 inserts at
    /// the beginning and index N inserts after slide N-1. Using `beginning of`
    /// rather than `before slide 1` keeps index 1 valid even when the document
    /// has no slides to reference.
    private static func renderAddSlide(index: Int, spec: SlideSpec, in document: DocumentRef) -> String {
        let location = index <= 1
            ? "at beginning of \(document.specifier)"
            : "at after slide \(index - 1) of \(document.specifier)"

        var lines = ["set newSlide to make new slide \(location)"]
        // A new slide has nothing to clear, so only non-empty content is
        // written. (On `updateSlide`, by contrast, empty means "clear".)
        let properties = slideProperties(
            title: spec.layout.hasTitle ? spec.title.nonEmpty : nil,
            body: spec.layout.hasBody && !spec.body.isEmpty ? spec.body : nil,
            speakerNotes: spec.speakerNotes.nonEmpty
        )
        if !properties.isEmpty {
            lines += tell("newSlide", properties)
        }
        return tellKeynote(lines)
    }

    /// A `nil` field is left alone; an empty string / empty array clears the
    /// placeholder. Both `nil` would be an empty (harmless) `tell` block, but
    /// validation rejects that action before it reaches here.
    private static func renderUpdateSlide(
        index: Int,
        title: String?,
        body: [String]?,
        in document: DocumentRef
    ) -> String {
        tellKeynote(
            tell(
                "slide \(index) of \(document.specifier)",
                slideProperties(title: title, body: body, speakerNotes: nil)
            )
        )
    }

    private static func renderDeleteSlide(index: Int, in document: DocumentRef) -> String {
        tellKeynote(["delete slide \(index) of \(document.specifier)"])
    }

    /// AppleScript resolves the destination against the slide order *before*
    /// the move, so landing on position `to` means "after slide `to`" when
    /// moving down the deck and "before slide `to`" when moving up.
    private static func renderMoveSlide(from: Int, to: Int, in document: DocumentRef) -> String {
        guard from != to else {
            return tellKeynote(["-- slide \(from) is already at position \(to); nothing to do"])
        }
        let destination = from < to ? "after" : "before"
        return tellKeynote(
            ["move slide \(from) of \(document.specifier) "
             + "to \(destination) slide \(to) of \(document.specifier)"]
        )
    }

    private static func renderUpdateSpeakerNotes(
        index: Int,
        notes: String,
        in document: DocumentRef
    ) -> String {
        tellKeynote(
            ["set presenter notes of slide \(index) of \(document.specifier) "
             + "to \(AppleScriptString.literal(notes))"]
        )
    }

    // MARK: - Shared pieces

    /// The property assignments common to `addSlide` and `updateSlide`, in a
    /// fixed order. A `nil` argument emits no line for that field.
    ///
    /// Bullets become one string joined by newlines, which is how Keynote's
    /// body placeholder represents a bullet list.
    private static func slideProperties(
        title: String?,
        body: [String]?,
        speakerNotes: String?
    ) -> [String] {
        var lines: [String] = []
        if let title {
            lines.append("set object text of default title item to \(AppleScriptString.literal(title))")
        }
        if let body {
            let text = body.joined(separator: "\n")
            lines.append("set object text of default body item to \(AppleScriptString.literal(text))")
        }
        if let speakerNotes {
            lines.append("set presenter notes to \(AppleScriptString.literal(speakerNotes))")
        }
        return lines
    }

    /// Wraps `lines` in `tell application "Keynote" ... end tell`.
    private static func tellKeynote(_ lines: [String]) -> String {
        (["tell application \"Keynote\""] + indent(lines) + ["end tell"])
            .joined(separator: "\n")
    }

    /// Wraps `lines` in a nested `tell <target> ... end tell`.
    private static func tell(_ target: String, _ lines: [String]) -> [String] {
        ["tell \(target)"] + indent(lines) + ["end tell"]
    }

    private static func indent(_ lines: [String]) -> [String] {
        lines.map { $0.isEmpty ? $0 : "    " + $0 }
    }
}

private extension String {
    /// `nil` for the empty string — lets "no content" and "clear the content"
    /// stay distinguishable at the call site.
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? { self?.nonEmpty }
}

private extension SlideLayout {

    /// Whether this layout carries a title placeholder the renderer may write.
    var hasTitle: Bool {
        switch self {
        case .blank: false
        case .title, .titleAndBody: true
        }
    }

    /// Whether this layout carries a body placeholder the renderer may write.
    var hasBody: Bool {
        switch self {
        case .blank, .title: false
        case .titleAndBody: true
        }
    }
}
