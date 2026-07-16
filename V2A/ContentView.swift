import SwiftUI

struct ContentView: View {
    @State private var state = AppState()
    @State private var actionRowWidth: CGFloat = 0

    var body: some View {
        @Bindable var state = state

        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if !state.hasSonioxKey {
                        NoticeView("未配置 Soniox API Key。点右上角齿轮添加。")
                    }
                    if state.hasSonioxKey && !state.hasActiveProviderKey {
                        let name = state.activeProvider?.displayName ?? "AI provider"
                        NoticeView("未配置 \(name) 的 API Key。AI 整理不可用，请去设置添加。")
                    }
                    if let err = state.appError {
                        ErrorNoticeView(error: err) { state.showSettings = true }
                    }

                    micRow

                    rawPane

                    processedPane
                }
                .padding(16)
                .frame(width: geo.size.width, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AppColor.bg.ignoresSafeArea())
        .preferredColorScheme(state.effectiveColorScheme)
        .environment(\.locale, state.effectiveLocale)
        .keyboardDoneToolbar()
        .overlay(alignment: .top) {
            if let toast = state.toast {
                ToastView(text: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.toast)
        .sheet(isPresented: $state.showSettings) {
            SettingsSheet(state: state)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !state.onboarded },
            set: { _ in /* dismissed via OnboardingFlow.onComplete */ }
        )) {
            OnboardingFlow(state: state) {
                state.refreshKeyAvailability()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("V2A · 语音 → 文字 → AI 整理")
                    .font(.headline)
                    .foregroundStyle(AppColor.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("说一段，停一下，AI 整理后复制给 agent")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                state.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var micRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                RecordButton(state: state)
                Spacer(minLength: 0)
                Button("清空全部") { state.clearAll() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(state.isBusy ||
                              (state.finalText.isEmpty && state.liveText.isEmpty && state.processedText.isEmpty))
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: LocalizedStringKey {
        if state.starting { return "正在连接 Soniox…" }
        if state.stopping { return "正在保存…" }
        if state.recording { return "录音中…" }
        return state.hasSonioxKey ? "点按钮开始" : "需要先配置 API Key"
    }

    @ViewBuilder
    private var rawPane: some View {
        let rawBinding = Binding<String>(
            get: { state.rawDisplay },
            set: { newValue in
                if !state.isBusy {
                    state.finalText = newValue
                    state.liveText = ""
                }
            }
        )
        VStack(alignment: .leading, spacing: 8) {
            TranscriptPaneView(
                title: "原始转录",
                text: rawBinding,
                isReadonly: state.isBusy,
                placeholder: "转录的文字会出现在这里。停止后可编辑。"
            )
            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Narrow low-key copy-raw on the left; the two big cleanup buttons (the real
    // primary actions) stacked on the right.
    @ViewBuilder
    private var actionRow: some View {
        let spacing: CGFloat = 8
        let usable = max(actionRowWidth - spacing, 0)
        let leftW = usable * 0.32
        let rightW = usable * 0.68

        HStack(spacing: spacing) {
            Button {
                state.copyRaw()
            } label: {
                Text(state.rawCopied ? "已复制 ✓" : "复制原文")
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(CleanupButtonStyle(emphasis: .faint, big: false, okFeedback: state.rawCopied))
            .disabled(state.rawDisplay.isEmpty)
            .frame(width: leftW > 0 ? leftW : nil)

            VStack(spacing: 8) {
                cleanupButton(title: "轻度整理", kind: .light, emphasis: .medium)
                cleanupButton(title: "深度整理", kind: .deep, emphasis: .solid)
            }
            .frame(width: rightW > 0 ? rightW : nil)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { actionRowWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in actionRowWidth = w }
            }
        )
    }

    // One big cleanup button. Long-press reveals custom slots the user has filled.
    @ViewBuilder
    private func cleanupButton(title: LocalizedStringKey, kind: AppState.CleanupKind, emphasis: ButtonEmphasis) -> some View {
        let disabled = state.rawDisplay.isEmpty || state.processing || !state.hasActiveProviderKey || state.isBusy
        Button {
            state.processWithAI(kind: kind)
        } label: {
            Group {
                if state.processing {
                    ProgressView().controlSize(.mini)
                        .tint(emphasis == .solid ? AppColor.accentFg : AppColor.accent)
                } else {
                    Text(title).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(CleanupButtonStyle(emphasis: emphasis, big: true))
        .disabled(disabled)
        .contextMenu {
            if !state.promptSlot1.isEmpty {
                Button("自定义 1") { state.processWithAI(kind: .custom1) }
            }
            if !state.promptSlot2.isEmpty {
                Button("自定义 2") { state.processWithAI(kind: .custom2) }
            }
        }
    }

    @ViewBuilder
    private var processedPane: some View {
        let processedBinding = Binding<String>(
            get: { state.processedText },
            set: { state.processedText = $0 }
        )
        VStack(alignment: .leading, spacing: 8) {
            TranscriptPaneView(
                title: "AI 整理后",
                text: processedBinding,
                isReadonly: false,
                placeholder: state.hasActiveProviderKey
                    ? "AI 整理后的文本会出现在这里。"
                    : "未配置 AI provider API key — AI 整理不可用。"
            )
            HStack(spacing: 8) {
                Button {
                    state.copyProcessed()
                } label: {
                    Text(state.processedCopied ? "已复制 ✓" : "复制整理后")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CleanupButtonStyle(emphasis: .solid, big: true, okFeedback: state.processedCopied))
                .disabled(state.processedText.isEmpty)

                if !state.processedText.isEmpty {
                    ShareLink(item: state.processedText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColor.accentFg)
                            .frame(width: 44, height: 36)
                            .background(AppColor.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RecordButton: View {
    let state: AppState
    @State private var dotOpacity: Double = 1.0

    var body: some View {
        Button {
            state.toggleRecording()
        } label: {
            HStack(spacing: 8) {
                if state.starting || state.stopping {
                    ProgressView().controlSize(.mini).tint(AppColor.accent)
                    Text(state.starting ? "连接中…" : "停止中…")
                } else if state.recording {
                    Circle()
                        .fill(AppColor.accent)
                        .frame(width: 8, height: 8)
                        .opacity(dotOpacity)
                    Text("录音中")
                } else {
                    Circle()
                        .fill(AppColor.accent)
                        .frame(width: 8, height: 8)
                    Text("开始录音")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppColor.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.m)
            .frame(minHeight: 44)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!state.hasSonioxKey || state.starting || state.stopping)
        .onChange(of: state.recording) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    dotOpacity = 0.4
                }
            } else {
                withAnimation { dotOpacity = 1.0 }
            }
        }
    }
}
