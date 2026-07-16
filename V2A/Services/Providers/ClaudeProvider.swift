import Foundation

enum ClaudeProvider {
    static let info = CleanupProviderInfo(
        id: "claude",
        displayName: "Claude Haiku 4.5",
        defaultModel: "claude-haiku-4-5-20251001",
        apiKeyHelpURL: "https://console.anthropic.com/settings/keys",
        billingURL: "https://console.anthropic.com/settings/billing",
        keychainAccount: "provider.claude"
    )

    static func cleanup(_ req: CleanupRequest) async throws -> String {
        try await AnthropicClient.cleanup(
            apiKey: req.apiKey,
            model: req.model ?? info.defaultModel,
            systemPrompt: req.systemPrompt,
            userMessage: req.transcript,
            onToken: req.onToken
        )
    }
}
