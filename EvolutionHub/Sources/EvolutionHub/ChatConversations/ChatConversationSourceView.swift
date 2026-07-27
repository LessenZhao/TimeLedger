import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct ChatConversationSourceView: View {
    @ObservedObject var store: ChatConversationHubStore
    let references: [ChatConversationMessageReference]

    var body: some View {
        DisclosureGroup("来源 \(references.count)") {
            ForEach(references, id: \.self) { (reference: ChatConversationMessageReference) in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(reference.conversationId)/\(reference.messageId)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(store.sourceMessage(for: reference)?.content ?? "原始消息当前不可用")
                        .font(.caption)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        }
        .font(.caption)
    }
}
