import Foundation
import Observation
import SwiftUI
import UIKit

// 1:1 port of V2A/src/main.ts state machine + handlers.
// All state mutation is on @MainActor; service callbacks bounce through Task { @MainActor }.

@MainActor
@Observable
final class AppState {
    // MARK: - State (matches AppModel in V2A/src/ui.ts)
    var recording: Bool = false
    var starting: Bool = false
    var stopping: Bool = false
    var hotwords: [String] = []
    var finalText: String = ""
    var liveText: String = ""
    var processedText: String = ""
    var processing: Bool = false
    var rawCopied: Bool = false
    var processedCopied: Bool = false
    var hasSonioxKey: Bool = false
    var hasActiveProviderKey: Bool = false
    var activeProviderId: String = ProviderRegistry.defaultId
    var selectedLanguages: [String] = ["zh", "en"]
    var promptSlot1: String = ""
    var promptSlot2: String = ""
    var onboarded: Bool = false
    var uiLanguage: String = "system"   // "system" | "zh" | "en"
    var appearance: String = "system"   // "system" | "light" | "dark"
    var autoCopy: Bool = false
    var toast: String? = nil
    var appError: AppError? = nil
    var showSettings: Bool = false

    // Set true whenever a transcript token arrives during a recording session;
    // used to detect an all-silence recording.
    @ObservationIgnored private var receivedAnyText = false
    // True when stopRecording was triggered by an error (skip the silence hint).
    @ObservationIgnored private var stoppedDueToError = false

    // MARK: - Internal
    @ObservationIgnored private var recorder: MicRecorder?
    @ObservationIgnored private var soniox: SonioxClient?
    @ObservationIgnored private var processTask: Task<Void, Never>?
    @ObservationIgnored private var rawCopiedTask: Task<Void, Never>?
    @ObservationIgnored private var processedCopiedTask: Task<Void, Never>?

    private static let activeProviderKey = "v2a.active_provider.v1"
    private static let languagesKey = "v2a.languages.v1"
    private static let promptSlot1Key = "v2a.prompt_slot_1.v1"
    private static let promptSlot2Key = "v2a.prompt_slot_2.v1"
    private static let onboardedKey = "v2a.onboarded.v1"
    private static let uiLanguageKey = "v2a.ui_language.v1"
    private static let appearanceKey = "v2a.appearance.v1"
    private static let autoCopyKey = "v2a.auto_copy.v1"

    init() {
        self.hotwords = HotwordsStore.load()
        let stored = UserDefaults.standard.string(forKey: Self.activeProviderKey) ?? ProviderRegistry.defaultId
        self.activeProviderId = ProviderRegistry.find(id: stored) != nil ? stored : ProviderRegistry.defaultId
        if let langs = UserDefaults.standard.stringArray(forKey: Self.languagesKey), !langs.isEmpty {
            self.selectedLanguages = langs
        }
        self.promptSlot1 = UserDefaults.standard.string(forKey: Self.promptSlot1Key) ?? ""
        self.promptSlot2 = UserDefaults.standard.string(forKey: Self.promptSlot2Key) ?? ""
        if let lang = UserDefaults.standard.string(forKey: Self.uiLanguageKey),
           ["system", "zh", "en"].contains(lang) {
            self.uiLanguage = lang
        }
        if let appr = UserDefaults.standard.string(forKey: Self.appearanceKey),
           ["system", "light", "dark"].contains(appr) {
            self.appearance = appr
        }
        self.autoCopy = UserDefaults.standard.bool(forKey: Self.autoCopyKey)
        // Existing users (already have keys) skip onboarding.
        if UserDefaults.standard.bool(forKey: Self.onboardedKey) {
            self.onboarded = true
        } else {
            let hasSoniox = !(KeychainStore.get(account: "soniox") ?? "").isEmpty
            let hasAnyProvider = ProviderRegistry.all.contains {
                !(KeychainStore.get(account: $0.keychainAccount) ?? "").isEmpty
            }
            if hasSoniox && hasAnyProvider {
                self.onboarded = true
                UserDefaults.standard.set(true, forKey: Self.onboardedKey)
            }
        }
        refreshKeyAvailability()
    }

    func markOnboarded() {
        onboarded = true
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
    }

