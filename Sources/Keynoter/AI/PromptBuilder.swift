import Foundation

/// Builds the two pieces of text the model sees: the standing instructions that
/// define its job, and a per-request prompt carrying the user's words plus the
/// deck as it currently stands.
///
/// Pure string assembly, so the exact wording is pinned by tests. Wording is
/// load-bearing here — it is the only thing standing between a vague request and
/// a plan with the wrong slide numbers — so changes should come with a test
/// update and a live check, not just a build.
enum PromptBuilder {

    /// How many slides of context to include before falling back to a summary.
    /// A long deck would otherwise crowd out the request itself.
    static let maxOutlineSlides = 40

    /// Titles are truncated in the outline: the model needs them to identify
    /// slides, not to reproduce them.
    static let maxOutlineTitleLength = 80

    /// Standing instructions for the session. Kept to three short paragraphs —
    /// they are re-sent with every request, so they come straight out of the
    /// context budget.
    static let instructions = """
    You plan edits to an Apple Keynote presentation. Respond only by filling in \
    the plan structure. Never write AppleScript, code, or explanatory prose.

    Actions are applied in the order you list them, and each one sees the deck as \
    changed by the actions before it. Slide numbers are 1-based. addSlide inserts \
    at the number you give, pushing later slides down. Set targetIndex only for \
    moveSlide. Leave a field empty when the action does not set it.

    Keep slide text short enough to read from the back of a room: a title of a few \
    words, and at most six bullets of one line each. Put detail in speakerNotes \
    instead. Write slide text in the same language as the request. A new \
    presentation starts with one empty slide: use updateSlide to turn it into the \
    title slide rather than leaving it blank.
    """

    /// The per-request prompt: what the deck looks like now, then what the user
    /// asked for.
    ///
    /// The outline goes first so the model has the slide numbers in hand before
    /// it reads the request that refers to them.
    static func prompt(request: String, slides: [SlideInfo]) -> String {
        """
        \(outline(slides))

        Request: \(request.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    // MARK: - Outline

    /// A numbered list of the current slides, or a short stand-in when there is
    /// nothing useful to list.
    static func outline(_ slides: [SlideInfo]) -> String {
        guard !slides.isEmpty else {
            return "The presentation is empty."
        }

        let shown = slides.prefix(maxOutlineSlides)
        var lines = ["The presentation has \(slides.count) slide\(slides.count == 1 ? "" : "s"):"]
        for slide in shown {
            lines.append("  \(slide.index). \(displayTitle(slide.title))")
        }
        if slides.count > shown.count {
            lines.append("  … and \(slides.count - shown.count) more.")
        }
        return lines.joined(separator: "\n")
    }

    /// An untitled slide still needs a row — dropping it would silently shift
    /// every later slide number the model reads.
    static func displayTitle(_ title: String) -> String {
        let collapsed = title
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if collapsed.isEmpty { return "(untitled)" }
        if collapsed.count <= maxOutlineTitleLength { return collapsed }
        return collapsed.prefix(maxOutlineTitleLength) + "…"
    }
}
