import SwiftUI

struct TranscriptPaneView: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let isReadonly: Bool
    let placeholder: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1)
                Spacer()
                Text("\(text.count) 字")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColor.textTertiary)
                        .padding(.horizontal, 14).padding(.vertical, 16)
                }
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .padding(8)
                    .disabled(isReadonly)
                    .foregroundStyle(AppColor.textPrimary)
                    .font(.system(size: 15))
                    .lineSpacing(4)
            }
            .frame(minHeight: 200)
            .background(isReadonly ? AppColor.paneTint : AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
