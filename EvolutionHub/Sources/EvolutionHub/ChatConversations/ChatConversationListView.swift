import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct ChatConversationListView: View {
    @ObservedObject var store: ChatConversationHubStore
    var focusedConversationID: Binding<String?>? = nil
    var onOpenConversation: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("导入会话")
                    .font(.headline)
                Spacer()
                Text("\(store.visibleConversations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if store.visibleConversations.isEmpty {
                ContentUnavailableView(
                    "没有符合条件的 ChatGPT 对话",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("检查归档路径、日期范围和处理状态筛选。")
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
                ForEach(conversationItems, id: \.id) { (item: ChatConversationListItem) in
                    let conversation = item.conversation
                    let isFocused = focusedConversationID?.wrappedValue == conversation.conversationId
                    HStack(alignment: .top, spacing: 10) {
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
                    Divider()
                }
            }
        }
    }

    private var conversationItems: [ChatConversationListItem] {
        store.visibleConversations.map(ChatConversationListItem.init)
    }
}

private struct ChatConversationListItem: Identifiable {
    let conversation: ChatConversationArchiveSummary

    var id: String { conversation.conversationId }
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
