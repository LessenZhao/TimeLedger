import AppKit
import EvolutionCore
import EvolutionHubCore
import SwiftUI

/// An explicit hand-off surface: the app prepares immutable input, then the
/// user runs the displayed Skill command in Codex. No model runs in the Hub.
struct ChatConversationView: View {
    @EnvironmentObject private var store: ChatConversationHubStore
    @EnvironmentObject private var hubStore: HubStore
    @State private var usesDateRange = false
    @State private var rangeStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var rangeEnd = Date()

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            HSplitView {
                ChatConversationListView(store: store)
                    .frame(minWidth: 260, idealWidth: 330, maxWidth: 460)

                VSplitView {
                    ScrollView {
                        ChatConversationReviewView(store: store)
                    }
                    .frame(minHeight: 260, idealHeight: 420)
                    ChatConversationLedgerView(store: store)
                }
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            commandPanel
        }
        .navigationTitle("ChatGPT 对话")
        .onAppear {
            synchronizeDateRange()
            store.refresh(archiveRootPath: hubStore.settings.chatgptArchiveRoot)
        }
        .onChange(of: hubStore.settings.chatgptArchiveRoot) { _, path in
            store.refresh(archiveRootPath: path)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Toggle("按日期", isOn: $usesDateRange)
                .toggleStyle(.checkbox)
                .onChange(of: usesDateRange) { _, _ in synchronizeDateRange() }

            if usesDateRange {
                DatePicker("从", selection: $rangeStart, displayedComponents: .date)
                    .labelsHidden()
                    .onChange(of: rangeStart) { _, _ in synchronizeDateRange() }
                Text("至")
                    .foregroundStyle(.secondary)
                DatePicker("到", selection: $rangeEnd, displayedComponents: .date)
                    .labelsHidden()
                    .onChange(of: rangeEnd) { _, _ in synchronizeDateRange() }
            }

            Menu("处理状态") {
                ForEach(chatConversationStatuses, id: \.self) { status in
                    Toggle(status.title, isOn: statusBinding(status))
                }
            }

            Spacer()

            Button {
                store.refresh(archiveRootPath: hubStore.settings.chatgptArchiveRoot)
            } label: {
                Label("刷新归档", systemImage: "arrow.clockwise")
            }

            Button("生成处理任务") {
                do {
                    _ = try store.generateTask()
                } catch {
                    // Store keeps the actionable error for the visible status area.
                }
            }
            .disabled(store.selectedConversationIDs.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            if store.hasPendingCandidates {
                Text("候选已生成，待人工确认")
                    .font(.subheadline.weight(.semibold))
                Text("先在上方核对主题、会话片段、候选结论和引用材料；确认或拒绝后再生成下一项任务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let command = store.lastGeneratedCommand {
                Text("下一步：在 Codex 中显式执行")
                    .font(.subheadline.weight(.semibold))
                HStack {
                    Text(command)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button("复制命令") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(command, forType: .string)
                    }
                }
                Text("Skill 只会生成候选结果；不会自动写入正式账本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("选择有待处理消息的会话后生成不可变任务。日期和状态筛选只影响可见会话，不改变已选择的处理范围。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBinding(_ status: ChatConversationProcessingStatus) -> Binding<Bool> {
        Binding(
            get: { store.statusFilter.contains(status) },
            set: { isIncluded in
                if isIncluded {
                    store.statusFilter.insert(status)
                } else {
                    store.statusFilter.remove(status)
                }
            }
        )
    }

    private func synchronizeDateRange() {
        guard usesDateRange else {
            store.dateRange = nil
            return
        }
        let end = Calendar.current.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: rangeEnd
        ) ?? rangeEnd
        store.dateRange = ChatConversationDateRange(start: rangeStart, end: end)
    }
}

private let chatConversationStatuses: [ChatConversationProcessingStatus] = [
    .pending,
    .partiallyProcessed,
    .processed,
    .needsReexport,
]

private extension ChatConversationProcessingStatus {
    var title: String {
        switch self {
        case .pending:
            return "待处理"
        case .partiallyProcessed:
            return "部分处理"
        case .processed:
            return "已处理"
        case .needsReexport:
            return "需要重新导出"
        }
    }
}
