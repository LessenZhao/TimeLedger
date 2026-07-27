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
                        ForEach(store.candidates, id: \.jobId) { candidate in
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
                Text("选择一份候选，检查片段目录与备考资产后再确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func candidateDetail(_ candidate: ChatConversationProposal) -> some View {
        HStack(spacing: 12) {
            Label("片段 \(candidate.segments.count)", systemImage: "rectangle.3.group")
            Label("资产 \(candidate.assets.count)", systemImage: "books.vertical")
            Label("忽略 \(candidate.ignoredMessages.count)", systemImage: "eye.slash")
            Spacer()
            Button("确认写入") {
                _ = try? store.confirmCandidate(jobID: candidate.jobId)
            }
            .buttonStyle(.borderedProminent)
            Button("拒绝候选") {
                _ = try? store.rejectCandidate(jobID: candidate.jobId, reason: "User rejected candidate")
            }
            .buttonStyle(.bordered)
        }

        Text("确认写入只提交被纳入的资产，但提交全部片段与明确忽略项。")
            .font(.caption)
            .foregroundStyle(.secondary)

        ForEach(candidate.segments) { segment in
            VStack(alignment: .leading, spacing: 8) {
                TextField("片段标题", text: segmentTitleBinding(candidate.jobId, segment))
                    .textFieldStyle(.roundedBorder)
                TextField("片段摘要", text: segmentSummaryBinding(candidate.jobId, segment))
                    .textFieldStyle(.roundedBorder)
                Text(topicLabel(segment.topicTarget))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let summary = store.sourceSummary(for: segment.sourceMessages)
                Text("来源 \(summary.messageCount) 条 · 轮次 \(summary.turnCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ChatConversationSourceView(
                    store: store,
                    references: segment.sourceMessages,
                    purpose: .coverage
                )

                let assets = candidate.assets.filter { $0.segmentId == segment.id }
                Text("资产 \(assets.count)")
                    .font(.subheadline.weight(.semibold))
                ForEach(assets) { asset in
                    candidateAssetCard(asset, candidate: candidate)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        }

        if !candidate.ignoredMessages.isEmpty {
            Text("明确忽略")
                .font(.subheadline.weight(.semibold))
            ForEach(Array(candidate.ignoredMessages.enumerated()), id: \.offset) { _, item in
                Text("\(item.sourceMessage.messageId)：\(item.reason)")
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func candidateAssetCard(
        _ asset: ChatConversationProposalAsset,
        candidate: ChatConversationProposal
    ) -> some View {
        let preview: String = {
            if asset.preservation == .verbatim {
                return "原文资产将在确认时从来源块截取保存"
            }
            return asset.draftText ?? ""
        }()
        ChatStudyAssetCard(
            title: asset.title,
            kind: asset.kind,
            subtype: asset.subtype,
            uses: asset.uses,
            preservation: asset.preservation,
            origin: asset.origin,
            bodyText: preview,
            isIncluded: inclusionBinding(candidate.jobId, asset.id),
            onOpenSource: nil,
            draftTextBinding: asset.preservation == .distilled
                ? draftBinding(candidate.jobId, asset)
                : nil
        )
    }

    private var candidateSelection: Binding<String?> {
        Binding(
            get: { store.selectedCandidateJobID },
            set: { store.selectCandidate(jobID: $0) }
        )
    }

    private func inclusionBinding(_ jobID: String, _ assetID: String) -> Binding<Bool> {
        Binding(
            get: { store.isCandidateAssetIncluded(jobID: jobID, assetID: assetID) },
            set: { try? store.setCandidateAssetIncluded(jobID: jobID, assetID: assetID, isIncluded: $0) }
        )
    }

    private func draftBinding(_ jobID: String, _ asset: ChatConversationProposalAsset) -> Binding<String> {
        Binding(
            get: { asset.draftText ?? "" },
            set: { newValue in
                try? store.updateCandidateAsset(
                    jobID: jobID,
                    assetID: asset.id,
                    title: asset.title,
                    kind: asset.kind,
                    subtype: asset.subtype,
                    uses: asset.uses,
                    draftText: newValue
                )
            }
        )
    }

    private func segmentTitleBinding(_ jobID: String, _ segment: ChatConversationProposalSegment) -> Binding<String> {
        Binding(
            get: { segment.title },
            set: { try? store.setCandidateSegmentMetadata(jobID: jobID, segmentID: segment.id, title: $0, summary: segment.summary) }
        )
    }

    private func segmentSummaryBinding(_ jobID: String, _ segment: ChatConversationProposalSegment) -> Binding<String> {
        Binding(
            get: { segment.summary },
            set: { try? store.setCandidateSegmentMetadata(jobID: jobID, segmentID: segment.id, title: segment.title, summary: $0) }
        )
    }

    private func topicLabel(_ target: ChatConversationTopicTarget) -> String {
        switch target {
        case .existing(let id):
            return "主题：已有 \(id)"
        case .new(_, let name):
            return "主题：新建 \(name)"
        }
    }
}