    func setUiLanguage(_ code: String) {
        guard ["system", "zh", "en"].contains(code) else { return }
        uiLanguage = code
        UserDefaults.standard.set(code, forKey: Self.uiLanguageKey)
        // iOS reads AppleLanguages at launch to pick the UI localization, so this
        // takes effect after the app is reopened.
        switch code {
        case "en": UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case "zh": UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        default:   UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    func setAppearance(_ value: String) {
        guard ["system", "light", "dark"].contains(value) else { return }
        appearance = value
        UserDefaults.standard.set(value, forKey: Self.appearanceKey)
    }

    var effectiveColorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    func setAutoCopy(_ enabled: Bool) {
        autoCopy = enabled
        UserDefaults.standard.set(enabled, forKey: Self.autoCopyKey)
    }

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    func showToast(_ message: String, duration: TimeInterval = 2.0) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run { self?.toast = nil }
        }
    }

    var effectiveLocale: Locale {
        switch uiLanguage {
        case "zh": return Locale(identifier: "zh-Hans")
        case "en": return Locale(identifier: "en")
        default:   return Locale.current
        }
    }

    // MARK: - Languages
    func setSelectedLanguages(_ langs: [String]) {
        let cleaned = langs.isEmpty ? ["zh", "en"] : langs
        selectedLanguages = cleaned
        UserDefaults.standard.set(cleaned, forKey: Self.languagesKey)
    }

    // MARK: - Prompts
    func setPromptSlot1(_ value: String) {
        promptSlot1 = value
        UserDefaults.standard.set(value, forKey: Self.promptSlot1Key)
    }

    func setPromptSlot2(_ value: String) {
        promptSlot2 = value
        UserDefaults.standard.set(value, forKey: Self.promptSlot2Key)
    }

    var activeProvider: CleanupProviderInfo? {
        ProviderRegistry.find(id: activeProviderId)
    }

    func setActiveProvider(_ id: String) {
        guard ProviderRegistry.find(id: id) != nil else { return }
        activeProviderId = id
        UserDefaults.standard.set(id, forKey: Self.activeProviderKey)
        refreshKeyAvailability()
    }

    func refreshKeyAvailability() {
        self.hasSonioxKey = !(KeychainStore.get(account: "soniox") ?? "").isEmpty
        if let provider = activeProvider {
            self.hasActiveProviderKey = !(KeychainStore.get(account: provider.keychainAccount) ?? "").isEmpty
        } else {
            self.hasActiveProviderKey = false
        }
    }

    var rawDisplay: String {
        if liveText.isEmpty { return finalText }
        if finalText.isEmpty { return liveText }
        return finalText + "\n\n" + liveText
    }

    var isBusy: Bool { recording || starting || stopping }

    // MARK: - Hotwords
    func addHotwords(from input: String) {
        let next = HotwordsStore.parse(input)
        guard !next.isEmpty else { return }
        var merged = hotwords
        for w in next where !merged.contains(w) { merged.append(w) }
        hotwords = merged
        HotwordsStore.save(hotwords)
    }

    func removeHotword(_ word: String) {
        hotwords.removeAll { $0 == word }
        HotwordsStore.save(hotwords)
    }

    // MARK: - Recording
    func toggleRecording() {
        if starting || stopping { return }
        if recording {
            Task { await self.stopRecording() }
        } else {
            Task { await self.startRecording() }
        }
    }

