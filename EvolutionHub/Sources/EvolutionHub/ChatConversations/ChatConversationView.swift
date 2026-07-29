import AppKit
import EvolutionCore
import EvolutionHubCore
import SwiftUI

/// Workspace order is product priority: 会话 → 待确认 → 正式库.
enum ChatWorkspaceTab: String, CaseIterable, Identifiable {
    case sessions = "会话"
    case review = "待确认"
    case library = "正式库"
    case notes = "笔记库"

    var id: Self { self }
}

/// Chat prep surface.
///
/// Shell contract: module chrome lives in the app's single top bar (right of the sidebar seam).
/// Content columns no longer host a second global header row for 会话.
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
            Group {
                switch workspaceTab {
                case .sessions:
                    sessionsWorkspace
                case .review:
                    ChatConversationReviewView(
                        store: store,
                        stageMode: $stageMode,
                        leftHeaderPrefix: { EmptyView() }
                    )
                case .library:
                    ChatConversationLedgerView(
                        store: store,
                        stageMode: $stageMode,
                        leftHeaderPrefix: { EmptyView() },
                        rightHeaderTrailing: { EmptyView() }
                    )
                case .notes:
                    ChatReadingNotesLibraryView(store: store) { target in
                        focusNoteTarget(target)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsCommandPanel {
                Divider()
                commandPanel
            }
        }
        .background(
            HubChromeInstaller(dependency: chromeDependency) {
                moduleChrome
            }
        )
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
                if stageMode != .source {
                    stageMode = .read
                }
            case .notes:
                break
            }
        }
    }

    // MARK: - Shell module chrome (single top-bar row)

    private var chromeDependency: String {
        let focusedTitle: String = {
            guard let focusedConversationID,
                  let conversation = store.conversation(id: focusedConversationID) else {
                return ""
            }
            return conversation.title
        }()
        let segmentFlag: String = {
            guard let focusedConversationID else { return "0" }
            return store.preferredFormalSegmentID(forConversationID: focusedConversationID) == nil ? "0" : "1"
        }()
        return [
            workspaceTab.rawValue,
            stageMode.rawValue,
            focusedConversationID ?? "",
            focusedTitle,
            segmentFlag,
            String(store.visibleConversations.count),
            String(store.showsOnlyStarredConversations),
            String(usesDateRange),
            String(store.selectedConversationIDs.count),
            String(store.candidates.count),
            store.statusFilter.map(\.rawValue).sorted().joined(separator: ","),
            rangeStart.timeIntervalSince1970.description,
            rangeEnd.timeIntervalSince1970.description
        ].joined(separator: "|")
    }

    @ViewBuilder
    private var moduleChrome: some View {
        HStack(spacing: 8) {
            workspaceTabs

            switch workspaceTab {
            case .sessions:
                sessionFilterAccessory
                Spacer(minLength: 4)
                Toggle(isOn: $store.showsOnlyStarredConversations) {
                    Image(systemName: store.showsOnlyStarredConversations ? "star.fill" : "star")
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(store.showsOnlyStarredConversations ? "显示全部会话" : "仅显示星标会话")
                Text("\(store.visibleConversations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                shellSeparator

                sessionStageChrome
            case .review:
                Text(store.candidates.isEmpty ? "暂无候选" : "候选 \(store.candidates.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                globalActions
            case .library:
                Spacer(minLength: 8)
                globalActions
            case .notes:
                Text("笔记 \(store.allNotes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 8)
                globalActions
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var shellSeparator: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var sessionStageChrome: some View {
        if let focusedConversationID,
           let conversation = store.conversation(id: focusedConversationID) {
            let references = store.messageReferences(forConversationID: focusedConversationID)
            let segmentID = store.preferredFormalSegmentID(forConversationID: focusedConversationID)
            let summary = store.sourceSummary(for: references)
            Text(conversation.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            if segmentID == nil {
                Text("只读")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(summary.messageCount) 消息 · \(summary.turnCount) 轮")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .monospacedDigit()
            SourceCatalogToggle()
            globalActions
        } else {
            Text("选择左侧会话")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            globalActions
        }
    }

    private func modeBinding(enabled: Set<ChatStageMode>) -> Binding<ChatStageMode> {
        let fallback = ChatStageMode.displayOrder.first(where: { enabled.contains($0) }) ?? .source
        return Binding(
            get: { enabled.contains(stageMode) ? stageMode : fallback },
            set: { newValue in
                stageMode = enabled.contains(newValue) ? newValue : fallback
            }
        )
    }

    // MARK: - Sessions content (no column header row)

    private var sessionsWorkspace: some View {
        HSplitView {
            ChatConversationListView(
                store: store,
                focusedConversationID: $focusedConversationID,
                onOpenConversation: { id in
                    focusedConversationID = id
                    stageMode = .source
                },
                showsHeader: false
            )
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)

            sessionStageBody
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var sessionStageBody: some View {
        if let focusedConversationID,
           let _ = store.conversation(id: focusedConversationID) {
            let references = store.messageReferences(forConversationID: focusedConversationID)
            let segmentID = store.preferredFormalSegmentID(forConversationID: focusedConversationID)
            let destination: ChatConversationSourceDestination = {
                if let segmentID {
                    return .formal(segmentID: segmentID)
                }
                return .readOnly
            }()

            ChatConversationSourceStage(
                store: store,
                references: references,
                purpose: .coverage,
                destination: destination,
                allowsNotes: true,
                showsToolbar: false
            )
        } else {
            ContentUnavailableView(
                "选择导入会话",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("左侧点选阅读全文；勾选后可生成处理任务。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    // MARK: - Shared chrome pieces

    private var workspaceTabs: some View {
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
        .labelsHidden()
        .frame(maxWidth: 240)
        .controlSize(.small)
        .help(workspaceHelp)
    }

    @ViewBuilder
    private var globalActions: some View {
        Button {
            store.refresh(archiveRootPath: hubStore.settings.chatgptArchiveRoot)
        } label: {
            Label("刷新", systemImage: "arrow.clockwise")
        }
        .controlSize(.small)
        .help("刷新 ChatGPT 归档")

        if workspaceTab == .sessions {
            Button("生成处理任务") {
                do {
                    _ = try store.generateTask()
                } catch {
                    // Store keeps the actionable error for the visible status area.
                }
            }
            .controlSize(.small)
            .disabled(store.selectedConversationIDs.isEmpty)
            .help("勾选左侧会话后生成处理任务")
        }
    }

    @ViewBuilder
    private var sessionFilterAccessory: some View {
        Toggle("日期", isOn: $usesDateRange)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .onChange(of: usesDateRange) { _, _ in synchronizeDateRange() }

        if usesDateRange {
            DatePicker("从", selection: $rangeStart, displayedComponents: .date)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 96)
                .onChange(of: rangeStart) { _, _ in synchronizeDateRange() }
            Text("–")
                .font(.caption2)
                .foregroundStyle(.secondary)
            DatePicker("到", selection: $rangeEnd, displayedComponents: .date)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 96)
                .onChange(of: rangeEnd) { _, _ in synchronizeDateRange() }
        }

        Menu {
            ForEach(chatConversationStatuses, id: \.self) { status in
                Toggle(status.title, isOn: statusBinding(status))
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .help("按处理状态筛选")
        .frame(width: 24)
    }

    private var workspaceHelp: String {
        switch workspaceTab {
        case .sessions:
            return "点选导入会话阅读原文；勾选后可生成处理任务。"
        case .review:
            return "核对候选后确认写入；不会自动应用。"
        case .library:
            return "正式材料：左栏目录，中栏阅读/编辑/原文。"
        case .notes:
            return "个人阅读笔记库：按原文/正式资产回跳。"
        }
    }


    private func focusNoteTarget(_ target: ReadingNoteNavigationTarget) {
        switch target {
        case .conversation(let conversationID):
            store.pendingNotesFocusConversationID = conversationID
            workspaceTab = .sessions
            focusedConversationID = conversationID
            stageMode = .source
        case .formalAsset(let assetID):
            store.pendingNotesFocusAssetID = assetID
            workspaceTab = .library
            stageMode = .read
        }
    }

    private var showsCommandPanel: Bool {
        store.lastError != nil || store.hasPendingCandidates || store.lastGeneratedCommand != nil
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
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

enum ChatChromeMetrics {
    static let headerHeight: CGFloat = 34
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
