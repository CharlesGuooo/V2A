import SwiftUI

// MARK: - Tokens

// Semantic color tokens. Each maps to a ColorSet in Assets.xcassets with
// light + dark variants. Direction A: zinc neutrals + indigo accent.
enum AppColor {
    static let bg            = Color("bg")
    static let surface       = Color("surface")
    static let paneTint      = Color("paneTint")
    static let textPrimary   = Color("textPrimary")
    static let textSecondary = Color("textSecondary")
    static let textTertiary  = Color("textTertiary")
    static let accent        = Color("accent")
    static let accentFg      = Color("accentFg")
    static let border        = Color("border")
    static let error         = Color("error")
    static let success       = Color("success")
}

// 4pt-based spacing scale used across all surfaces.
enum Spacing {
    static let xs:  CGFloat = 4
    static let s:   CGFloat = 8
    static let m:   CGFloat = 12
    static let l:   CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

// MARK: - Notice banner

// Notice (top error / config alert) banner. Two inits: localized
// (auto-translated via Localizable.xcstrings) and verbatim (for runtime
// strings like state.error where translation isn't applicable).
struct NoticeView: View {
    private let content: Text

    init(_ key: LocalizedStringKey) {
        self.content = Text(key)
    }

    init(plain text: String) {
        self.content = Text(verbatim: text)
    }

    var body: some View {
        content
            .font(.footnote)
            .foregroundStyle(AppColor.error)
            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.error.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Toast

// Transient toast banner shown at top via .overlay. Uses inverted-luminance
// surface (dark in light mode, light in dark mode) so it floats above content
// without competing with the accent.
struct ToastView: View {
    let text: String
    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppColor.bg)
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s + 2)
            .background(AppColor.textPrimary)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

// MARK: - Button styles

// Primary filled button. Used for the dominant CTA per screen.
struct PrimaryButtonStyle: ButtonStyle {
    var isOk: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppColor.accentFg)
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s + 2)
            .background(isOk ? AppColor.success : AppColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

// Emphasis ramp for the main-screen action buttons. Single accent hue at
// increasing strength, so it auto-adapts to light/dark via the accent token.
enum ButtonEmphasis {
    case faint   // copy-raw: lowest emphasis
    case medium  // light cleanup
    case solid   // deep cleanup: primary action
}

struct CleanupButtonStyle: ButtonStyle {
    var emphasis: ButtonEmphasis
    var big: Bool = false
    var okFeedback: Bool = false  // copy-raw turns success-green when copied

    func makeBody(configuration: Configuration) -> some View {
        let fg: Color
        let bg: Color
        switch emphasis {
        case .faint:  fg = AppColor.textSecondary; bg = AppColor.accent.opacity(0.10)
        case .medium: fg = AppColor.accent;        bg = AppColor.accent.opacity(0.22)
        case .solid:  fg = AppColor.accentFg;      bg = AppColor.accent
        }
        return configuration.label
            .font(.system(size: big ? 15 : 13, weight: .semibold))
            .foregroundStyle(okFeedback ? AppColor.accentFg : fg)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, big ? Spacing.s : Spacing.s + 2)
            .frame(maxWidth: .infinity)
            .background(okFeedback ? AppColor.success : bg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

// Error banner with an optional call-to-action (billing link / open Settings).
struct ErrorNoticeView: View {
    let error: AppError
    var onAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(verbatim: error.message)
                .font(.footnote)
                .foregroundStyle(AppColor.error)
                .fixedSize(horizontal: false, vertical: true)
            if let title = error.actionTitle {
                Button {
                    if let url = error.actionURL {
                        UIApplication.shared.open(url)
                    } else {
                        onAction?()
                    }
                } label: {
                    Text(verbatim: title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColor.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.error.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// Secondary text-only button. No bg, no border. Used for safe / cancel /
// alternative actions next to a Primary.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppColor.accent)
            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s + 2)
            .background(configuration.isPressed ? AppColor.accent.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Keyboard toolbar (Done button)

extension View {
    // Adds a "完成" (Done) button above the keyboard. Apply on the outermost
    // view of any surface that has text input.
    func keyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            }
        }
    }
}
