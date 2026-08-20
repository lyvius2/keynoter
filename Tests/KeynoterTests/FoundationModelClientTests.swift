import Foundation
import Testing
import FoundationModels
@testable import Keynoter

/// Covers the pure parts of the model layer: how unavailability and generation
/// failures are turned into something a person can act on. The model call
/// itself stays out of the suite.
@Suite("FoundationModelClient messages")
struct FoundationModelClientTests {

    private func context() -> LanguageModelSession.GenerationError.Context {
        .init(debugDescription: "test")
    }

    @Test("Each unavailability reason explains what to do about it")
    func unavailableReasons() {
        let notEnabled = FoundationModelClient.describe(.appleIntelligenceNotEnabled)
        #expect(notEnabled.contains("System Settings"))

        let notReady = FoundationModelClient.describe(.modelNotReady)
        #expect(notReady.contains("Try again"))

        // An ineligible Mac is not a fixable state, so it says what still works.
        let ineligible = FoundationModelClient.describe(.deviceNotEligible)
        #expect(ineligible.contains("Slash commands still work"))
    }

    @Test("A guardrail violation is reported as a refusal, not a crash")
    func guardrailViolation() {
        let error = FoundationModelClient.translate(
            LanguageModelSession.GenerationError.guardrailViolation(context())
        )
        guard case .refused(let detail) = error else {
            Issue.record("expected .refused, got \(error)")
            return
        }
        #expect(detail.contains("rewording"))
    }

    @Test("A context overflow that survives the retry says the request is too long")
    func contextOverflow() {
        let error = FoundationModelClient.translate(
            LanguageModelSession.GenerationError.exceededContextWindowSize(context())
        )
        #expect(error == .generationFailed(
            detail: "The conversation grew too long even after starting over. Try a shorter request."
        ))
    }

    @Test("A schema rejection is called out as a Keynoter bug, not user error")
    func unsupportedGuide() {
        let error = FoundationModelClient.translate(
            LanguageModelSession.GenerationError.unsupportedGuide(context())
        )
        #expect(error.userMessage.contains("bug"))
    }

    @Test("A non-FoundationModels error still produces a message")
    func unknownError() {
        struct Boom: Error {}
        let error = FoundationModelClient.translate(Boom())
        guard case .generationFailed = error else {
            Issue.record("expected .generationFailed, got \(error)")
            return
        }
        #expect(error.userMessage.isEmpty == false)
    }

    @Test("Availability compares as a value")
    func availability() {
        #expect(ModelAvailability.available.isAvailable)
        #expect(ModelAvailability.unavailable(reason: "nope").isAvailable == false)
    }

    @Test("Every planner error carries a non-empty message for the REPL")
    func plannerErrorMessages() {
        let errors: [PlannerError] = [
            .modelUnavailable(reason: "off"),
            .refused(detail: "no"),
            .generationFailed(detail: "broke")
        ]
        for error in errors {
            #expect(error.userMessage.isEmpty == false)
        }
    }

    @Test("Planning is deterministic — the same request should plan the same way")
    func greedySampling() {
        #expect(FoundationModelClient.options == GenerationOptions(sampling: .greedy))
    }
}
