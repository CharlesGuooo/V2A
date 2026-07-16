import Foundation

// A user-facing error with an optional call-to-action (open a billing page,
// or — when actionURL is nil but actionOpensSettings is true — open Settings).
struct AppError {
    let message: String
    var actionTitle: String? = nil
    var actionURL: URL? = nil
    var actionOpensSettings: Bool = false
}

// Turns raw provider/Soniox failures into friendly, actionable AppErrors.
enum FailureClassifier {

    // MARK: - AI provider (HTTP)

    static func provider(_ error: Error, _ p: CleanupProviderInfo) -> AppError {
        // Network-level
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .timedOut:
                return AppError(message: String(localized: "AI 响应超时，稍后重试。"))
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                return AppError(message: String(localized: "无网络连接，检查网络后重试。"))
            default:
                break
            }
        }

        // HTTP-level
        if case let CleanupError.http(code, body) = error {
            let b = body.lowercased()
            let mentionsQuota = b.contains("insufficient") || b.contains("balance")
                || b.contains("resource_exhausted") || b.contains("quota")
                || b.contains("exceeded your current quota") || b.contains("credit")

            // Balance / quota exhausted
            if code == 402 || mentionsQuota {
                if let url = URL(string: p.billingURL) {
                    return AppError(
                        message: String(localized: "\(p.displayName) 余额 / 额度不足，无法整理。"),
                        actionTitle: String(localized: "去 \(p.displayName) 充值 →"),
                        actionURL: url
                    )
                }
                return AppError(message: String(localized: "\(p.displayName) 余额 / 额度不足，无法整理。"))
            }

            // Invalid / expired key
            if code == 401 || code == 403
                || (b.contains("invalid") && b.contains("key"))
                || b.contains("api_key_invalid") || b.contains("authentication") {
                return AppError(
                    message: String(localized: "\(p.displayName) 的 API key 无效或已失效。"),
                    actionTitle: String(localized: "去设置重新配置"),
                    actionOpensSettings: true
                )
            }

            // Rate limit (429 without quota markers)
            if code == 429 {
                return AppError(message: String(localized: "请求太频繁，稍等几秒再试。"))
            }

            // Fallback: short raw
            let snippet = body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
            return AppError(message: String(localized: "AI 整理失败（\(code)）：\(String(snippet))"))
        }

        return AppError(message: String(localized: "AI 整理失败：\(error.localizedDescription)"))
    }

    // MARK: - Soniox (WebSocket)

    static func soniox(code: Int?, message: String?) -> AppError {
        let raw = (message ?? "").lowercased()
        let consoleURL = URL(string: "https://console.soniox.com/")

        if raw.contains("unauthor") || raw.contains("invalid") || raw.contains("api key")
            || raw.contains("authentication") || code == 401 {
            return AppError(
                message: String(localized: "Soniox 的 API key 无效或已失效。"),
                actionTitle: String(localized: "去设置重新配置"),
                actionOpensSettings: true
            )
        }

        if raw.contains("quota") || raw.contains("balance") || raw.contains("limit")
            || raw.contains("exceeded") || raw.contains("insufficient") {
            return AppError(
                message: String(localized: "Soniox 余额 / 额度不足，无法转录。"),
                actionTitle: String(localized: "去 Soniox 充值 →"),
                actionURL: consoleURL
            )
        }

        // Generic connection failure
        if let m = message, !m.isEmpty {
            let snippet = m.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
            return AppError(message: String(localized: "Soniox 连接出错：\(String(snippet))"))
        }
        return AppError(message: String(localized: "Soniox 连接断开，请重试。"))
    }
}
