import SwiftUI

struct AboutView: View {
    var body: some View {
        Form {
            appSection
            privacySection
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text(versionString).foregroundStyle(.secondary)
            }
            HStack {
                Text("Bundle ID")
                Spacer()
                Text(Bundle.main.bundleIdentifier ?? "?")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } header: {
            Text("V2A")
        } footer: {
            Text("说一段话 → 实时转成文字 → AI 整理通顺 → 复制给 ChatGPT / Claude / 任何 Agent。打字慢的时候用。")
        }
    }

    private var privacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                bullet("你填进去的 API key 只存在这台手机的 keychain 里，我们看不到，也不会上传。")
                bullet("录音通过你自己的 Soniox key 发到 Soniox，整理通过你自己的 AI 厂商 key 发到对应厂商。中间不经过任何我们的服务器。")
                bullet("热词、自定义整理风格、设置项都只存在本机。")
                bullet("我们不收集任何使用数据、不做分析、不做广告。")
                bullet("App 完全断网时除了录音之外都不能用——所有功能都靠你自己的 key 调用第三方 API。")
            }
            .padding(.vertical, 6)
        } header: {
            Text("隐私")
        } footer: {
            Text("如果换设备或重装，记得在新设备重新填一次 key。")
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: "•").foregroundStyle(AppColor.accent)
            Text(LocalizedStringKey(text)).font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
