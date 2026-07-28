import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct ChatConversationListView<HeaderAccessory: View>: View {
    @ObservedObject var store: ChatConversationHubStore
    var focusedConversationID: Binding<String?>? = nil
    var onOpenConversation: ((String) -> Void)? = nil
    var showsHeader: Bool = true
    @ViewBuilder var headerAccessory: () -> HeaderAccessory

    init(
        store: ChatConversationHubStore,
        focusedConversationID: Binding<String?>? = nil,
        onOpenConversation: ((String) -> Void)? = nil,
        showsHeader: Bool = true,
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory = { EmptyView() }
    ) {
        self.store = store
        self.focusedConversationID = focusedConversationID
        self.onOpenConversation = onOpenConversation
        self.showsHeader = showsHeader
        self.headerAccessory = headerAccessory
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack(spacing: 8) {
                    Text("导入会话")
                        .font(.subheadline.weight(.semibold))
                    headerAccessory()
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
                }
                .padding(.horizontal, 12)
                .frame(height: 34)

                Divider()
            }

            if store.visibleConversations.isEmpty {
                ContentUnavailableView(
                    store.showsOnlyStarredConversations ? "没有星标会话" : "没有符合条件的 ChatGPT 对话",
                    systemImage: store.showsOnlyStarredConversations ? "star" : "bubble.left.and.bubble.right",
                    description: Text(
                        store.showsOnlyStarredConversations
                            ? "点会话行上的星标标记重点，或关闭仅星标过滤。"
                            : "检查归档路径、日期范围和处理状态筛选。"
                    )
                )
            } else {
                conversationList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(store.visibleConversationDayGroups) { group in
                    sectionHeader(group)
                    ForEach(group.conversations, id: \.conversationId) { conversation in
                        conversationRow(conversation)
                        Divider()
                    }
                }
            }
        }
    }

    private func sectionHeader(_ group: ChatConversationDayGroup) -> some View {
        HStack(spacing: 8) {
            Text(ChatConversationDayGrouping.title(for: group.dayStart))
                .font(.subheadline.weight(.semibold))
            Text("\(group.conversations.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func conversationRow(_ conversation: ChatConversationArchiveSummary) -> some View {
        let isFocused = focusedConversationID?.wrappedValue == conversation.conversationId
        let isStarred = store.isConversationStarred(conversation.conversationId)

        return HStack(alignment: .top, spacing: 10) {
            Toggle(
                isOn: Binding(
                    get: { store.selectedConversationIDs.contains(conversation.conversationId) },
                    set: { _ in store.toggleSelection(conversationID: conversation.conversationId) }
                )
            ) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!store.isSelectable(conversationID: conversation.conversationId))

            Button {
                store.toggleConversationStar(conversationID: conversation.conversationId)
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundStyle(isStarred ? Color.orange : Color.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isStarred ? "取消会话星标" : "标记为重点会话")

            Button {
                onOpenConversation?(conversation.conversationId)
                focusedConversationID?.wrappedValue = conversation.conversationId
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text("\(conversation.status.title) · 已处理 \(conversation.processedMessageCount) · 待处理 \(conversation.pendingMessageCount)")
                        .font(.caption)
                        .foregroundStyle(conversation.issue == nil ? Color.secondary : Color.orange)
                    Text("更新于 \(conversation.updatedAt)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if conversation.messages.contains(where: {
                        ChatConversationEvidencePresentation
                            .containsAttachmentReference(in: $0.content)
                    }) {
                        Label("含附件（附件正文未归档）", systemImage: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let issue = conversation.issue {
                        Label(issue.title, systemImage: "arrow.clockwise.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isFocused ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

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

private extension ChatConversationArchiveIssue {
    var title: String {
        switch self {
        case .missingStructuredData:
            return "缺少结构化数据，请重新导出"
        case .invalidStructuredData:
            return "结构化数据无效，请重新导出"
        case .mismatchedConversationIdentity:
            return "结构化数据与会话不匹配，请重新导出"
        }
    }
}
