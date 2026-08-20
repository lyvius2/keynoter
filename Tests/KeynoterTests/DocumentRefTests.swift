import Foundation
import Testing
@testable import Keynoter

@Suite("DocumentRef")
struct DocumentRefTests {

    @Test("A reference renders as an id-based AppleScript specifier")
    func specifier() {
        let ref = DocumentRef(id: "C29AB346-3939-4EA4-82F9-B840292C80FD")
        #expect(ref.specifier == "document id \"C29AB346-3939-4EA4-82F9-B840292C80FD\"")
    }

    @Test("The id is escaped like any other interpolated value")
    func specifierEscapes() {
        let ref = DocumentRef(id: "a\"b\\c")
        #expect(ref.specifier == "document id \"a\\\"b\\\\c\"")
    }

    @Test("References compare by id")
    func equality() {
        #expect(DocumentRef(id: "A") == DocumentRef(id: "A"))
        #expect(DocumentRef(id: "A") != DocumentRef(id: "B"))
    }

    @Test("No rendered action falls back to the front document")
    func noActionTargetsFrontDocument() {
        let ref = DocumentRef(id: "DECK")
        let actions: [PresentationAction] = [
            .addSlide(index: 1, spec: SlideSpec(title: "T")),
            .addSlide(index: 3, spec: SlideSpec(title: "T")),
            .updateSlide(index: 2, title: "T", body: ["b"]),
            .deleteSlide(index: 2),
            .moveSlide(from: 1, to: 3),
            .moveSlide(from: 3, to: 1),
            .updateSpeakerNotes(index: 2, notes: "N")
        ]
        for action in actions {
            let script = AppleScriptRenderer.render(action, in: ref)
            #expect(!script.contains("front document"), "\(action.summary) targets the front document")
            #expect(!script.contains("document 1"), "\(action.summary) targets document 1")
            #expect(script.contains(ref.specifier), "\(action.summary) does not name its document")
        }
    }

    @Test("Every document-scoped controller script names its document")
    func controllerScriptsTargetTheDocument() {
        let ref = DocumentRef(id: "DECK")
        let scripts = [
            KeynoteController.saveScript(document: ref),
            KeynoteController.saveAsScript(document: ref, path: "/tmp/copy.key"),
            KeynoteController.closeScript(document: ref, save: true),
            KeynoteController.activateScript(document: ref),
            KeynoteController.readSlidesScript(document: ref),
            KeynoteController.readSlideScript(document: ref, index: 1)
        ]
        for script in scripts {
            #expect(!script.contains("front document"))
            #expect(script.contains(ref.specifier))
        }
    }
}
