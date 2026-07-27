import EvolutionCore
import EvolutionHubCore
import SwiftUI

enum ChatConversationSourcePurpose {
    case coverage
    case evidence

    var buttonLabel: String {
        switch self {
        case .coverage:
            return "查看处理材料"
        case .evidence:
            return "查看结论依据"
        }
    }

    var title: String {
        switch self {
        case .coverage:
            return "已覆盖原始消息"
        case .evidence:
            return "结论引用的原始消息"
        }
    }

    var explanation: String {
        switch self {
        case .coverage:
            return "这些消息已被本次处理覆盖；它们不一定都直接证明同一条结论。"
        case .evidence:
            return "这些消息是该结论引用的对话材料；它们仍保留在所属会话片段中。"
        }
    }
}

struct ChatConversationSourceView: View {
    @ObservedObject var store: ChatConversationHubStore
    let references: [ChatConversationMessageReference]
    let purpose: ChatConversationSourcePurpose
    @State private var isInspectorPresented = false

    init(
        store: ChatConversationHubStore,
        references: [ChatConversationMessageReference],
        purpose: ChatConversationSourcePurpose = .coverage
    ) {
        self.store = store
        self.references = references
        self.purpose = purpose
    }

    var body: some View {
        Button {
            isInspectorPresented = true
        } label: {
            Label("\(purpose.buttonLabel) \(references.count)", systemImage: "text.book.closed")
        }
        .font(.caption)
        .sheet(isPresented: $isInspectorPresented) {
            ChatConversationSourceInspector(
                store: store,
                references: references,
                purpose: purpose
            )
        }
    }
}

private struct ChatConversationSourceInspector: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ChatConversationHubStore
    let references: [ChatConversationMessageReference]
    let purpose: ChatConversationSourcePurpose
    @State private var selectedTurnID: String?

    private var summary: ChatConversationSourceSummary {
        store.sourceSummary(for: references)
    }

    private var turns: [ChatConversationSourceTurn] {
        store.sourceTurns(for: references)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text(purpose.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    sourceSummary

                    if turns.isEmpty {
                        ContentUnavailableView(
                            "原始消息当前不可用",
                            systemImage: "exclamationmark.triangle",
                            description: Text("归档刷新后可再次查看。")
                        )
                    } else {
                        Text("按对话轮次查看")
                            .font(.headline)
                        ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                            turnRow(turn, number: index + 1)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(purpose.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 520)
    }

    private var sourceSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                "\(summary.turnCount) 轮 · \(summary.userMessageCount) 次你的输入 · \(summary.assistantMessageCount) 段回复 · \(summary.messageCount) 条原始消息"
            )
            .font(.headline)
            Text("回答的段落和换行不会增加原始消息数。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if summary.unavailableMessageCount > 0 {
                Text("其中 \(summary.unavailableMessageCount) 条消息目前无法从归档读取。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func turnRow(_ turn: ChatConversationSourceTurn, number: Int) -> some View {
        let isSelected = selectedTurnID == turn.id
        VStack(alignment: .leading, spacing: 8) {
            Button {
                selectedTurnID = isSelected ? nil : turn.id
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .frame(width: 12)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("第 \(number) 轮 · \(store.conversationTitle(for: turn.conversationId))")
                            .font(.subheadline.weight(.medium))
                        Text("\(turn.messages.count) 条原始消息 · \(preview(for: turn))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isSelected {
                ForEach(turn.messages) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(roleTitle(message.role)) · \(message.createdAt)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(message.content)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func preview(for turn: ChatConversationSourceTurn) -> String {
        guard let first = turn.messages.first else { return "" }
        let normalized = first.content.replacingOccurrences(of: "\n", with: " ")
        return String(normalized.prefix(96))
    }

    private func roleTitle(_ role: ChatConversationRole) -> String {
        switch role {
        case .user:
            return "你"
        case .assistant:
            return "ChatGPT"
        case .system:
            return "系统"
        case .tool:
            return "工具"
        }
    }
}
