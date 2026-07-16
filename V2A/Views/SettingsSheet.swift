import SwiftUI

struct SettingsSheet: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var sonioxKey: String = ""
    @State private var providerKey: String = ""
    @State private var selectedProviderId: String = ProviderRegistry.defaultId
    @State private var hotwordInput: String = ""
    @State private var showLanguageRestart = false

    var body: some View {
        NavigationStack {
            Form {
                aiSection
                promptSection
                sonioxSection
                hotwordsSection
                generalSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear { loadCurrentState() }
            .onChange(of: selectedProviderId) { oldId, newId in
                // Persist what's typed before swapping the visible key.
                if let old = ProviderRegistry.find(id: oldId) {
                    KeychainStore.set(account: old.keychainAccount, value: providerKey)
                }
                if let new = ProviderRegistry.find(id: newId) {
                    providerKey = KeychainStore.get(account: new.keychainAccount) ?? ""
                }
            }
            .keyboardDoneToolbar()
            .alert("重开 App 生效", isPresented: $showLanguageRestart) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("界面语言已切换，完全关闭并重新打开 V2A 后生效。")
            }
        }
    }

    // MARK: - AI provider

    private var aiSection: some View {
        Section {
            Picker("Provider", selection: $selectedProviderId) {
                ForEach(ProviderRegistry.all, id: \.id) { p in
                    Text(p.displayName).tag(p.id)
                }
            }
            SecureField("API Key", text: $providerKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if let provider = ProviderRegistry.find(id: selectedProviderId),
               let url = URL(string: provider.apiKeyHelpURL) {
                Link("去 \(provider.displayName) 网站拿 key →", destination: url)
                    .font(.caption)
            }
        } header: {
            Text("AI 整理（必需）")
        } footer: {
            Text("选一家 provider 给你的语音转录做后期清理。每家 key 独立存储，可随时切换。")
        }
    }

    // MARK: - Prompt

    private var promptSection: some View {
        Section {
            NavigationLink {
                PromptManagerView(state: state)
            } label: {
                Text("告诉 AI 怎么整理")
            }
        } header: {
            Text("整理风格")
        } footer: {
            Text("看轻度 / 深度整理的规则，或者自己写一两个自定义版本（主页长按整理按钮选用）。")
        }
    }

    // MARK: - Soniox

    private var sonioxSection: some View {
        Section {
            SecureField("Soniox API Key", text: $sonioxKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            NavigationLink {
                LanguagePickerView(state: state)
            } label: {
                HStack {
                    Text("启用的语言")
                    Spacer()
                    Text(state.selectedLanguages.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let url = URL(string: "https://console.soniox.com/") {
                Link("去 Soniox 网站拿 key →", destination: url)
                    .font(.caption)
            }
        } header: {
            Text("Soniox 实时转录（必需）")
        } footer: {
            Text("用来把你说的话实时转成文字。从 console.soniox.com 拿 key。")
        }
    }

    // MARK: - Hotwords

    private var hotwordsSection: some View {
        Section {
            HStack {
                TextField("添加热词", text: $hotwordInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit(commitHotword)
                Button("加入") { commitHotword() }
                    .disabled(hotwordInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if state.hotwords.isEmpty {
                Text("把人名、专有名词、缩写加进来，Soniox 识别会更准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.hotwords, id: \.self) { word in
                    Text(word)
                }
                .onDelete { indices in
                    for idx in indices {
                        state.removeHotword(state.hotwords[idx])
                    }
                }
            }
        } header: {
            Text("热词")
        } footer: {
            Text("逗号或回车分隔多个；左滑删除单个。")
        }
    }

    // MARK: - General

    @State private var historyEnabled: Bool = HistoryStore.isEnabled()

    private var generalSection: some View {
        Section {
            Picker("外观", selection: Binding(
                get: { state.appearance },
                set: { state.setAppearance($0) }
            )) {
                Text("跟随系统").tag("system")
                Text("亮").tag("light")
                Text("暗").tag("dark")
            }
            Picker("界面语言", selection: Binding(
                get: { state.uiLanguage },
                set: { newValue in
                    let changed = newValue != state.uiLanguage
                    state.setUiLanguage(newValue)
                    if changed { showLanguageRestart = true }
                }
            )) {
                Text("跟随系统").tag("system")
                Text("中文").tag("zh")
                Text("English").tag("en")
            }
            Toggle("整理完自动复制", isOn: Binding(
                get: { state.autoCopy },
                set: { state.setAutoCopy($0) }
            ))
            Toggle("记录转录历史", isOn: $historyEnabled)
                .onChange(of: historyEnabled) { _, newValue in
                    state.setHistoryEnabled(newValue)
                }
            NavigationLink {
                HistoryView()
            } label: {
                HStack {
                    Text("转录历史")
                    Spacer()
                    Text("最近 \(HistoryStore.cap) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("通用")
        } footer: {
            Text("「自动复制」打开后，AI 整理一完成就把结果写到剪贴板，省一步操作。历史保存在本机。")
        }
    }

    // MARK: - Help / About

    private var aboutSection: some View {
        Section {
            NavigationLink {
                FAQView()
            } label: {
                Label("怎么拿 API key", systemImage: "questionmark.circle")
            }
            NavigationLink {
                AboutView()
            } label: {
                Label("关于 / 隐私", systemImage: "info.circle")
            }
        } header: {
            Text("帮助")
        }
    }

    // MARK: - Helpers

    private func commitHotword() {
        let trimmed = hotwordInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        state.addHotwords(from: hotwordInput)
        hotwordInput = ""
    }

    private func loadCurrentState() {
        selectedProviderId = state.activeProviderId
        sonioxKey = KeychainStore.get(account: "soniox") ?? ""
        if let provider = ProviderRegistry.find(id: selectedProviderId) {
            providerKey = KeychainStore.get(account: provider.keychainAccount) ?? ""
        }
    }

    private func save() {
        KeychainStore.set(account: "soniox", value: sonioxKey)
        if let provider = ProviderRegistry.find(id: selectedProviderId) {
            KeychainStore.set(account: provider.keychainAccount, value: providerKey)
        }
        state.setActiveProvider(selectedProviderId)
    }
}
