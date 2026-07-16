import Foundation

// Google Gemini generateContent / streamGenerateContent client.
// Auth is via ?key=... query string (not header). Body uses contents/parts schema.
// System prompt goes in systemInstruction field, not in contents.
enum GeminiClient {
    static func cleanup(
        apiKey: String,
        model: String,
        systemPrompt: String,
        userMessage: String,
        onToken: ((String) -> Void)?
    ) async throws -> String {
        let useStream = onToken != nil
        let method = useStream ? "streamGenerateContent" : "generateContent"
        let urlString: String
        if useStream {
            urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):\(method)?alt=sse&key=\(apiKey)"
        } else {
            urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):\(method)?key=\(apiKey)"
        }
        guard let url = URL(string: urlString) else { throw CleanupError.badResponse }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": userMessage]]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2
            ]
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
            if let text = extractText(from: obj) {
                accumulated += text
                onToken(text)
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
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = extractText(from: obj) else {
            throw CleanupError.noContent
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Pulls all text parts out of a generateContent response chunk.
    // Shape: { candidates: [ { content: { parts: [ { text: "..." } ] } } ] }
    private static func extractText(from obj: [String: Any]) -> String? {
        guard let candidates = obj["candidates"] as? [[String: Any]] else { return nil }
        var out = ""
        for cand in candidates {
            guard let content = cand["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }
            for p in parts {
                if let t = p["text"] as? String { out += t }
            }
        }
        return out.isEmpty ? nil : out
    }
}
