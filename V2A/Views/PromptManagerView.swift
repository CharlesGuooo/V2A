import SwiftUI

struct PromptManagerView: View {
    @Bindable var state: AppState

    @State private var slot1Draft: String = ""
    @State private var slot2Draft: String = ""

    // Recording state — shared across both slots; only one can record at a time.
    @State private var recordingSlot: Int? = nil
    @State private var recordingStarting: Bool = false
    @State private var recordingStopping: Bool = false
    @State private var recordingError: String? = nil
    @State private var liveTranscript: String = ""
    @State private var baseTextBeforeRecord: String = ""
    @State private var recorder: MicRecorder? = nil
    @State private var soniox: SonioxClient? = nil

    @FocusState private var focusedSlot: Int?

    var body: some View {
        Form {
            builtinSection(
                title: "轻度整理",
                footer: "快速清理：删语气词、修标点、小幅通顺。",
                text: PromptDefaults.lightDisplay(for: displayLang)
            )
            builtinSection(
                title: "深度整理",
                footer: "结构化：识别改口只留最终意思、把分点整理成 bullet。",
                text: PromptDefaults.deepDisplay(for: displayLang)
            )
            slotSection(index: 1)
            slotSection(index: 2)
            if let err = recordingError {
                Section { Text(err).foregroundStyle(AppColor.error) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("告诉 AI 怎么整理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedSlot = nil }
            }
        }
        .onAppear {
            slot1Draft = state.promptSlot1
            slot2Draft = state.promptSlot2
        }
    }

    // MARK: - Built-in (read-only)

    private var displayLang: String {
        switch state.uiLanguage {
        case "zh": return "zh"
        case "en": return "en"
        default:   return Locale.current.language.languageCode?.identifier == "zh" ? "zh" : "en"
        }
    }

    @ViewBuilder
    private func builtinSection(title: LocalizedStringKey, footer: LocalizedStringKey, text: String) -> some View {
        Section {
            ScrollView {
                Text(text)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)

            Button {
                UIPasteboard.general.string = text
            } label: {
                Label("复制这段", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .font(.caption)
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }

    // MARK: - Editable slots

    @ViewBuilder
    private func slotSection(index: Int) -> some View {
        Section {
            TextEditor(text: editorBinding(for: index))
                .frame(minHeight: 140)
                .font(.system(size: 13))
                .focused($focusedSlot, equals: index)
                .disabled(recordingSlot == index)
                .opacity(recordingSlot == index ? 0.85 : 1.0)

            controlsRow(for: index)
                .font(.caption)
        } header: {
            Text("自定义 \(index)")
        } footer: {
            Text("在主页长按「轻度整理」或「深度整理」就能选用这一版。")
        }
    }

    @ViewBuilder
    private func controlsRow(for index: Int) -> some View {
        HStack(spacing: 18) {
            Button {
                toggleRecording(for: index)
            } label: {
                if recordingSlot == index {
                    if recordingStopping {
                        Label("停止中…", systemImage: "stop.circle")
                    } else {
                        Label("停止", systemImage: "stop.circle.fill")
                    }
                } else if recordingStarting && recordingSlot == nil {
                    Label("连接中…", systemImage: "mic")
                } else {
                    Label("录音输入", systemImage: "mic.fill")
                }
            }
            .buttonStyle(.borderless)
            .tint(recordingSlot == index ? .red : AppColor.accent)
            .disabled(otherSlotRecording(index) || recordingStarting || recordingStopping)

            Menu {
                Button("轻度整理") { fill(index: index, with: PromptDefaults.lightDisplay(for: displayLang)) }
                Button("深度整理") { fill(index: index, with: PromptDefaults.deepDisplay(for: displayLang)) }
            } label: {
                Label("填入模板", systemImage: "arrow.down.doc")
            }
            .buttonStyle(.borderless)
            .disabled(recordingSlot != nil)

            Spacer()

            Button(role: .destructive) {
                if index == 1 {
                    slot1Draft = ""
                    state.setPromptSlot1("")
                } else {
                    slot2Draft = ""
                    state.setPromptSlot2("")
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled((index == 1 ? slot1Draft : slot2Draft).isEmpty || recordingSlot != nil)
        }
    }

    private func otherSlotRecording(_ index: Int) -> Bool {
        if let r = recordingSlot { return r != index }
        return false
    }

    private func fill(index: Int, with text: String) {
        if index == 1 {
            slot1Draft = text
            state.setPromptSlot1(text)
        } else {
            slot2Draft = text
            state.setPromptSlot2(text)
        }
    }

    // MARK: - Editor binding

    private func editorBinding(for index: Int) -> Binding<String> {
        if recordingSlot == index {
            return Binding(
                get: { combinedTextDuringRecording() },
                set: { _ in /* read-only while recording */ }
            )
        }
        return Binding(
            get: { index == 1 ? slot1Draft : slot2Draft },
            set: { newValue in
                if index == 1 {
                    slot1Draft = newValue
                    state.setPromptSlot1(newValue)
                } else {
                    slot2Draft = newValue
                    state.setPromptSlot2(newValue)
                }
            }
        )
    }

    private func combinedTextDuringRecording() -> String {
        let live = liveTranscript.trimmingCharacters(in: .whitespaces)
        if live.isEmpty { return baseTextBeforeRecord }
        if baseTextBeforeRecord.isEmpty { return live }
        return baseTextBeforeRecord + " " + live
    }

    // MARK: - Recording

    private func toggleRecording(for index: Int) {
        if recordingSlot == index {
            Task { await stopRecording() }
        } else if recordingSlot == nil {
            Task { await startRecording(for: index) }
        }
    }

    @MainActor
    private func startRecording(for index: Int) async {
        guard recordingSlot == nil, !recordingStarting, !recordingStopping else { return }
        guard let key = KeychainStore.get(account: "soniox"), !key.isEmpty else {
            recordingError = String(localized: "未配置 Soniox key，去设置 → Soniox 那栏填一下。")
            return
        }
        focusedSlot = nil
        recordingStarting = true
        recordingError = nil
        liveTranscript = ""
        baseTextBeforeRecord = (index == 1 ? slot1Draft : slot2Draft)

        let rec = MicRecorder()
        let granted = await rec.requestPermission()
        guard granted else {
            recordingError = String(localized: "麦克风权限被拒绝。设置 → V2A → 允许麦克风。")
            recordingStarting = false
            return
        }

        let langs = state.selectedLanguages
        let hot = state.hotwords
        let sx = SonioxClient(
            apiKey: key,
            hotwords: hot,
            languageHints: langs,
            languageHintsStrict: !langs.isEmpty,
            onText: { text, _ in
                Task { @MainActor in self.liveTranscript = text }
            },
            onFailure: { appErr in
                Task { @MainActor in
                    self.recordingError = appErr.message
                    await self.stopRecording()
                }
            }
        )

        do {
            try await sx.start()
            try await rec.start { [weak sx] frame in
                sx?.sendAudio(frame)
            }
        } catch {
            recordingError = String(localized: "启动失败：\(error.localizedDescription)")
            await sx.stop()
            recordingStarting = false
            return
        }

        recorder = rec
        soniox = sx
        recordingStarting = false
        recordingSlot = index
    }

    @MainActor
    private func stopRecording() async {
        guard let index = recordingSlot else {
            // cleanup any partial state
            if let recorder { await recorder.stop(); self.recorder = nil }
            if let soniox { await soniox.stop(); self.soniox = nil }
            recordingStarting = false
            recordingStopping = false
            return
        }
        if recordingStopping { return }
        recordingStopping = true

        if let recorder { await recorder.stop(); self.recorder = nil }
        if let soniox { await soniox.stop(); self.soniox = nil }

        // Commit the combined text into the slot.
        let final = combinedTextDuringRecording()
        if index == 1 {
            slot1Draft = final
            state.setPromptSlot1(final)
        } else {
            slot2Draft = final
            state.setPromptSlot2(final)
        }

        liveTranscript = ""
        baseTextBeforeRecord = ""
        recordingSlot = nil
        recordingStopping = false
    }
}
