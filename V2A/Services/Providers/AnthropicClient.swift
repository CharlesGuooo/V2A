import Foundation

// Anthropic Messages API client.
// Unlike OpenAI-compatible APIs, system prompt is a top-level field (not a message role),
// auth uses x-api-key header (not Authorization: Bearer), and streaming uses
// typed SSE events (content_block_delta → text_delta).
enum AnthropicClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    static func cleanup(
        apiKey: String,
        model: String,
        systemPrompt: String,
        userMessage: String,
        onToken: ((String) -> Void)?
    ) async throws -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 60

        let useStream = onToken != nil
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ],
            "stream": useStream,
            "temperature": 0.2,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        if useStream {
            return try await streamCleanup(req: req, onToken: onToken!)
        } else {
            return try await nonStreamCleanup(req: req)
        }
    }

    private static func streamCleanup(req: URLRequest, onToken: (String) -> Void) async throws -> String {
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse else { throw CleanupError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            var bodyStr = ""
            for try await line in bytes.lines {
                bodyStr += line + "\n"
                if bodyStr.count > 2000 { break }
            }
            throw CleanupError.http(http.statusCode, bodyStr)
        }

        var accumulated = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let type = obj["type"] as? String
            if type == "content_block_delta",
               let delta = obj["delta"] as? [String: Any],
               (delta["type"] as? String) == "text_delta",
               let text = delta["text"] as? String {
                accumulated += text
                onToken(text)
            } else if type == "message_stop" {
                break
            }
        }
        return accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonStreamCleanup(req: URLRequest) async throws -> String {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw CleanupError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw CleanupError.http(http.statusCode, text)
        }
        // content: [{ type: "text", text: "..." }]
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else {
            throw CleanupError.noContent
        }
        let joined = content.compactMap { ($0["text"] as? String) }.joined()
        guard !joined.isEmpty else { throw CleanupError.noContent }
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
