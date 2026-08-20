import Testing
@testable import Keynoter

@Suite("PresentationSpec")
struct PresentationSpecTests {

    @Test("Default init produces an empty spec")
    func specDefaults() {
        let spec = PresentationSpec()
        #expect(spec.title == "")
        #expect(spec.theme == nil)
        #expect(spec.slides.isEmpty)
    }

    @Test("Default SlideSpec uses titleAndBody with everything unset")
    func slideDefaults() {
        let slide = SlideSpec()
        #expect(slide.layout == .titleAndBody)
        #expect(slide.title == nil)
        #expect(slide.body.isEmpty)
        #expect(slide.speakerNotes == nil)
    }

    @Test("SlideLayout exposes all three cases")
    func layoutCases() {
        #expect(SlideLayout.allCases == [.blank, .title, .titleAndBody])
    }

    @Test("Equality is structural")
    func equality() {
        let a = PresentationSpec(
            title: "T", theme: "White",
            slides: [SlideSpec(layout: .title, title: "one")]
        )
        let b = PresentationSpec(
            title: "T", theme: "White",
            slides: [SlideSpec(layout: .title, title: "one")]
        )
        #expect(a == b)
    }
}
