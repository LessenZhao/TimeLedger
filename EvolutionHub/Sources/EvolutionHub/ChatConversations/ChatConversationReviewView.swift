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
        let topicGroups = candidateTopicGroups(candidate)
        let newTopics = candidateTopics(candidate)
        let unmappedFindings = unmappedCandidateFindings(candidate)
        HStack(spacing: 12) {
            Label("候选片段 \(candidate.segments.count)", systemImage: "rectangle.3.group")
            Label("候选结论 \(candidate.findings.count)", systemImage: "text.bubble")
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

        Text("候选尚未写入正式账本。先核对每条结论的主题、会话片段和引用材料。")
            .font(.caption)
            .foregroundStyle(.secondary)

        ForEach(topicGroups) { group in
            VStack(alignment: .leading, spacing: 10) {
                Text(group.isNew ? "建议新主题" : "归入已有主题")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if let candidateTopic = group.candidateTopic {
                    TextField(candidateTopic.id, text: candidateTopicNameBinding(candidateTopic))
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(group.title)
                        .font(.headline)
                }

                Text("会话片段")
                    .font(.subheadline.weight(.semibold))
                ForEach(group.segments, id: \.id) { segment in
                    candidateSegmentRow(segment, newTopics: newTopics)
                }

                if !group.findings.isEmpty {
                    Text("候选结论")
                        .font(.subheadline.weight(.semibold))
                    ForEach(group.findings, id: \.id) { finding in
                        candidateFindingRow(finding, candidate: candidate)
                    }
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }

        if !unmappedFindings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("无法归属的候选结论")
                    .font(.subheadline.weight(.semibold))
                Text("这些结论没有与所属会话片段保持同一主题，不能确认写入。请重新生成候选。")
                    .font(.caption)
                    .foregroundStyle(.red)
                ForEach(unmappedFindings, id: \.id) { finding in
                    candidateFindingRow(finding, candidate: candidate)
                }
            }
            .padding(12)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
                        ChatConversationSourceView(store: store, references: match.sourceMessages, purpose: .evidence)
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

    private func candidateSegmentRow(
        _ segment: ChatConversationProposalSegment,
        newTopics: [CandidateTopic]
    ) -> some View {
        let summary = store.sourceSummary(for: segment.sourceMessages)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(store.conversationTitle(for: segment.sourceMessages.first?.conversationId ?? "")) · 会话片段")
                    .font(.caption.weight(.medium))
                Text(sourceSummaryText(summary, prefix: "已覆盖"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if hasAlternativeTopic(for: segment, newTopics: newTopics) {
                Menu("移动到…") {
                    ForEach(store.ledgerDocument.topics, id: \.id) { topic in
                        let target = ChatConversationTopicTarget.existing(id: topic.id)
                        if target != segment.topicTarget {
                            Button(topic.name) {
                                try? store.setCandidateSegmentTopic(segmentID: segment.id, target: target)
                            }
                        }
                    }
                    ForEach(newTopics, id: \.id) { topic in
                        let target = ChatConversationTopicTarget.new(id: topic.id, name: topic.name)
                        if target != segment.topicTarget {
                            Button("新主题：\(topic.name)") {
                                try? store.setCandidateSegmentTopic(segmentID: segment.id, target: target)
                            }
                        }
                    }
                }
                .font(.caption)
            }
            Spacer()
            ChatConversationSourceView(store: store, references: segment.sourceMessages, purpose: .coverage)
        }
    }

    private func candidateFindingRow(
        _ finding: ChatConversationProposalFinding,
        candidate: ChatConversationProposal
    ) -> some View {
        let supportingSegmentIDs = store.candidateSupportingSegmentIDs(for: finding, in: candidate)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(finding.body)
                    .font(.caption)
                Text("关联片段：\(supportingSegmentLabels(supportingSegmentIDs, candidate: candidate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ChatConversationSourceView(store: store, references: finding.sourceMessages, purpose: .evidence)
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

    private func candidateTopicGroups(_ candidate: ChatConversationProposal) -> [CandidateTopicGroup] {
        let targets = candidate.segments.map(\.topicTarget).reduce(into: [ChatConversationTopicTarget]()) { result, target in
            if !result.contains(target) {
                result.append(target)
            }
        }
        return targets.map { target in
            CandidateTopicGroup(
                target: target,
                title: topicLabel(target),
                segments: candidate.segments.filter { $0.topicTarget == target },
                findings: candidate.findings.filter {
                    $0.topicTarget == target && resolvedTopicTarget(for: $0, candidate: candidate) == target
                }
            )
        }
    }

    private func unmappedCandidateFindings(_ candidate: ChatConversationProposal) -> [ChatConversationProposalFinding] {
        candidate.findings.filter { finding in
            resolvedTopicTarget(for: finding, candidate: candidate) != finding.topicTarget
        }
    }

    private func resolvedTopicTarget(
        for finding: ChatConversationProposalFinding,
        candidate: ChatConversationProposal
    ) -> ChatConversationTopicTarget? {
        let supportingSegmentIDs = store.candidateSupportingSegmentIDs(for: finding, in: candidate)
        let targets = supportingSegmentIDs.compactMap { supportingID in
            candidate.segments.first(where: { $0.id == supportingID })?.topicTarget
        }
        guard Set(targets).count == 1 else { return nil }
        return targets.first
    }

    private func hasAlternativeTopic(
        for segment: ChatConversationProposalSegment,
        newTopics: [CandidateTopic]
    ) -> Bool {
        store.ledgerDocument.topics.contains { .existing(id: $0.id) != segment.topicTarget }
            || newTopics.contains { .new(id: $0.id, name: $0.name) != segment.topicTarget }
    }

    private func sourceSummaryText(_ summary: ChatConversationSourceSummary, prefix: String) -> String {
        "\(prefix) \(summary.messageCount) 条原始消息 · \(summary.userMessageCount) 次你的输入 · \(summary.assistantMessageCount) 段回复"
    }

    private func supportingSegmentLabels(
        _ segmentIDs: [String],
        candidate: ChatConversationProposal
    ) -> String {
        let labels = segmentIDs.compactMap { segmentID in
            candidate.segments.first(where: { $0.id == segmentID }).flatMap { segment in
                segment.sourceMessages.first.map { store.conversationTitle(for: $0.conversationId) }
            }
        }
        return labels.isEmpty ? "未找到关联片段" : labels.joined(separator: "、")
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

private struct CandidateTopicGroup: Identifiable {
    let target: ChatConversationTopicTarget
    let title: String
    let segments: [ChatConversationProposalSegment]
    let findings: [ChatConversationProposalFinding]

    var id: String {
        switch target {
        case .existing(let id):
            return "existing:\(id)"
        case .new(let id, _):
            return "new:\(id)"
        }
    }

    var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    var candidateTopic: CandidateTopic? {
        guard case .new(let id, let name) = target else { return nil }
        return CandidateTopic(id: id, name: name)
    }
}
