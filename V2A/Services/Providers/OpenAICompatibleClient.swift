import Foundation

// Shared client for OpenAI-compatible chat completions APIs.
// Used by Deepseek, OpenAI, and Groq — they all accept the same JSON body shape
// against /chat/completions and stream via `data: {...}\n\ndata: [DONE]` lines.
enum OpenAICompatibleClient {
    static func cleanup(
        endpoint: URL,
        apiKey: String,
        model: String,
        systemPrompt: String,
        userMessage: String,
        onToken: ((String) -> Void)?
    ) async throws -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60

        let useStream = onToken != nil
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage],
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
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }
            accumulated += content
            onToken(content)
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
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw CleanupError.noContent
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
