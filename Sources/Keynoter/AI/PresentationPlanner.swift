import Foundation

/// Turns one natural-language request into validated `PresentationAction`s.
///
/// The seam between "what the model said" and "what Keynoter will do": it owns
/// prompt construction and plan conversion, leaving `FoundationModelClient` to
/// deal only with the model session. Nothing here talks to Keynote — applying
/// the actions is `ActionRunner`'s job.
@MainActor
struct PresentationPlanner {

    let client: FoundationModelClient

    init(client: FoundationModelClient = FoundationModelClient()) {
        self.client = client
    }

    /// `slides` is the deck as it stands, and it matters: the model addresses
    /// slides by number, so a stale outline produces a plan aimed at the wrong
    /// slides. Callers refresh before asking.
    func plan(request: String, slides: [SlideInfo]) async throws -> [PresentationAction] {
        let prompt = PromptBuilder.prompt(request: request, slides: slides)
        let plan = try await client.plan(prompt: prompt)
        return try plan.toActions()
    }
}
