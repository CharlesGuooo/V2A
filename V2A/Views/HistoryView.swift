import SwiftUI

struct HistoryView: View {
    @State private var sessions: [Session] = []
    @State private var showClearAlert: Bool = false

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sessions) { session in
                        NavigationLink {
                            HistoryDetailView(session: session)
                        } label: {
                            row(session)
                        }
                    }
                    .onDelete { indices in
                        for idx in indices {
                            HistoryStore.remove(id: sessions[idx].id)
                        }
                        sessions = HistoryStore.load()
                    }
                }
            }
        }
        .navigationTitle("转录历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !sessions.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空全部", role: .destructive) {
                        showClearAlert = true
                    }
                }
            }
        }
        .alert("清空全部历史？", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                HistoryStore.clearAll()
                sessions = []
            }
        } message: {
            Text("这个操作不能撤销。")
        }
        .onAppear {
            sessions = HistoryStore.load()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("还没有历史记录")
                .foregroundStyle(.secondary)
            Text("AI 整理完成后会自动保存最近 20 条到这里。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.cleaned.isEmpty ? session.raw : session.cleaned)
                .font(.system(size: 14))
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(session.timestamp, style: .date)
                Text(verbatim: "·")
                Text(session.timestamp, style: .time)
                Text(verbatim: "·")
                Text(providerLabel(session.providerId))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func providerLabel(_ id: String) -> String {
        ProviderRegistry.find(id: id)?.displayName ?? id
    }
}

struct HistoryDetailView: View {
    let session: Session
    @State private var copiedRaw = false
    @State private var copiedCleaned = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metaSection
                paneSection(title: "原始转录", text: session.raw, copied: $copiedRaw, isCleaned: false)
                paneSection(title: "AI 整理后", text: session.cleaned, copied: $copiedCleaned, isCleaned: true)
            }
            .padding(16)
        }
        .background(AppColor.bg.ignoresSafeArea())
        .navigationTitle("历史详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.timestamp, style: .date)
                Text(session.timestamp, style: .time)
            }
            .font(.caption)
            .foregroundStyle(AppColor.textSecondary)

            Text(ProviderRegistry.find(id: session.providerId)?.displayName ?? session.providerId)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func paneSection(title: LocalizedStringKey, text: String, copied: Binding<Bool>, isCleaned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppColor.accent)
                .textCase(.uppercase)
                .tracking(1)

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(AppColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)

            Button {
                UIPasteboard.general.string = text
                copied.wrappedValue = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await MainActor.run { copied.wrappedValue = false }
                }
            } label: {
                Text(copied.wrappedValue ? "已复制 ✓" : (isCleaned ? "复制整理后" : "复制原文"))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(isOk: copied.wrappedValue))
            .disabled(text.isEmpty)
        }
    }
}
