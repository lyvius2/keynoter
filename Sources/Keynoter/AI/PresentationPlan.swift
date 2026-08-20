import Foundation
import FoundationModels

/// What the model is asked to produce: an ordered list of changes.
///
/// The model never writes AppleScript. It fills in this structure, Keynoter
/// converts it to `PresentationAction`s, and the deterministic renderer takes
/// over from there.
@Generable(description: "An ordered plan of changes to make to a Keynote presentation.")
struct PresentationPlan {

    @Guide(description: "The changes to make, in the order they should be applied.")
    var actions: [GenerableAction]
}

/// The kinds of change the planner may ask for.
///
/// `createPresentation` is deliberately absent. Creating a document is
/// `/create`'s job, and leaving it out has a useful side effect: every action
/// the planner can emit is reversible, so `/undo` always works on model-driven
/// edits.
@Generable(description: "The kind of change to make to the presentation.")
enum GenerableActionKind {
    case addSlide
    case updateSlide
    case deleteSlide
    case moveSlide
    case updateSpeakerNotes
}

/// One change, expressed as a flat record rather than an enum with associated
/// values.
///
/// Flat and always-populated is easier for a small on-device model to fill in
/// reliably than a shape where the valid fields depend on the case. Fields that
/// do not apply to the chosen `kind` are ignored by the converter, and empty
/// strings / empty arrays stand in for "nothing here" — see
/// `PresentationPlan.actions(...)` for exactly how each field is read.
@Generable(description: "A single change to the presentation.")
struct GenerableAction {

    @Guide(description: "Which kind of change this is.")
    var kind: GenerableActionKind

    @Guide(
        description: "The 1-based slide number this change applies to. For addSlide, the position the new slide will occupy.",
        .minimum(1)
    )
    var slideIndex: Int

    @Guide(
        description: "For moveSlide only: the 1-based slide number to move the slide to. Ignored otherwise.",
        .minimum(1)
    )
    var targetIndex: Int

    @Guide(description: "The slide title, a few words. Empty if the change does not set a title.")
    var title: String

    @Guide(
        description: "Bullet points for the slide body, one short line each. Empty if the change does not set the body.",
        .maximumCount(8)
    )
    var body: [String]

    @Guide(description: "Speaker notes for the slide. Empty if the change does not set notes.")
    var speakerNotes: String
}

// MARK: - Progress

/// A plan as it is being written, reduced to the two things worth showing while
/// the user waits: how many changes the model has started, and what it is
/// writing right now.
///
/// Built from `PresentationPlan.PartiallyGenerated`, whose fields are all
/// optional — a snapshot arrives with the action's kind but not yet its title,
/// then the title but not yet the body. Every field is therefore treated as
/// "not written yet" rather than "absent".
struct PlanProgress: Equatable, Sendable {

    /// How many actions the model has begun describing.
    let actionCount: Int

    /// The action being written, as far as it has been written. `nil` until it
    /// says what kind of change it is.
    let current: String?

    /// What the REPL prints: the step number and the change taking shape under
    /// it, mirroring the `  add slide 4` lines printed as steps are applied.
    var display: String {
        guard actionCount > 0 else { return "…" }
        return "\(actionCount). \(current ?? "…")"
    }

    init(actionCount: Int, current: String?) {
        self.actionCount = actionCount
        self.current = current
    }

    init(_ partial: PresentationPlan.PartiallyGenerated) {
        let actions = partial.actions ?? []
        self.actionCount = actions.count
        self.current = actions.last.flatMap(Self.describe)
    }

    /// Deliberately close to `PresentationAction.summary`, so a step reads the
    /// same while it is being planned and after it has been applied.
    static func describe(_ action: GenerableAction.PartiallyGenerated) -> String? {
        guard let kind = action.kind else { return nil }

        let slide = action.slideIndex.map { "slide \($0)" } ?? "slide"
        switch kind {
        case .addSlide:
            return "add \(slide)" + titleSuffix(action.title) + bodySuffix(action.body)
        case .updateSlide:
            return "update \(slide)" + titleSuffix(action.title) + bodySuffix(action.body)
        case .deleteSlide:
            return "delete \(slide)"
        case .moveSlide:
            guard let target = action.targetIndex else { return "move \(slide)" }
            return "move \(slide) to \(target)"
        case .updateSpeakerNotes:
            return "update speaker notes on \(slide)"
        }
    }

