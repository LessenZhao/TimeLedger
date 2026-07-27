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
                        if store.formalConversationProjections.isEmpty {
                            ContentUnavailableView(
                                "尚未确认正式内容",
                                systemImage: "checkmark.seal",
                                description: Text("确认候选后，这里会按会话显示片段、结论和证据链。")
                            )
                        } else {
                            ForEach(store.formalConversationProjections, id: \.id) { projection in
                                conversationProjection(projection)
                            }
                        }
                    case .topic:
                        if store.topicProjections.isEmpty {
                            ContentUnavailableView(
                                "尚未确认正式主题",
                                systemImage: "tag",
                                description: Text("确认候选后，这里会按主题汇总片段、结论和证据链。")
                            )
                        } else {
                            ForEach(store.topicProjections, id: \.id) { projection in
                                topicProjection(projection)
                            }
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
        DisclosureGroup("\(projection.title) · \(projection.segments.count) 个会话片段 / \(projection.findings.count) 条结论") {
            VStack(alignment: .leading, spacing: 8) {
                if !projection.segments.isEmpty {
                    Text("会话片段")
                        .font(.subheadline.weight(.semibold))
                    ForEach(projection.segments, id: \.id) { segment in
                        formalSegmentRow(segment, allowsMove: true)
                    }
                }

                if !projection.findings.isEmpty {
                    Text("正式结论")
                        .font(.subheadline.weight(.semibold))
                    ForEach(projection.findings, id: \.id) { finding in
                        findingRow(finding)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func topicProjection(_ projection: ChatConversationTopicProjection) -> some View {
        DisclosureGroup("\(projection.topic.name) · \(projection.segments.count) 个会话片段 / \(projection.findings.count) 条结论") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("主题名称", text: topicNameBinding(projection.topic))
                        .textFieldStyle(.roundedBorder)
                    Menu("合并到") {
                        ForEach(store.ledgerDocument.topics.filter { $0.id != projection.topic.id }, id: \.id) { target in
                            Button(target.name) {
                                try? store.mergeTopic(id: projection.topic.id, intoTopicID: target.id)
                            }
                        }
                    }
                    .font(.caption)
                }

                if !projection.findings.isEmpty {
                    Text("正式结论")
                        .font(.subheadline.weight(.semibold))
                    ForEach(projection.findings, id: \.id) { finding in
                        findingRow(finding)
                    }
                }

                if !projection.segments.isEmpty {
                    Text("会话片段")
                        .font(.subheadline.weight(.semibold))
                    ForEach(projection.segments, id: \.id) { segment in
                        formalSegmentRow(segment, allowsMove: false)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func formalSegmentRow(_ segment: ChatConversationSegment, allowsMove: Bool) -> some View {
        let summary = store.sourceSummary(for: segment.sourceMessages)
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(store.conversationTitle(for: segment.conversationId)) · \(topicName(segment.topicId))")
                    .font(.caption.weight(.medium))
                Text(sourceSummaryText(summary, prefix: "已覆盖"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if allowsMove {
                Menu("移动") {
                    ForEach(store.ledgerDocument.topics, id: \.id) { topic in
                        Button(topic.name) {
                            try? store.moveSegment(id: segment.id, toTopicID: topic.id)
                        }
                    }
                }
                .font(.caption)
            }
            Spacer()
            ChatConversationSourceView(store: store, references: segment.sourceMessages, purpose: .coverage)
        }
    }

    @ViewBuilder
    private func findingRow(_ finding: ChatConversationFinding) -> some View {
        let mark = store.mark(for: finding.id)
        let segmentIDs = store.formalSupportingSegmentIDs(for: finding)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
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
                Spacer()
                ChatConversationSourceView(store: store, references: finding.sourceMessages, purpose: .evidence)
            }
            Text("关联会话片段：\(segmentLabels(segmentIDs))")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                "备注",
                text: Binding(
                    get: { mark?.note ?? "" },
                    set: { try? store.setMark(findingID: finding.id, isHighlighted: mark?.isHighlighted ?? false, note: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 300)
        }
        .padding(.vertical, 3)
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

    private func sourceSummaryText(_ summary: ChatConversationSourceSummary, prefix: String) -> String {
        "\(prefix) \(summary.messageCount) 条原始消息 · \(summary.userMessageCount) 次你的输入 · \(summary.assistantMessageCount) 段回复"
    }

    private func segmentLabels(_ ids: [String]) -> String {
        let labels = ids.compactMap { id -> String? in
            guard let segment = store.ledgerDocument.segments.first(where: { $0.id == id }) else { return nil }
            let summary = store.sourceSummary(for: segment.sourceMessages)
            return "\(store.conversationTitle(for: segment.conversationId))（\(summary.messageCount) 条材料）"
        }
        return labels.isEmpty ? "未找到关联会话片段" : labels.joined(separator: "、")
    }
}
