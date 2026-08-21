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
    /// `onProgress` reports the plan as the model writes it. It fires many
    /// times per action and carries no result — nothing is applied until the
    /// plan is complete and converted.
    /// `onConversationReset` is forwarded from `FoundationModelClient.plan()`.
    func plan(
        request: String,
        slides: [SlideInfo],
        onProgress: (PlanProgress) -> Void = { _ in },
        onConversationReset: (() -> Void)? = nil
    ) async throws -> [PresentationAction] {
        let prompt = PromptBuilder.prompt(request: request, slides: slides)
        let plan = try await client.plan(
            prompt: prompt,
            onProgress: onProgress,
            onConversationReset: onConversationReset
        )
        return try plan.toActions()
    }
}
