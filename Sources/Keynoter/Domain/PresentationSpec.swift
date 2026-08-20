import Foundation

/// A slide's high-level layout. Used by the renderer to decide which
/// placeholders (title, body) to populate. Richer variants — photo, quote,
/// section header — will grow this enum in a later phase.
enum SlideLayout: String, Sendable, CaseIterable, Equatable {
    case blank
    case title
    case titleAndBody
}

/// The full state of one slide as the planner would describe it.
///
/// - `title == nil` means "no title placeholder" (only meaningful for
///   layouts that carry one).
/// - `body` is a list of bullet strings; `[]` means "no bullets".
/// - `speakerNotes == nil` means "no notes set".
struct SlideSpec: Equatable, Sendable {
    var layout: SlideLayout
    var title: String?
    var body: [String]
    var speakerNotes: String?

    init(
        layout: SlideLayout = .titleAndBody,
        title: String? = nil,
        body: [String] = [],
        speakerNotes: String? = nil
    ) {
        self.layout = layout
        self.title = title
        self.body = body
        self.speakerNotes = speakerNotes
    }
}

/// A complete presentation as the planner would describe one from scratch.
/// Not the same thing as an on-disk `.key` document — this is the shape the
/// model produces before the executor materializes it in Keynote.
struct PresentationSpec: Equatable, Sendable {
    var title: String
    var theme: String?
    var slides: [SlideSpec]

    init(title: String = "", theme: String? = nil, slides: [SlideSpec] = []) {
        self.title = title
        self.theme = theme
        self.slides = slides
    }
}
