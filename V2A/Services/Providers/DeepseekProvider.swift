import Foundation

enum DeepseekProvider {
    static let info = CleanupProviderInfo(
        id: "deepseek",
        displayName: "Deepseek V4 Flash",
        defaultModel: "deepseek-v4-flash",
        apiKeyHelpURL: "https://platform.deepseek.com/api_keys",
        billingURL: "https://platform.deepseek.com/top_up",
        keychainAccount: "deepseek"
    )

    private static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

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
