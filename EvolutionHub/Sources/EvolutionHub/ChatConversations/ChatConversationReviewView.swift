import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct ChatConversationReviewView: View {
    @ObservedObject var store: ChatConversationHubStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("待确认候选")
                    .font(.headline)
                Spacer()
                if !store.candidates.isEmpty {
                    Picker("候选", selection: candidateSelection) {
                        Text("选择候选").tag(Optional<String>.none)
                        ForEach(store.candidates, id: \.jobId) { (candidate: ChatConversationProposal) in
                            Text(candidate.jobId).tag(Optional(candidate.jobId))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            if let candidate = store.selectedCandidate {
                candidateDetail(candidate)
            } else if store.candidates.isEmpty {
                Text("Skill 发布的候选会在这里等待人工确认；不会自动应用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("选择一份候选，检查覆盖、主题和来源后再确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func candidateDetail(_ candidate: ChatConversationProposal) -> some View {
        let newTopics = candidateTopics(candidate)
        HStack(spacing: 12) {
            Label("片段 \(candidate.segments.count)", systemImage: "rectangle.3.group")
            Label("内容点 \(candidate.findings.count)", systemImage: "text.bubble")
            Label("忽略 \(candidate.ignoredMessages.count)", systemImage: "eye.slash")
            Spacer()
            Button("确认写入") {
                do {
                    _ = try store.confirmCandidate(jobID: candidate.jobId)
                } catch {
                    // The store publishes the actionable failure state.
                }
            }
            .buttonStyle(.borderedProminent)
            Button("拒绝候选") {
                do {
                    _ = try store.rejectCandidate(jobID: candidate.jobId, reason: "User rejected candidate")
                } catch {
                    // The store publishes the actionable failure state.
                }
            }
            .buttonStyle(.bordered)
        }

        if !newTopics.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("候选新主题（可改名）")
                    .font(.subheadline.weight(.semibold))
                ForEach(newTopics, id: \.id) { (topic: CandidateTopic) in
                    TextField(topic.id, text: candidateTopicNameBinding(topic))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("片段与主题归属")
                .font(.subheadline.weight(.semibold))
            ForEach(candidate.segments, id: \.id) { (segment: ChatConversationProposalSegment) in
                HStack {
                    Text("\(segment.id) · \(segment.sourceMessages.count) 条来源")
                        .font(.caption)
                    Menu(topicLabel(segment.topicTarget)) {
                        ForEach(store.ledgerDocument.topics, id: \.id) { (topic: ChatConversationTopic) in
                            Button(topic.name) {
                                try? store.setCandidateSegmentTopic(
                                    segmentID: segment.id,
                                    target: .existing(id: topic.id)
                                )
                            }
                        }
                        ForEach(newTopics, id: \.id) { (topic: CandidateTopic) in
                            Button("新主题：\(topic.name)") {
                                try? store.setCandidateSegmentTopic(
                                    segmentID: segment.id,
                                    target: .new(id: topic.id, name: topic.name)
                                )
                            }
                        }
                    }
                    .font(.caption)
                    Spacer()
                    ChatConversationSourceView(store: store, references: segment.sourceMessages)
                }
            }
        }

        if !candidate.findings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("建议内容点")
                    .font(.subheadline.weight(.semibold))
                ForEach(candidate.findings, id: \.id) { (finding: ChatConversationProposalFinding) in
                    HStack(alignment: .top) {
                        Text(finding.body)
                            .font(.caption)
                        Spacer()
                        ChatConversationSourceView(store: store, references: finding.sourceMessages)
                    }
                }
            }
        }

        if !candidate.duplicateMatches.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("与已有内容点的重复匹配")
                    .font(.subheadline.weight(.semibold))
                ForEach(candidate.duplicateMatches, id: \.self) { (match: ChatConversationDuplicateMatch) in
                    HStack(alignment: .top) {
                        Text(existingFindingBody(match.existingFindingId))
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        ChatConversationSourceView(store: store, references: match.sourceMessages)
                    }
                }
            }
        }

        if !candidate.ignoredMessages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("明确忽略")
                    .font(.subheadline.weight(.semibold))
                ForEach(candidate.ignoredMessages, id: \.sourceMessage) { (ignored: ChatConversationIgnoredMessage) in
                    Text("\(ignored.sourceMessage.conversationId)/\(ignored.sourceMessage.messageId)：\(ignored.reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var candidateSelection: Binding<String?> {
        Binding(
            get: { store.selectedCandidateJobID },
            set: { store.selectCandidate(jobID: $0) }
        )
    }

    private func candidateTopicNameBinding(_ topic: CandidateTopic) -> Binding<String> {
        Binding(
            get: { topic.name },
            set: { try? store.renameCandidateTopic(id: topic.id, name: $0) }
        )
    }

    private func candidateTopics(_ candidate: ChatConversationProposal) -> [CandidateTopic] {
        var topics: [String: String] = [:]
        for target in candidate.segments.map(\.topicTarget) + candidate.findings.map(\.topicTarget) {
            guard case .new(let id, let name) = target else { continue }
            topics[id] = name
        }
        return topics.map { CandidateTopic(id: $0.key, name: $0.value) }.sorted { $0.id < $1.id }
    }

    private func topicLabel(_ target: ChatConversationTopicTarget) -> String {
        switch target {
        case .existing(let id):
            return store.ledgerDocument.topics.first(where: { $0.id == id })?.name ?? id
        case .new(_, let name):
            return "新主题：\(name)"
        }
    }

    private func existingFindingBody(_ id: String) -> String {
        store.ledgerDocument.findings.first(where: { $0.id == id })?.body ?? id
    }
}

private struct CandidateTopic: Identifiable {
    let id: String
    let name: String
}
