import Foundation

enum OpenAIProvider {
    static let info = CleanupProviderInfo(
        id: "openai",
        displayName: "OpenAI GPT-4o mini",
        defaultModel: "gpt-4o-mini",
        apiKeyHelpURL: "https://platform.openai.com/api-keys",
        billingURL: "https://platform.openai.com/settings/organization/billing",
        keychainAccount: "provider.openai"
    )

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    static func cleanup(_ req: CleanupRequest) async throws -> String {
        try await OpenAICompatibleClient.cleanup(
            endpoint: endpoint,
            apiKey: req.apiKey,
            model: req.model ?? info.defaultModel,
            systemPrompt: req.systemPrompt,
            userMessage: req.transcript,
            onToken: req.onToken
        )
    }
}
