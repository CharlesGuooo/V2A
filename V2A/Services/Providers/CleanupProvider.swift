import Foundation

enum CleanupError: LocalizedError {
    case http(Int, String)
    case noContent
    case badResponse
    case unknownProvider(String)
    case missingApiKey

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            let snippet = body.prefix(300)
            return "HTTP \(code): \(snippet.isEmpty ? String(localized: "未知错误") : String(snippet))"
        case .noContent:
            return String(localized: "AI 返回格式异常：缺少内容字段")
        case .badResponse:
            return String(localized: "AI 返回非 HTTP 响应")
        case .unknownProvider(let id):
            return String(localized: "未知的 provider：\(id)")
        case .missingApiKey:
            return String(localized: "缺少 API key")
        }
    }
}

struct CleanupProviderInfo {
    let id: String
    let displayName: String
    let defaultModel: String
    let apiKeyHelpURL: String
    let billingURL: String
    let keychainAccount: String
}

struct CleanupRequest {
    let transcript: String
    let systemPrompt: String
    let apiKey: String
    let model: String?
    let onToken: ((String) -> Void)?
}

enum ProviderRegistry {
    static let all: [CleanupProviderInfo] = [
        DeepseekProvider.info,
        ClaudeProvider.info,
        GeminiProvider.info,
        OpenAIProvider.info,
        GroqProvider.info,
    ]

    static let defaultId = "deepseek"

    static func find(id: String) -> CleanupProviderInfo? {
        all.first { $0.id == id }
    }

    static func cleanup(_ req: CleanupRequest, providerId: String) async throws -> String {
        switch providerId {
        case "deepseek": return try await DeepseekProvider.cleanup(req)
        case "claude":   return try await ClaudeProvider.cleanup(req)
        case "gemini":   return try await GeminiProvider.cleanup(req)
        case "openai":   return try await OpenAIProvider.cleanup(req)
        case "groq":     return try await GroqProvider.cleanup(req)
        default:         throw CleanupError.unknownProvider(providerId)
        }
    }
}
