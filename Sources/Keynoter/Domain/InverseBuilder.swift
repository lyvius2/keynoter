import Foundation

/// Computes the action that reverses a given action.
///
/// Pure by construction: anything that has to be read out of Keynote arrives as
/// the `snapshot` argument, captured by `ActionRunner` immediately before the
/// action runs. That keeps every inverse rule testable without a live document.
enum InverseBuilder {

    /// The slide whose contents must be captured before `action` runs, or `nil`
    /// when the inverse can be derived from the action alone.
    ///
    /// Only one slide is ever needed, so the pre-read stays O(1) rather than
    /// re-reading the whole deck.
    static func snapshotIndex(for action: PresentationAction) -> Int? {
        switch action {
        case .createPresentation, .addSlide, .moveSlide:
            return nil
        case .updateSlide(let index, _, _),
             .deleteSlide(let index),
             .updateSpeakerNotes(let index, _):
            return index
        }
    }

    /// The action that undoes `action`, or `nil` when it cannot be undone.
    ///
    /// `snapshot` is the state of `snapshotIndex(for:)`'s slide as it was
    /// *before* `action` ran. Passing `nil` where a snapshot was required also
    /// yields `nil` — better to refuse the undo than to guess at lost content.
    ///
    /// Known limitation: undoing a `deleteSlide` restores the slide's title,
    /// body and notes, because that is all `SlideSpec` carries. The original
    /// master, images and shapes are not recovered.
    static func inverse(of action: PresentationAction, snapshot: SlideSpec?) -> PresentationAction? {
        switch action {
        case .createPresentation:
            // There is no deletePresentation action, and there should not be —
            // an action that closes or discards a document belongs to the
            // session layer, not the content pipeline.
            return nil

        case .addSlide(let index, _):
            return .deleteSlide(index: index)

        case .updateSlide(let index, let title, let body):
            guard let snapshot else { return nil }
            // Restore only the fields this update actually touched: a `nil`
            // field meant "leave alone" going in, and must mean the same
            // coming back out. A field that had no placeholder before is
            // restored as empty, which is the closest `updateSlide` can get.
            return .updateSlide(
                index: index,
                title: title == nil ? nil : (snapshot.title ?? ""),
                body: body == nil ? nil : snapshot.body
            )

        case .deleteSlide(let index):
            guard let snapshot else { return nil }
            return .addSlide(index: index, spec: snapshot)

        case .moveSlide(let from, let to):
            // After the move the slide sits at `to`, so moving it back is the
            // same action with the endpoints swapped.
            return .moveSlide(from: to, to: from)

        case .updateSpeakerNotes(let index, _):
            guard let snapshot else { return nil }
            return .updateSpeakerNotes(index: index, notes: snapshot.speakerNotes ?? "")
        }
    }
}
