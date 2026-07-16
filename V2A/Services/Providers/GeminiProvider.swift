import Foundation

enum GeminiProvider {
    static let info = CleanupProviderInfo(
        id: "gemini",
        displayName: "Gemini 2.5 Flash",
        defaultModel: "gemini-2.5-flash",
        apiKeyHelpURL: "https://aistudio.google.com/apikey",
        billingURL: "https://console.cloud.google.com/billing",
        keychainAccount: "provider.gemini"
    )

    static func cleanup(_ req: CleanupRequest) async throws -> String {
        try await GeminiClient.cleanup(
            apiKey: req.apiKey,
            model: req.model ?? info.defaultModel,
            systemPrompt: req.systemPrompt,
            userMessage: req.transcript,
            onToken: req.onToken
        )
    }
}
