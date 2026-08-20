import Foundation

/// One structured change to a Keynote presentation.
///
/// The planner emits a sequence of these; the renderer turns each into a
/// deterministic AppleScript snippet; the executor runs the snippets in order.
/// Indices are 1-based to match AppleScript's `slide N of <document>`.
enum PresentationAction: Equatable, Sendable {
    /// Creates a new, empty document. `theme` names a Keynote theme (e.g.
    /// "White", "Modern Portfolio"); `nil` uses the default.
    case createPresentation(title: String, theme: String?)

    /// Inserts a new slide at the given position. `index` is the position the
    /// new slide will occupy, so a document with N slides accepts 1...N+1.
    case addSlide(index: Int, spec: SlideSpec)

    /// Replaces `title` and/or `body` on an existing slide. A `nil` field
    /// means "leave this alone"; an empty string / empty array means "clear".
    /// Setting both to `nil` is a validation error.
    case updateSlide(index: Int, title: String?, body: [String]?)

    case deleteSlide(index: Int)

    /// `from` and `to` are both indices in the current document; after the
    /// move the slide that was at `from` occupies position `to`.
    case moveSlide(from: Int, to: Int)

    case updateSpeakerNotes(index: Int, notes: String)
}

extension PresentationAction {

    /// A short, imperative description for REPL output — "add slide 3".
    /// Deliberately excludes the text content: `/script` is where the full
    /// payload is inspected.
    var summary: String {
        switch self {
        case .createPresentation(let title, _):
            return title.isEmpty ? "create presentation" : "create presentation \"\(title)\""
        case .addSlide(let index, _):
            return "add slide \(index)"
        case .updateSlide(let index, _, _):
            return "update slide \(index)"
        case .deleteSlide(let index):
            return "delete slide \(index)"
        case .moveSlide(let from, let to):
            return "move slide \(from) to \(to)"
        case .updateSpeakerNotes(let index, _):
            return "update speaker notes on slide \(index)"
        }
    }
}

/// State the validator needs from Session to decide whether an action is safe.
struct ValidationContext: Equatable, Sendable {
    let slideCount: Int
}

enum ValidationError: Error, Equatable {
    /// `allowed` is a half-open range so `1..<1` can express "no valid index"
    /// on an empty document (a `ClosedRange` cannot represent that).
    case indexOutOfRange(index: Int, allowed: Range<Int>)
    case emptyUpdate
    case textTooLong(field: String, limit: Int, actual: Int)
    case invalidCharacter(field: String)
}

extension ValidationError {

    /// One-line rendering for the REPL, matching `AppleScriptError.userMessage`.
    var userMessage: String {
        switch self {
        case .indexOutOfRange(let index, let allowed):
            if allowed.isEmpty {
                return "Slide \(index) does not exist — the document has no slides."
            }
            return "Slide \(index) is out of range (the document allows \(allowed.lowerBound)–\(allowed.upperBound - 1))."
        case .emptyUpdate:
            return "That update would change nothing."
        case .textTooLong(let field, let limit, let actual):
            return "\(field) is \(actual) characters — the limit is \(limit)."
        case .invalidCharacter(let field):
            return "\(field) contains a character Keynoter will not send to Keynote."
        }
    }
}

/// Pure validation over `PresentationAction`. Runs before the renderer, so
/// the renderer can trust that inputs are well-formed.
enum ValidationEngine {

    /// Length caps are Keynoter-side sanity limits, not Keynote's own limits.
    /// Adjust freely if the model needs more room.
    static let maxTitleLength = 200
    static let maxBodyItemLength = 500
    static let maxSpeakerNotesLength = 4000
    static let maxThemeLength = 100

    static func validate(_ action: PresentationAction, in context: ValidationContext) throws {
        switch action {
        case .createPresentation(let title, let theme):
            try checkText(title, field: "title", limit: maxTitleLength)
            if let theme {
                try checkText(theme, field: "theme", limit: maxThemeLength)
            }

        case .addSlide(let index, let spec):
            try checkAddIndex(index, count: context.slideCount)
            try validate(spec)

        case .updateSlide(let index, let title, let body):
            try checkIndex(index, count: context.slideCount)
            if title == nil && body == nil {
                throw ValidationError.emptyUpdate
            }
            if let title {
                try checkText(title, field: "title", limit: maxTitleLength)
            }
            if let body {
                for (position, item) in body.enumerated() {
                    try checkText(item, field: "body[\(position)]", limit: maxBodyItemLength)
                }
            }

        case .deleteSlide(let index):
            try checkIndex(index, count: context.slideCount)

        case .moveSlide(let from, let to):
            try checkIndex(from, count: context.slideCount)
            try checkIndex(to, count: context.slideCount)

        case .updateSpeakerNotes(let index, let notes):
            try checkIndex(index, count: context.slideCount)
            try checkText(notes, field: "notes", limit: maxSpeakerNotesLength)
        }
    }

    static func validate(_ spec: SlideSpec) throws {
        if let title = spec.title {
            try checkText(title, field: "title", limit: maxTitleLength)
        }
        for (position, item) in spec.body.enumerated() {
            try checkText(item, field: "body[\(position)]", limit: maxBodyItemLength)
        }
        if let notes = spec.speakerNotes {
            try checkText(notes, field: "notes", limit: maxSpeakerNotesLength)
        }
    }

    // MARK: - Helpers

    static func checkIndex(_ index: Int, count: Int) throws {
        let allowed = 1..<(count + 1)
        guard allowed.contains(index) else {
            throw ValidationError.indexOutOfRange(index: index, allowed: allowed)
        }
    }

    static func checkAddIndex(_ index: Int, count: Int) throws {
        let allowed = 1..<(count + 2)
        guard allowed.contains(index) else {
            throw ValidationError.indexOutOfRange(index: index, allowed: allowed)
        }
    }

    /// Rejects `\0` and non-whitespace control characters (which can confuse
    /// osascript's line-based error reporting and Keynote's text placeholders).
    /// `\t`, `\n`, `\r` are allowed; escaping for AppleScript string literals
    /// is the renderer's job.
    static func checkText(_ text: String, field: String, limit: Int) throws {
        if text.count > limit {
            throw ValidationError.textTooLong(field: field, limit: limit, actual: text.count)
        }
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value == 0 {
                throw ValidationError.invalidCharacter(field: field)
            }
            if value < 0x20, value != 0x09, value != 0x0A, value != 0x0D {
                throw ValidationError.invalidCharacter(field: field)
            }
        }
    }
}
