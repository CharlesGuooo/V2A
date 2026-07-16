import SwiftUI

struct FAQView: View {
    var body: some View {
        Form {
            sonioxSection
            ForEach(ProviderRegistry.all, id: \.id) { provider in
                providerSection(provider)
            }
        }
        .navigationTitle("怎么拿 API key")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sonioxSection: some View {
        Section {
            stepsView(Self.sonioxSteps)
            if let url = URL(string: "https://console.soniox.com/") {
                Link("打开 Soniox 控制台 →", destination: url)
                    .font(.caption)
            }
        } header: {
            Text("Soniox · 把语音转成文字（必需）")
        }
    }

    private func providerSection(_ p: CleanupProviderInfo) -> some View {
        Section {
            stepsView(Self.stepsFor(providerId: p.id))
            if let url = URL(string: p.apiKeyHelpURL) {
                Link("打开 \(p.displayName) 控制台 →", destination: url)
                    .font(.caption)
            }
        } header: {
            Text("\(p.displayName) · 帮你整理文字")
        } footer: {
            footnoteView(for: p.id)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func footnoteView(for providerId: String) -> some View {
        switch providerId {
        case "deepseek": Text("新账号有免费额度，先用着不要钱。")
        case "gemini":   Text("每天有免费配额，量不大的话不用付钱。")
        case "groq":     Text("免费额度大、速度飞快。适合刚开始试。")
        case "claude":   Text("质量最稳，但要先充钱才能用。")
        case "openai":   Text("知名度最高，但价格不便宜，要先充值。")
        default:         EmptyView()
        }
    }

    private func stepsView(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, text in
                HStack(alignment: .top, spacing: 8) {
                    Text(verbatim: "\(idx + 1).")
                        .font(.caption.bold())
                        .frame(width: 20, alignment: .leading)
                        .foregroundStyle(AppColor.accent)
                    Text(LocalizedStringKey(text))
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Step content

    private static let sonioxSteps: [String] = [
        "打开 console.soniox.com，用邮箱注册一个账号",
        "登录后左边菜单找到「API Keys」",
        "点「Create API Key」生成一个新 key",
        "复制出来的那串字符，回到 V2A 设置粘到 Soniox 那栏",
    ]

    private static func stepsFor(providerId: String) -> [String] {
        switch providerId {
        case "deepseek":
            return [
                "打开 platform.deepseek.com 注册账号（手机号或邮箱都行）",
                "登录后点右上角头像 → API Keys",
                "点「Create new API key」起个名字，生成 key",
                "复制 sk- 开头的字符串，回到 V2A 设置粘进 AI 整理那栏",
            ]
        case "claude":
            return [
                "打开 console.anthropic.com 注册账号",
                "充值至少 5 美元（Anthropic 要求先充值才能用 API）",
                "左边菜单 API Keys → 点「Create Key」",
                "复制 sk-ant- 开头的 key，回到 V2A 设置粘进去",
            ]
        case "gemini":
            return [
                "打开 aistudio.google.com，用 Google 账号登录",
                "左下角点「Get API key」",
                "点「Create API key」，选一个 Google Cloud 项目（没有就让它新建）",
                "复制 AIza 开头的 key，回到 V2A 设置粘进去",
            ]
        case "openai":
            return [
                "打开 platform.openai.com 注册账号",
                "必须先充值（最少 5 美元）才能用 API",
                "右上角设置 → API keys → Create new secret key",
                "复制 sk- 开头的 key（关掉就看不到了，记得马上粘到 V2A）",
            ]
        case "groq":
            return [
                "打开 console.groq.com，可以直接用 Google 或 GitHub 登录",
                "左边菜单点「API Keys」",
                "点「Create API Key」起个名字",
                "复制 gsk_ 开头的 key，回到 V2A 设置粘进去",
            ]
        default:
            return []
        }
    }

}
