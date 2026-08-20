import Foundation
import Testing
@testable import Keynoter

/// Builds a `GenerableAction` the way the model would: every field present,
/// unused ones empty.
private func action(
    _ kind: GenerableActionKind,
    slideIndex: Int = 1,
    targetIndex: Int = 1,
    title: String = "",
    body: [String] = [],
    speakerNotes: String = ""
) -> GenerableAction {
    GenerableAction(
        kind: kind,
        slideIndex: slideIndex,
        targetIndex: targetIndex,
        title: title,
        body: body,
        speakerNotes: speakerNotes
    )
}

@Suite("PresentationPlan conversion")
struct PresentationPlanConversionTests {

    @Test("addSlide carries title, bullets and notes into a SlideSpec")
    func addSlide() throws {
        let converted = try action(
            .addSlide,
            slideIndex: 3,
            title: "TO-BE Architecture",
            body: ["MSK cluster", "Private link"],
            speakerNotes: "Mention cost"
        ).toAction(position: 0)

        #expect(converted == .addSlide(index: 3, spec: SlideSpec(
            layout: .titleAndBody,
            title: "TO-BE Architecture",
            body: ["MSK cluster", "Private link"],
            speakerNotes: "Mention cost"
        )))
    }

    @Test("The layout follows from which placeholders the model filled in")
    func layoutInference() throws {
        func layout(title: String, body: [String]) throws -> SlideLayout {
            let converted = try action(.addSlide, title: title, body: body).toAction(position: 0)
            guard case .addSlide(_, let spec) = converted else {
                Issue.record("expected addSlide")
                return .blank
            }
            return spec.layout
        }

        #expect(try layout(title: "T", body: ["b"]) == .titleAndBody)
        #expect(try layout(title: "T", body: []) == .title)
        #expect(try layout(title: "", body: []) == .blank)
        // Bullets without a title still need a body placeholder to write into.
        #expect(try layout(title: "", body: ["b"]) == .titleAndBody)
    }

    @Test("An empty field on updateSlide means leave it alone, not clear it")
    func updateSlideTreatsEmptyAsUntouched() throws {
        let titleOnly = try action(.updateSlide, slideIndex: 2, title: "New").toAction(position: 0)
        #expect(titleOnly == .updateSlide(index: 2, title: "New", body: nil))

        let bodyOnly = try action(.updateSlide, slideIndex: 2, body: ["a"]).toAction(position: 0)
        #expect(bodyOnly == .updateSlide(index: 2, title: nil, body: ["a"]))
    }

    @Test("An update that would change nothing is rejected, not silently applied")
    func updateSlideWithNothingToDo() {
        #expect(throws: PlanConversionError.emptyAction(position: 4, kind: "updateSlide")) {
            try action(.updateSlide, slideIndex: 2).toAction(position: 4)
        }
    }

    @Test("deleteSlide and moveSlide read their slide numbers")
    func deleteAndMove() throws {
        #expect(try action(.deleteSlide, slideIndex: 5).toAction(position: 0)
                == .deleteSlide(index: 5))
        #expect(try action(.moveSlide, slideIndex: 2, targetIndex: 6).toAction(position: 0)
                == .moveSlide(from: 2, to: 6))
    }

    @Test("Empty speaker notes are rejected rather than clearing the slide's notes")
    func emptySpeakerNotes() {
        #expect(throws: PlanConversionError.emptyAction(position: 0, kind: "updateSpeakerNotes")) {
            try action(.updateSpeakerNotes, slideIndex: 2).toAction(position: 0)
        }
    }

    @Test("A plan converts in order")
    func planPreservesOrder() throws {
        let plan = PresentationPlan(actions: [
            action(.addSlide, slideIndex: 2, title: "One"),
            action(.deleteSlide, slideIndex: 5),
            action(.moveSlide, slideIndex: 1, targetIndex: 3)
        ])

        #expect(try plan.toActions() == [
            .addSlide(index: 2, spec: SlideSpec(layout: .title, title: "One", body: [])),
            .deleteSlide(index: 5),
            .moveSlide(from: 1, to: 3)
        ])
    }

    @Test("An empty plan is an error, not a silent no-op")
    func emptyPlan() {
        #expect(throws: PlanConversionError.emptyPlan) {
            try PresentationPlan(actions: []).toActions()
        }
    }

    @Test("Conversion does not bounds-check — that is the validator's job")
    func conversionDoesNotValidate() throws {
        // Slide 99 of a 2-slide deck converts fine here and is rejected later,
        // against the live slide count.
        let converted = try action(.deleteSlide, slideIndex: 99).toAction(position: 0)
        #expect(converted == .deleteSlide(index: 99))

        #expect(throws: ValidationError.self) {
            try ValidationEngine.validate(converted, in: ValidationContext(slideCount: 2))
        }
    }
}

@Suite("PromptBuilder")
struct PromptBuilderTests {

    @Test("The outline numbers every slide the model may refer to")
    func outline() {
        let text = PromptBuilder.outline([
            SlideInfo(index: 1, title: "Introduction"),
            SlideInfo(index: 2, title: "AS-IS Architecture")
        ])

        #expect(text == """
        The presentation has 2 slides:
          1. Introduction
          2. AS-IS Architecture
        """)
    }

    @Test("An untitled slide still gets a row, so later numbers stay right")
    func untitledSlideKeepsItsRow() {
        let text = PromptBuilder.outline([
            SlideInfo(index: 1, title: ""),
            SlideInfo(index: 2, title: "Second")
        ])

        #expect(text.contains("1. (untitled)"))
        #expect(text.contains("2. Second"))
    }

    @Test("An empty deck says so instead of printing an empty list")
    func emptyOutline() {
        #expect(PromptBuilder.outline([]) == "The presentation is empty.")
    }

    @Test("One slide is described in the singular")
    func singular() {
        let text = PromptBuilder.outline([SlideInfo(index: 1, title: "Only")])
        #expect(text.hasPrefix("The presentation has 1 slide:"))
    }

    @Test("A long deck is truncated with a count of what was left out")
    func longDeckIsTruncated() {
        let slides = (1...50).map { SlideInfo(index: $0, title: "Slide \($0)") }
        let text = PromptBuilder.outline(slides)

        #expect(text.contains("50. ") == false)
        #expect(text.contains("40. Slide 40"))
        #expect(text.contains("… and 10 more."))
    }

    @Test("Long titles are truncated and newlines collapsed")
    func titleDisplay() {
        #expect(PromptBuilder.displayTitle("  Spaced  ") == "Spaced")
        #expect(PromptBuilder.displayTitle("Two\nlines") == "Two lines")
        #expect(PromptBuilder.displayTitle("   ") == "(untitled)")

        let long = String(repeating: "a", count: 200)
        let shown = PromptBuilder.displayTitle(long)
        #expect(shown.count == PromptBuilder.maxOutlineTitleLength + 1)
        #expect(shown.hasSuffix("…"))
    }

    @Test("The prompt puts the deck before the request")
    func promptOrder() {
        let text = PromptBuilder.prompt(
            request: "  Delete slide 2.  ",
            slides: [SlideInfo(index: 1, title: "Intro"), SlideInfo(index: 2, title: "Detail")]
        )

        #expect(text == """
        The presentation has 2 slides:
          1. Intro
          2. Detail

        Request: Delete slide 2.
        """)
    }

    @Test("The instructions forbid AppleScript and pin the indexing rules")
    func instructions() {
        let text = PromptBuilder.instructions
        #expect(text.contains("Never write AppleScript"))
        #expect(text.contains("1-based"))
        #expect(text.contains("in the order you list them"))
    }
}
