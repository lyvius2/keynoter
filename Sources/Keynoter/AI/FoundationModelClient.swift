import Foundation
import FoundationModels

/// Whether the on-device model can be used right now, in Keynoter's terms.
enum ModelAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool { self == .available }
}

enum PlannerError: Error, Equatable {
    case modelUnavailable(reason: String)
    /// The model declined the request, or the request tripped a safety guardrail.
    case refused(detail: String)
    /// Anything else the framework reported, already turned into a sentence.
    case generationFailed(detail: String)
}

/// Owns the `LanguageModelSession` and every direct call into FoundationModels.
///
/// The session is kept alive across requests so a follow-up like "make that
/// shorter" still has the earlier exchange to refer to. That transcript grows,
/// so a context-window overflow is handled by starting a fresh session and
/// retrying once — losing the conversational memory is a far better outcome
/// than refusing the request.
///
/// Main-actor isolated to match the REPL, which is the only caller.
@MainActor
final class FoundationModelClient {

    /// Deterministic decoding. A presentation plan is a structured command, not
    /// creative writing: the same request against the same deck should produce
    /// the same slides, and it makes a misbehaving prompt reproducible.
    nonisolated static let options = GenerationOptions(sampling: .greedy)

    private let instructions: String
    private var session: LanguageModelSession?

    init(instructions: String = PromptBuilder.instructions) {
        self.instructions = instructions
    }

    // MARK: - Availability

    /// Why the model cannot be used, phrased for someone who has never heard of
    /// `SystemLanguageModel`.
    static func availability() -> ModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: describe(reason))
        @unknown default:
            return .unavailable(reason: "Apple Intelligence is unavailable for an unknown reason.")
        }
    }

    nonisolated static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This Mac does not support Apple Intelligence, so Keynoter cannot plan slides. Slash commands still work."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is turned off. Enable it in System Settings > Apple Intelligence & Siri."
        case .modelNotReady:
            return "The on-device model is still downloading or preparing. Try again in a few minutes."
        @unknown default:
            return "Apple Intelligence is unavailable for an unknown reason."
        }
    }

    /// Starts loading the model so the first real request does not pay for it.
    /// Best-effort: if the model is unavailable this does nothing.
    func prewarm() {
        guard Self.availability().isAvailable else { return }
        activeSession().prewarm()
    }

    // MARK: - Planning

    /// Asks the model to fill in a `PresentationPlan` for `prompt`.
    func plan(prompt: String) async throws -> PresentationPlan {
        if case .unavailable(let reason) = Self.availability() {
            throw PlannerError.modelUnavailable(reason: reason)
        }

        do {
            return try await respond(to: prompt)
        } catch let error as LanguageModelSession.GenerationError {
            // The transcript filled up. Drop it and try once with a clean
            // session — the deck outline travels in the prompt, so nothing the
            // planner actually needs is lost.
            guard case .exceededContextWindowSize = error else {
                throw Self.translate(error)
            }
            session = nil
            do {
                return try await respond(to: prompt)
            } catch {
                throw Self.translate(error)
            }
        } catch {
            throw Self.translate(error)
        }
    }

    private func respond(to prompt: String) async throws -> PresentationPlan {
        try await activeSession()
            .respond(to: prompt, generating: PresentationPlan.self, options: Self.options)
            .content
    }

    private func activeSession() -> LanguageModelSession {
        if let session { return session }
        let created = LanguageModelSession(instructions: instructions)
        session = created
        return created
    }

    /// Forgets the conversation. The next request starts from the instructions
    /// alone.
    func resetConversation() {
        session = nil
    }

    // MARK: - Errors

    nonisolated static func translate(_ error: Error) -> PlannerError {
        guard let error = error as? LanguageModelSession.GenerationError else {
            return .generationFailed(detail: "\(error)")
        }
        switch error {
        case .guardrailViolation:
            return .refused(detail: "The request tripped Apple Intelligence's safety filter. Try rewording it.")
        case .refusal:
            return .refused(detail: "The model declined that request.")
        case .exceededContextWindowSize:
            return .generationFailed(detail: "The conversation grew too long even after starting over. Try a shorter request.")
        case .unsupportedLanguageOrLocale:
            return .generationFailed(detail: "Apple Intelligence does not support this language yet.")
        case .assetsUnavailable:
            return .generationFailed(detail: "The on-device model is not ready. Check /doctor.")
        case .rateLimited:
            return .generationFailed(detail: "Apple Intelligence is rate limiting requests. Try again shortly.")
        case .decodingFailure:
            return .generationFailed(detail: "The model's plan could not be read. Try rewording the request.")
        case .concurrentRequests:
            return .generationFailed(detail: "Another request is still running.")
        case .unsupportedGuide:
            return .generationFailed(detail: "Keynoter's plan schema was rejected by the model — this is a bug.")
        @unknown default:
            return .generationFailed(detail: error.localizedDescription)
        }
    }
}

extension PlannerError {

    var userMessage: String {
        switch self {
        case .modelUnavailable(let reason): reason
        case .refused(let detail): detail
        case .generationFailed(let detail): detail
        }
    }
}
