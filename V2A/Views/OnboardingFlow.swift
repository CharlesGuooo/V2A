import SwiftUI

struct OnboardingFlow: View {
    @Bindable var state: AppState
    let onComplete: () -> Void

    @State private var step: Int = 0
    @State private var sonioxKey: String = ""
    @State private var providerId: String = ProviderRegistry.defaultId
    @State private var providerKey: String = ""

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                welcomeStep.tag(0)
                sonioxStep.tag(1)
                providerStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .indexViewStyle(.page(backgroundDisplayMode: .never))

            stepDots
                .padding(.vertical, 12)

            HStack(spacing: 12) {
                if step > 0 {
                    Button("上一步") {
                        withAnimation { step -= 1 }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Spacer(minLength: 0)
                Button(step == totalSteps - 1 ? "完成，开始用" : "下一步") {
                    if step == totalSteps - 1 {
                        complete()
                    } else {
                        withAnimation { step += 1 }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(nextDisabled)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(AppColor.bg.ignoresSafeArea())
        .keyboardDoneToolbar()
        .onAppear {
            sonioxKey = KeychainStore.get(account: "soniox") ?? ""
            providerId = state.activeProviderId
            if let p = ProviderRegistry.find(id: providerId) {
                providerKey = KeychainStore.get(account: p.keychainAccount) ?? ""
            }
        }
        .onChange(of: providerId) { oldId, newId in
            if let oldP = ProviderRegistry.find(id: oldId) {
                KeychainStore.set(account: oldP.keychainAccount, value: providerKey)
            }
            if let newP = ProviderRegistry.find(id: newId) {
                providerKey = KeychainStore.get(account: newP.keychainAccount) ?? ""
            }
        }
    }

    // MARK: - Step indicator

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Circle()
                    .fill(i == step ? AppColor.accent : AppColor.border)
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("欢迎用 V2A")
                .font(.largeTitle.bold())
                .foregroundStyle(AppColor.accent)

            Text("说一段话，自动转成文字，AI 帮你整理通顺，一键复制给 ChatGPT 或其他 agent。打字慢的时候特别好用。")
                .font(.body)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                bullet("接下来要填两个 key：")
                bullet("· Soniox（把声音变文字）")
                bullet("· 一家 AI 服务商（整理文字，5 家任选其一）")
                bullet("两个 key 都从对应官网注册账号免费拿。")
            }

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Step 1: Soniox

    private var sonioxStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("第 1 步 · Soniox key")
                .font(.title2.bold())
                .foregroundStyle(AppColor.accent)

            Text("Soniox 负责把你说的话实时转成文字。")
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("把 Soniox API key 粘进来", text: $sonioxKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(AppColor.paneTint)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(AppColor.textPrimary)

            if let url = URL(string: "https://console.soniox.com/") {
                Link("还没有 key？打开 Soniox 注册 →", destination: url)
                    .font(.caption)
            }

            Text("拿 key 的步骤：注册账号 → 登录 → 左侧 API Keys → Create API Key → 复制。")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Step 2: AI Provider

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("第 2 步 · 选一家 AI")
                .font(.title2.bold())
                .foregroundStyle(AppColor.accent)

            Text("用谁来帮你整理文字。5 家任选一家，以后随时可以切换。")
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("AI 服务商", selection: $providerId) {
                ForEach(ProviderRegistry.all, id: \.id) { p in
                    Text(p.displayName).tag(p.id)
                }
            }
            .pickerStyle(.menu)
            .padding(12)
            .background(AppColor.paneTint)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            SecureField("把 \(currentProviderName) 的 API key 粘进来", text: $providerKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(AppColor.paneTint)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(AppColor.textPrimary)

            if let provider = ProviderRegistry.find(id: providerId),
               let url = URL(string: provider.apiKeyHelpURL) {
                Link("还没有 key？打开 \(provider.displayName) 注册 →", destination: url)
                    .font(.caption)
            }

            quickHintForProvider
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Computed

    private var currentProviderName: String {
        ProviderRegistry.find(id: providerId)?.displayName ?? "AI"
    }

    @ViewBuilder
    private var quickHintForProvider: some View {
        switch providerId {
        case "deepseek": Text("Deepseek 注册就送免费额度，对中文友好，推荐先用这家试试。")
        case "claude":   Text("Claude 质量最稳，但需要先在 Anthropic 充值才能用。")
        case "gemini":   Text("Google Gemini 每天有免费配额，量不大的话不用付钱。")
        case "openai":   Text("OpenAI 知名度最高，但要先充值才能用 API。")
        case "groq":     Text("Groq 速度飞快、免费额度大。适合刚开始试。")
        default:         EmptyView()
        }
    }

    private var nextDisabled: Bool {
        switch step {
        case 1: return sonioxKey.trimmingCharacters(in: .whitespaces).isEmpty
        case 2: return providerKey.trimmingCharacters(in: .whitespaces).isEmpty
        default: return false
        }
    }

    // MARK: - Complete

    private func complete() {
        KeychainStore.set(account: "soniox", value: sonioxKey.trimmingCharacters(in: .whitespaces))
        if let provider = ProviderRegistry.find(id: providerId) {
            KeychainStore.set(account: provider.keychainAccount, value: providerKey.trimmingCharacters(in: .whitespaces))
        }
        state.setActiveProvider(providerId)
        state.markOnboarded()
        onComplete()
    }

    // MARK: - Helpers

    private func bullet(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 14))
            .foregroundStyle(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
