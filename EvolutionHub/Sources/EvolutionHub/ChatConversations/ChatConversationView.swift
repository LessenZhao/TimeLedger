import AppKit
import EvolutionCore
import EvolutionHubCore
import SwiftUI

/// Workspace order is product priority: 会话 → 待确认 → 正式库.
private enum ChatWorkspaceTab: String, CaseIterable, Identifiable {
    case sessions = "会话"
    case review = "待确认"
    case library = "正式库"

    var id: Self { self }
}

/// Explicit hand-off surface for ChatGPT prep materials.
///
/// - 会话: left = imported history; center = read source
/// - 待确认: candidate review stage
/// - 正式库: material catalog + read/edit/source/excerpt
/// Imported conversation list appears only in 会话, not as a permanent far-left column.
struct ChatConversationView: View {
    @EnvironmentObject private var store: ChatConversationHubStore
    @EnvironmentObject private var hubStore: HubStore
    @State private var usesDateRange = false
    @State private var rangeStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var rangeEnd = Date()
    @State private var workspaceTab: ChatWorkspaceTab = .sessions
    @State private var stageMode: ChatStageMode = .source
    @State private var focusedConversationID: String?

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            workspaceHeader
            Divider()
            Group {
                switch workspaceTab {
                case .sessions:
                    sessionsWorkspace
                case .review:
                    ChatConversationReviewView(
                        store: store,
                        stageMode: $stageMode
                    )
                case .library:
                    ChatConversationLedgerView(
                        store: store,
                        stageMode: $stageMode
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            commandPanel
        }
        .navigationTitle("湖南省直遴选备考库")
        .onAppear {
            synchronizeDateRange()
            store.refresh(archiveRootPath: hubStore.settings.chatgptArchiveRoot)
            if store.hasPendingCandidates {
                workspaceTab = .review
            } else {
                workspaceTab = .sessions
                stageMode = .source
            }
        }
        .onChange(of: hubStore.settings.chatgptArchiveRoot) { _, path in
            store.refresh(archiveRootPath: path)
        }
        .onChange(of: store.hasPendingCandidates) { _, hasPending in
            if hasPending {
                workspaceTab = .review
            }
        }
        .onChange(of: workspaceTab) { _, tab in
            switch tab {
            case .sessions:
                stageMode = .source
            case .review:
                if stageMode == .edit {
                    stageMode = .read
                }
            case .library:
                if stageMode != .source && stageMode != .excerpt {
                    stageMode = .read
                }
            }
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            Picker("工作区", selection: $workspaceTab) {
                ForEach(ChatWorkspaceTab.allCases) { tab in
                    if tab == .review, !store.candidates.isEmpty {
                        Text("\(tab.rawValue) \(store.candidates.count)").tag(tab)
                    } else {
                        Text(tab.rawValue).tag(tab)
                    }
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Group {
                switch workspaceTab {
                case .sessions:
                    Text("点选导入会话阅读原文；勾选后可生成处理任务。")
                case .review:
                    Text("核对候选后确认写入；不会自动应用。")
                case .library:
                    Text("正式材料：左栏目录，中栏阅读/编辑/原文/摘录。")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var sessionsWorkspace: some View {
        HSplitView {
            ChatConversationListView(
                store: store,
                focusedConversationID: $focusedConversationID,
                onOpenConversation: { id in
                    focusedConversationID = id
                    stageMode = .source
                }
            )
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)

            sessionStage
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var sessionStage: some View {
        if let focusedConversationID,
           let conversation = store.conversation(id: focusedConversationID) {
            let references = store.messageReferences(forConversationID: focusedConversationID)
            let segmentID = store.preferredFormalSegmentID(forConversationID: focusedConversationID)
            let destination: ChatConversationSourceDestination = {
                if let segmentID {
                    return .formal(segmentID: segmentID)
                }
                return .readOnly
            }()

            VStack(spacing: 0) {
                ChatStageHeader(
                    mode: $stageMode,
                    title: conversation.title,
                    subtitle: segmentID == nil
                        ? "只读预览 · 确认进库并产生片段后可摘录"
                        : "可摘录到正式库",
                    enabledModes: segmentID == nil ? [.source] : [.source, .excerpt]
                )
                Divider()
                ChatConversationSourceStage(
                    store: store,
                    references: references,
                    purpose: .coverage,
                    destination: destination,
                    allowsExcerpt: segmentID != nil
                )
            }
        } else {
            ContentUnavailableView(
                "选择导入会话",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("左侧是导入的历史会话。点一项即可阅读全文；勾选多项后可生成处理任务。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
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
                Text("切换到「待确认」核对片段、候选正文和引用来源；确认或拒绝后再生成下一项任务。")
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
                Text("工作区顺序：会话 → 待确认 → 正式库。导入会话只在「会话」里出现；勾选后生成任务，点标题阅读原文。")
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