    /// An empty title means the model has not written one yet, not that the
    /// slide has none — so it is left off the line rather than shown as blank.
    /// Truncated because this goes on a single terminal line that is rewritten
    /// in place: a title that wraps would leave the previous update on screen.
    private static func titleSuffix(_ title: String?) -> String {
        guard let title, !title.isEmpty else { return "" }
        let collapsed = title
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !collapsed.isEmpty else { return "" }
        let shown = collapsed.count <= 40 ? collapsed : collapsed.prefix(40) + "…"
        return " \"\(shown)\""
    }

    /// Bullets are counted rather than shown. The count is also the only thing
    /// that moves while the model writes a long body — the step number and the
    /// title have been on screen for ten seconds by then — and the bullets
    /// themselves would not fit on the line.
    private static func bodySuffix(_ body: [String]?) -> String {
        guard let body, !body.isEmpty else { return "" }
        return " (\(body.count) bullet\(body.count == 1 ? "" : "s"))"
    }
}

// MARK: - Conversion

enum PlanConversionError: Error, Equatable {
    /// The action carried nothing the corresponding `PresentationAction` could
    /// use — an update that updates nothing, say.
    case emptyAction(position: Int, kind: String)
    /// The plan itself was empty: the model understood the request as requiring
    /// no changes.
    case emptyPlan
}

extension PresentationPlan {

    /// Converts the model's plan into domain actions, in order.
    ///
    /// Pure and total apart from the two `PlanConversionError` cases, so the
    /// whole mapping is testable without Apple Intelligence. Bounds checking is
    /// *not* done here — `ValidationEngine` owns that, and it runs against the
    /// live slide count just before each action is applied.
    func toActions() throws -> [PresentationAction] {
        guard !actions.isEmpty else { throw PlanConversionError.emptyPlan }
        return try actions.enumerated().map { position, action in
            try action.toAction(position: position)
        }
    }
}

extension GenerableAction {

    /// `position` is only used to point at the offending action in an error.
    func toAction(position: Int) throws -> PresentationAction {
        switch kind {
        case .addSlide:
            return .addSlide(index: slideIndex, spec: slideSpec)

        case .updateSlide:
            // Empty means "leave this field alone", not "clear it". The domain
            // model can express clearing (empty string / empty array), but the
            // model has no reliable way to distinguish the two, and leaving
            // content alone is the safer reading of an ambiguous plan.
            let newTitle = title.isEmpty ? nil : title
            let newBody = body.isEmpty ? nil : body
            guard newTitle != nil || newBody != nil else {
                throw PlanConversionError.emptyAction(position: position, kind: "updateSlide")
            }
            return .updateSlide(index: slideIndex, title: newTitle, body: newBody)

        case .deleteSlide:
            return .deleteSlide(index: slideIndex)

        case .moveSlide:
            return .moveSlide(from: slideIndex, to: targetIndex)

        case .updateSpeakerNotes:
            guard !speakerNotes.isEmpty else {
                throw PlanConversionError.emptyAction(position: position, kind: "updateSpeakerNotes")
            }
            return .updateSpeakerNotes(index: slideIndex, notes: speakerNotes)
        }
    }

    /// The layout follows from which placeholders the model actually filled in,
    /// the same rule `KeynoteController.parseSlide(_:)` uses when reading a
    /// slide back.
    private var slideSpec: SlideSpec {
        let layout: SlideLayout
        if !body.isEmpty {
            layout = .titleAndBody
        } else if !title.isEmpty {
            layout = .title
        } else {
            layout = .blank
        }
        return SlideSpec(
            layout: layout,
            title: title.isEmpty ? nil : title,
            body: body,
            speakerNotes: speakerNotes.isEmpty ? nil : speakerNotes
        )
    }
}

extension PlanConversionError {

    var userMessage: String {
        switch self {
        case .emptyPlan:
            return "The planner did not propose any changes. Try describing the change more concretely."
        case .emptyAction(let position, let kind):
            return "The planner proposed a \(kind) at step \(position + 1) with nothing to apply."
        }
    }
}
