import Foundation

// Soniox real-time STT WebSocket client. Mirrors V2A/src/providers/SonioxProvider.ts.
//
// Audio framing and the token-merge logic (final accumulates; interim is the
// rolling tail) are kept identical to the web version so the UX matches.

enum SonioxError: LocalizedError {
    case invalidURL
    var errorDescription: String? {
        switch self {
        case .invalidURL: return String(localized: "Soniox URL 异常")
        }
    }
}

final class SonioxClient {
    private let apiKey: String
    private let hotwords: [String]
    private let languageHints: [String]
    private let languageHintsStrict: Bool
    private let sampleRate: Int
    private let onText: (String, Bool) -> Void
    private let onFailure: (AppError) -> Void

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?

    private var finalText = ""

    init(apiKey: String,
         hotwords: [String],
         languageHints: [String] = ["zh", "en"],
         languageHintsStrict: Bool = false,
         sampleRate: Int = 16000,
         onText: @escaping (String, Bool) -> Void,
         onFailure: @escaping (AppError) -> Void) {
        self.apiKey = apiKey
        self.hotwords = hotwords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        self.languageHints = languageHints
        self.languageHintsStrict = languageHintsStrict
        self.sampleRate = sampleRate
        self.onText = onText
        self.onFailure = onFailure
    }

    func start() async throws {
        guard let url = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket") else {
            throw SonioxError.invalidURL
        }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        task.resume()

        var configDict: [String: Any] = [
            "api_key": apiKey,
            "model": "stt-rt-v5",
            "audio_format": "s16le",
            "sample_rate": sampleRate,
            "num_channels": 1,
            "enable_endpoint_detection": true,
        ]
        if !languageHints.isEmpty {
            configDict["language_hints"] = languageHints
            configDict["language_hints_strict"] = languageHintsStrict
        }
        // Soniox v5 context is an object with a `terms` array, not a sentence string.
        if !hotwords.isEmpty {
            configDict["context"] = ["terms": hotwords]
        }
        let data = try JSONSerialization.data(withJSONObject: configDict)
        let str = String(data: data, encoding: .utf8) ?? "{}"
        try await task.send(.string(str))

        Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func sendAudio(_ frame: Data) {
        guard let task = self.task else { return }
        task.send(.data(frame)) { _ in /* ignore */ }
    }

    func stop() async {
        guard let task = self.task else { return }
        // Signal end-of-stream per Soniox docs.
        do {
            try await task.send(.string(""))
        } catch {
            // ignore
        }
        // Mark as our-own-stop so onFail is suppressed.
        self.task = nil
        // Give server 500 ms to push final tokens.
        try? await Task.sleep(nanoseconds: 500_000_000)
        task.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        session = nil
    }

    private func receiveLoop() async {
        while let task = self.task {
            do {
                let msg = try await task.receive()
                switch msg {
                case .string(let str):
                    handleMessage(str)
                case .data:
                    break
                @unknown default:
                    break
                }
            } catch {
                // If we cleared self.task in stop(), the cancellation is expected.
                if self.task != nil {
                    onFailure(FailureClassifier.soniox(code: nil, message: error.localizedDescription))
                }
                return
            }
        }
    }

    private func handleMessage(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Soniox sends an error object before closing on auth / quota / bad config.
        if obj["error_code"] != nil || obj["error_message"] != nil {
            let code = obj["error_code"] as? Int
            let msg = obj["error_message"] as? String
            self.task = nil  // suppress the follow-up "connection dropped" from receiveLoop
            onFailure(FailureClassifier.soniox(code: code, message: msg))
            return
        }

        guard let tokens = obj["tokens"] as? [[String: Any]],
              !tokens.isEmpty else { return }

        var newFinal = ""
        var newInterim = ""
        var sawFinal = false
        for t in tokens {
            guard let text = t["text"] as? String, !text.isEmpty else { continue }
            if (t["is_final"] as? Bool) == true {
                newFinal += text
                sawFinal = true
            } else {
                newInterim += text
            }
        }
        if !newFinal.isEmpty { self.finalText += newFinal }
        let combined = (self.finalText + newInterim).trimmingCharacters(in: .whitespaces)
        onText(combined, sawFinal && newInterim.isEmpty)
    }
}