    func startRecording() async {
        if recording || starting || stopping { return }
        guard let key = KeychainStore.get(account: "soniox"), !key.isEmpty else {
            self.appError = AppError(message: String(localized: "未配置 Soniox API key。"))
            return
        }

        starting = true
        appError = nil
        liveText = ""
        receivedAnyText = false
        stoppedDueToError = false

        let recorder = MicRecorder()
        let granted = await recorder.requestPermission()
        guard granted else {
            appError = AppError(message: String(localized: "麦克风权限被拒绝。设置 → V2A → 允许麦克风。"))
            starting = false
            return
        }

        recorder.onInterruption = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.recording else { return }
                self.stoppedDueToError = true
                self.appError = AppError(message: String(localized: "录音被来电或其它 App 打断，已停止。"))
                await self.stopRecording()
            }
        }

        let snapshotHotwords = hotwords
        let snapshotLanguages = selectedLanguages
        let soniox = SonioxClient(
            apiKey: key,
            hotwords: snapshotHotwords,
            languageHints: snapshotLanguages,
            languageHintsStrict: !snapshotLanguages.isEmpty,
            onText: { [weak self] text, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !text.isEmpty { self.receivedAnyText = true }
                    self.liveText = text
                }
            },
            onFailure: { [weak self] appErr in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.stoppedDueToError = true
                    self.appError = appErr
                    await self.stopRecording()
                }
            }
        )

        do {
            try await soniox.start()
        } catch {
            self.appError = AppError(message: String(localized: "Soniox 连接失败：\(error.localizedDescription)"))
            starting = false
            return
        }

        do {
            try await recorder.start { [weak soniox] frame in
                soniox?.sendAudio(frame)
            }
        } catch {
            self.appError = AppError(message: String(localized: "麦克风失败：\(error.localizedDescription)"))
            await soniox.stop()
            starting = false
            return
        }

        self.recorder = recorder
        self.soniox = soniox
        starting = false
        recording = true
    }

    func stopRecording() async {
        if stopping { return }
        if !recording && recorder == nil && soniox == nil { return }

        stopping = true
        recording = false

        if let recorder = self.recorder {
            await recorder.stop()
            self.recorder = nil
        }
        if let soniox = self.soniox {
            await soniox.stop()
            self.soniox = nil
        }

        let session = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !session.isEmpty {
            finalText = finalText.isEmpty ? session : finalText + "\n\n" + session
        }
        liveText = ""
        stopping = false

        // If the whole session produced no transcript (and no error stopped it),
        // hint that nothing was heard.
        if !stoppedDueToError && !receivedAnyText && session.isEmpty {
            appError = AppError(message: String(localized: "没听到声音，检查麦克风或说话音量。"))
        }
        stoppedDueToError = false
    }

    // MARK: - AI Cleanup
    enum CleanupKind: String {
        case light, deep, custom1, custom2
    }

    func prompt(for kind: CleanupKind) -> String {
        switch kind {
        case .light:   return PromptDefaults.lightCanonical
        case .deep:    return PromptDefaults.deepCanonical
        case .custom1: return promptSlot1.isEmpty ? PromptDefaults.lightCanonical : promptSlot1
        case .custom2: return promptSlot2.isEmpty ? PromptDefaults.lightCanonical : promptSlot2
        }
    }

    func processWithAI(kind: CleanupKind = .light) {
        if isBusy { return }
        let providerId = activeProviderId
        guard let provider = ProviderRegistry.find(id: providerId) else { return }
        guard let key = KeychainStore.get(account: provider.keychainAccount), !key.isEmpty else { return }
        let source = rawDisplay
        guard !source.isEmpty, !processing else { return }

        let activePrompt = prompt(for: kind)
        let usedMode = kind.rawValue

        processing = true
        processedText = ""
        appError = nil

        processTask?.cancel()
        let task = Task { [weak self] in
            do {
                let req = CleanupRequest(
                    transcript: source,
                    systemPrompt: activePrompt,
                    apiKey: key,
                    model: nil,
                    onToken: { token in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            if Task.isCancelled { return }
                            self.processedText += token
                        }
                    }
                )
                let cleaned = try await ProviderRegistry.cleanup(req, providerId: providerId)
                await MainActor.run {
                    guard let self else { return }
                    if Task.isCancelled { return }
                    // Replace with trimmed final to clear any trailing whitespace.
                    if self.processedText != cleaned { self.processedText = cleaned }
                    self.recordSessionIfEnabled(
                        raw: source,
                        cleaned: cleaned,
                        providerId: providerId,
                        mode: usedMode
                    )
                    if self.autoCopy, !cleaned.isEmpty {
                        UIPasteboard.general.string = cleaned
                        self.showToast(String(localized: "已自动复制到剪贴板"))
                    }
                }
            } catch {
                if Task.isCancelled { return }
                if (error as? URLError)?.code == .cancelled { return }
                await MainActor.run {
                    guard let self else { return }
                    self.appError = FailureClassifier.provider(error, provider)
                }
            }
            await MainActor.run {
                self?.processing = false
            }
        }
        processTask = task
    }

    // MARK: - History
    var historyEnabled: Bool {
        get { HistoryStore.isEnabled() }
    }

    func setHistoryEnabled(_ enabled: Bool) {
        HistoryStore.setEnabled(enabled)
    }

    private func recordSessionIfEnabled(raw: String, cleaned: String, providerId: String, mode: String) {
        guard HistoryStore.isEnabled() else { return }
        let session = Session(
            id: UUID(),
            timestamp: Date(),
            raw: raw,
            cleaned: cleaned,
            providerId: providerId,
            mode: mode
        )
        HistoryStore.append(session)
    }

    func clearAll() {
        if isBusy { return }
        processTask?.cancel()
        processTask = nil
        processing = false
        finalText = ""
        liveText = ""
        processedText = ""
        appError = nil
    }

    // MARK: - Copy
    func copyRaw() {
        let text = rawDisplay
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        rawCopied = true
        rawCopiedTask?.cancel()
        rawCopiedTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { self?.rawCopied = false }
        }
    }

    func copyProcessed() {
        let text = processedText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        processedCopied = true
        processedCopiedTask?.cancel()
        processedCopiedTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { self?.processedCopied = false }
        }
    }
}
