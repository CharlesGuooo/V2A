import Foundation

enum GroqProvider {
    static let info = CleanupProviderInfo(
        id: "groq",
        displayName: "Groq Llama 3.1 8B",
        defaultModel: "llama-3.1-8b-instant",
        apiKeyHelpURL: "https://console.groq.com/keys",
        billingURL: "https://console.groq.com/settings/billing",
        keychainAccount: "provider.groq"
    )

    private static let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

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
