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
