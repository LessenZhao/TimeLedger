import EvolutionCore
import EvolutionHubCore
import SwiftUI

private enum ChatConversationProjectionMode: String, CaseIterable, Identifiable {
    case conversation = "按会话"
    case topic = "按主题"

    var id: Self { self }
}

struct ChatConversationLedgerView: View {
    @ObservedObject var store: ChatConversationHubStore
    @State private var mode: ChatConversationProjectionMode = .conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("正式账本")
                    .font(.headline)
                Picker("投影", selection: $mode) {
                    ForEach(ChatConversationProjectionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                Spacer()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    switch mode {
                    case .conversation:
                        ForEach(store.conversationProjections, id: \.id) { (projection: ChatConversationConversationProjection) in
                            conversationProjection(projection)
                        }
                    case .topic:
                        ForEach(store.topicProjections, id: \.id) { (projection: ChatConversationTopicProjection) in
                            topicProjection(projection)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func conversationProjection(_ projection: ChatConversationConversationProjection) -> some View {
        DisclosureGroup("\(projection.title) · \(projection.segments.count) 个片段") {
            ForEach(projection.segments, id: \.id) { (segment: ChatConversationSegment) in
                HStack {
                    Text("\(topicName(segment.topicId)) · \(segment.sourceMessages.count) 条来源")
                        .font(.caption)
                    Menu("移动") {
                        ForEach(store.ledgerDocument.topics, id: \.id) { (topic: ChatConversationTopic) in
                            Button(topic.name) {
                                try? store.moveSegment(id: segment.id, toTopicID: topic.id)
                            }
                        }
                    }
                    .font(.caption)
                    ChatConversationSourceView(store: store, references: segment.sourceMessages)
                }
            }
            ForEach(projection.findings, id: \.id) { (finding: ChatConversationFinding) in
                findingRow(finding)
            }
        }
    }

    @ViewBuilder
    private func topicProjection(_ projection: ChatConversationTopicProjection) -> some View {
        DisclosureGroup("\(projection.topic.name) · \(projection.segments.count) 个片段 / \(projection.findings.count) 个内容点") {
            HStack {
                TextField("主题名称", text: topicNameBinding(projection.topic))
                    .textFieldStyle(.roundedBorder)
                Menu("合并到") {
                    ForEach(store.ledgerDocument.topics.filter { $0.id != projection.topic.id }, id: \.id) { (target: ChatConversationTopic) in
                        Button(target.name) {
                            try? store.mergeTopic(id: projection.topic.id, intoTopicID: target.id)
                        }
                    }
                }
                .font(.caption)
            }
            ForEach(projection.segments, id: \.id) { (segment: ChatConversationSegment) in
                HStack {
                    Text("\(segment.conversationId) · \(segment.sourceMessages.count) 条来源")
                        .font(.caption)
                    ChatConversationSourceView(store: store, references: segment.sourceMessages)
                }
            }
            ForEach(projection.findings, id: \.id) { (finding: ChatConversationFinding) in
                findingRow(finding)
            }
        }
    }

    @ViewBuilder
    private func findingRow(_ finding: ChatConversationFinding) -> some View {
        let mark = store.mark(for: finding.id)
        HStack(alignment: .top) {
            Toggle(
                isOn: Binding(
                    get: { mark?.isHighlighted ?? false },
                    set: { try? store.setMark(findingID: finding.id, isHighlighted: $0, note: mark?.note) }
                )
            ) {
                Image(systemName: "star.fill")
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            Text(finding.body)
                .font(.caption)
            TextField(
                "备注",
                text: Binding(
                    get: { mark?.note ?? "" },
                    set: { try? store.setMark(findingID: finding.id, isHighlighted: mark?.isHighlighted ?? false, note: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 180)
            Spacer()
            ChatConversationSourceView(store: store, references: finding.sourceMessages)
        }
    }

    private func topicNameBinding(_ topic: ChatConversationTopic) -> Binding<String> {
        Binding(
            get: { topic.name },
            set: { try? store.renameTopic(id: topic.id, name: $0) }
        )
    }

    private func topicName(_ id: String) -> String {
        store.ledgerDocument.topics.first(where: { $0.id == id })?.name ?? id
    }
}
