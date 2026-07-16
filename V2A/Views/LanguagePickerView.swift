import SwiftUI

struct LanguagePickerView: View {
    @Bindable var state: AppState

    // Subset of Soniox-supported languages — the 15 most common.
    // Codes follow BCP-47 / ISO 639-1; Soniox accepts the short form.
    private static let languages: [(code: String, label: String)] = [
        ("zh", "中文（普通话）"),
        ("en", "English"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("es", "Español"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("pt", "Português"),
        ("ru", "Русский"),
        ("it", "Italiano"),
        ("nl", "Nederlands"),
        ("pl", "Polski"),
        ("tr", "Türkçe"),
        ("ar", "العربية"),
        ("hi", "हिन्दी"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(Self.languages, id: \.code) { lang in
                    Toggle(isOn: binding(for: lang.code)) {
                        HStack {
                            Text(lang.label)
                            Spacer()
                            Text(lang.code)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("启用的语言")
            } footer: {
                Text("勾选你会说的语言。勾得越多越容易误判（比如把中文听成日文）。至少保留一个；默认中 + 英。")
            }
        }
        .navigationTitle("Soniox 语言")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for code: String) -> Binding<Bool> {
        Binding(
            get: { state.selectedLanguages.contains(code) },
            set: { isOn in
                var next = state.selectedLanguages
                if isOn {
                    if !next.contains(code) { next.append(code) }
                } else {
                    next.removeAll { $0 == code }
                }
                state.setSelectedLanguages(next)
            }
        )
    }
}
