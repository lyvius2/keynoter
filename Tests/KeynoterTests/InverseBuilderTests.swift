import Foundation
import Testing
@testable import Keynoter

@Suite("InverseBuilder — snapshot requirements")
struct InverseBuilderSnapshotTests {

    @Test("Actions that carry everything their inverse needs require no snapshot")
    func noSnapshotNeeded() {
        #expect(InverseBuilder.snapshotIndex(for: .createPresentation(title: "Deck", theme: nil)) == nil)
        #expect(InverseBuilder.snapshotIndex(for: .addSlide(index: 2, spec: SlideSpec())) == nil)
        #expect(InverseBuilder.snapshotIndex(for: .moveSlide(from: 2, to: 5)) == nil)
    }

    @Test("Actions that destroy content name the slide to capture first")
    func snapshotNeeded() {
        #expect(InverseBuilder.snapshotIndex(for: .deleteSlide(index: 3)) == 3)
        #expect(InverseBuilder.snapshotIndex(for: .updateSlide(index: 4, title: "New", body: nil)) == 4)
        #expect(InverseBuilder.snapshotIndex(for: .updateSpeakerNotes(index: 7, notes: "Hi")) == 7)
    }
}

@Suite("InverseBuilder — inverses")
struct InverseBuilderTests {

    private let snapshot = SlideSpec(
        layout: .titleAndBody,
        title: "Old title",
        body: ["Old one", "Old two"],
        speakerNotes: "Old notes"
    )

    @Test("Creating a presentation cannot be undone")
    func createPresentationHasNoInverse() {
        let inverse = InverseBuilder.inverse(
            of: .createPresentation(title: "Deck", theme: "White"),
            snapshot: nil
        )
        #expect(inverse == nil)
    }

    @Test("Adding a slide is undone by deleting it")
    func addSlide() {
        let inverse = InverseBuilder.inverse(
            of: .addSlide(index: 3, spec: SlideSpec(title: "New")),
            snapshot: nil
        )
        #expect(inverse == .deleteSlide(index: 3))
    }

    @Test("Deleting a slide is undone by re-adding the captured slide")
    func deleteSlide() {
        let inverse = InverseBuilder.inverse(of: .deleteSlide(index: 2), snapshot: snapshot)
        #expect(inverse == .addSlide(index: 2, spec: snapshot))
    }

    @Test("Deleting a slide cannot be undone without a snapshot")
    func deleteSlideWithoutSnapshot() {
        #expect(InverseBuilder.inverse(of: .deleteSlide(index: 2), snapshot: nil) == nil)
    }

    @Test("An update is undone by writing back only the fields it touched")
    func updateSlideRestoresTouchedFieldsOnly() {
        let inverse = InverseBuilder.inverse(
            of: .updateSlide(index: 2, title: "New title", body: nil),
            snapshot: snapshot
        )
        // body stays nil: the original update left it alone, so undo must too.
        #expect(inverse == .updateSlide(index: 2, title: "Old title", body: nil))
    }

    @Test("An update that cleared the body is undone by restoring the bullets")
    func updateSlideRestoresBody() {
        let inverse = InverseBuilder.inverse(
            of: .updateSlide(index: 2, title: nil, body: []),
            snapshot: snapshot
        )
        #expect(inverse == .updateSlide(index: 2, title: nil, body: ["Old one", "Old two"]))
    }

    @Test("A title written onto a slide that had none is undone by clearing it")
    func updateSlideOnMissingTitlePlaceholder() {
        let blank = SlideSpec(layout: .blank, title: nil, body: [])
        let inverse = InverseBuilder.inverse(
            of: .updateSlide(index: 1, title: "New title", body: nil),
            snapshot: blank
        )
        #expect(inverse == .updateSlide(index: 1, title: "", body: nil))
    }

    @Test("An update cannot be undone without a snapshot")
    func updateSlideWithoutSnapshot() {
        let action = PresentationAction.updateSlide(index: 2, title: "New", body: nil)
        #expect(InverseBuilder.inverse(of: action, snapshot: nil) == nil)
    }

    @Test("A move is undone by swapping its endpoints")
    func moveSlide() {
        #expect(InverseBuilder.inverse(of: .moveSlide(from: 2, to: 5), snapshot: nil)
                == .moveSlide(from: 5, to: 2))
        #expect(InverseBuilder.inverse(of: .moveSlide(from: 5, to: 2), snapshot: nil)
                == .moveSlide(from: 2, to: 5))
    }

    @Test("Speaker notes are undone by restoring the captured notes")
    func updateSpeakerNotes() {
        let inverse = InverseBuilder.inverse(
            of: .updateSpeakerNotes(index: 2, notes: "New notes"),
            snapshot: snapshot
        )
        #expect(inverse == .updateSpeakerNotes(index: 2, notes: "Old notes"))
    }

    @Test("Notes added to a slide that had none are undone by clearing them")
    func updateSpeakerNotesOnSlideWithoutNotes() {
        let noNotes = SlideSpec(layout: .titleAndBody, title: "T", body: [], speakerNotes: nil)
        let inverse = InverseBuilder.inverse(
            of: .updateSpeakerNotes(index: 2, notes: "New notes"),
            snapshot: noNotes
        )
        #expect(inverse == .updateSpeakerNotes(index: 2, notes: ""))
    }

    @Test("Applying an inverse twice returns to the starting action")
    func inverseOfInverseRoundTrips() {
        let move = PresentationAction.moveSlide(from: 3, to: 6)
        let once = InverseBuilder.inverse(of: move, snapshot: nil)
        let twice = once.flatMap { InverseBuilder.inverse(of: $0, snapshot: nil) }
        #expect(twice == move)
    }
}