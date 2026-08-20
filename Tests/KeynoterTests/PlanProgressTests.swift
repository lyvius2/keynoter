import Foundation
import Testing
import FoundationModels
@testable import Keynoter

/// What the user watches while the model writes a plan.
///
/// Snapshots are built from JSON rather than from a live generation: the shapes
/// below are exactly what streaming produces — an action with a kind but no
/// title yet, a title but no body — and rebuilding them by hand keeps the model
/// call out of the suite.
@Suite("Plan progress")
struct PlanProgressTests {

    private func progress(_ json: String) throws -> PlanProgress {
        PlanProgress(try PresentationPlan.PartiallyGenerated(GeneratedContent(json: json)))
    }

    @Test("Before the first action there is nothing to report")
    func noActionsYet() throws {
        #expect(try progress(#"{"actions": []}"#).display == "…")
    }

    @Test("An action with only its kind still names the change")
    func kindOnly() throws {
        let step = try progress(#"{"actions": [{"kind": "addSlide"}]}"#)
        #expect(step.actionCount == 1)
        #expect(step.display == "1. add slide")
    }

    @Test("The title appears as soon as the model writes it")
    func titleAppears() throws {
        let step = try progress(#"{"actions": [{"kind": "addSlide", "slideIndex": 4, "title": "Why MSK"}]}"#)
        #expect(step.display == #"1. add slide 4 "Why MSK""#)
    }

    @Test("The step number counts the plan so far; the text describes the newest step")
    func countsAndDescribesTheLast() throws {
        let step = try progress("""
        {"actions": [
          {"kind": "addSlide", "slideIndex": 2, "title": "Today"},
          {"kind": "deleteSlide", "slideIndex": 5},
          {"kind": "updateSlide", "slideIndex": 3, "title": "Costs"}
        ]}
        """)
        #expect(step.actionCount == 3)
        #expect(step.display == #"3. update slide 3 "Costs""#)
    }

    @Test("A move reads as a move only once its destination is written")
    func moveDestination() throws {
        let started = try progress(#"{"actions": [{"kind": "moveSlide", "slideIndex": 2}]}"#)
        #expect(started.display == "1. move slide 2")

        let finished = try progress(#"{"actions": [{"kind": "moveSlide", "slideIndex": 2, "targetIndex": 5}]}"#)
        #expect(finished.display == "1. move slide 2 to 5")
    }

    @Test("Deletes and notes read the way they do once applied")
    func otherKinds() throws {
        #expect(try progress(#"{"actions": [{"kind": "deleteSlide", "slideIndex": 5}]}"#).display
            == "1. delete slide 5")
        #expect(try progress(#"{"actions": [{"kind": "updateSpeakerNotes", "slideIndex": 2}]}"#).display
            == "1. update speaker notes on slide 2")
    }

    @Test("An action that has not said what it is yet shows as pending, not as a guess")
    func kindNotWrittenYet() throws {
        let step = try progress(#"{"actions": [{"kind": "addSlide", "slideIndex": 1}, {"slideIndex": 2}]}"#)
        #expect(step.actionCount == 2)
        #expect(step.display == "2. …")
    }

    @Test("A slide number the model has not written yet is left out")
    func indexNotWrittenYet() throws {
        #expect(try progress(#"{"actions": [{"kind": "deleteSlide"}]}"#).display == "1. delete slide")
    }

    @Test("An empty title is 'not written yet', not a blank title")
    func emptyTitleIsOmitted() throws {
        #expect(try progress(#"{"actions": [{"kind": "addSlide", "slideIndex": 1, "title": ""}]}"#).display
            == "1. add slide 1")
        #expect(try progress(#"{"actions": [{"kind": "addSlide", "slideIndex": 1, "title": "   "}]}"#).display
            == "1. add slide 1")
    }

    @Test("A long title is truncated so the line can be rewritten in place")
    func longTitleIsTruncated() throws {
        let long = String(repeating: "a", count: 80)
        let step = try progress(#"{"actions": [{"kind": "addSlide", "slideIndex": 1, "title": "\#(long)"}]}"#)
        #expect(step.display.contains("…"))
        // 40 characters, an ellipsis, two quotes.
        #expect(step.display.count == "1. add slide 1 ".count + 43)
    }

    @Test("Bullets are counted as they arrive, so the line keeps moving")
    func bulletsAreCounted() throws {
        let one = try progress(#"{"actions": [{"kind": "addSlide", "slideIndex": 2, "title": "Today", "body": ["First"]}]}"#)
        #expect(one.display == #"1. add slide 2 "Today" (1 bullet)"#)

        let three = try progress("""
        {"actions": [{"kind": "addSlide", "slideIndex": 2, "title": "Today", "body": ["First", "Second", "Thi"]}]}
        """)
        // The third bullet is still being written; a half-written one counts.
        #expect(three.display == #"1. add slide 2 "Today" (3 bullets)"#)
    }

    @Test("Kinds that carry no body say nothing about bullets")
    func noBulletCountWhereThereIsNoBody() throws {
        #expect(try progress(#"{"actions": [{"kind": "deleteSlide", "slideIndex": 2, "body": ["stray"]}]}"#).display
            == "1. delete slide 2")
        #expect(try progress(#"{"actions": [{"kind": "addSlide", "slideIndex": 2, "body": []}]}"#).display
            == "1. add slide 2")
    }

    @Test("A multi-line title stays on one line")
    func multilineTitleIsCollapsed() throws {
        let step = try progress(#"{"actions": [{"kind": "addSlide", "slideIndex": 1, "title": "Why\nMSK"}]}"#)
        #expect(step.display == #"1. add slide 1 "Why MSK""#)
    }
}
