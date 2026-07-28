import EvolutionCore
import EvolutionHubCore
import SwiftUI

private enum ReviewSelection: Hashable {
    case segment(String)
    case asset(String)
}

struct ChatConversationReviewView: View {
    @ObservedObject var store: ChatConversationHubStore
    @Binding var stageMode: ChatStageMode
    @State private var editingAsset: ChatCandidateAssetEditorItem?
    @State private var selection: ReviewSelection?

    var body: some View {
        Group {
            if let candidate = store.selectedCandidate {
                candidateWorkspace(candidate)
            } else if store.candidates.isEmpty {
                ContentUnavailableView(
                    "暂无待确认候选",
                    systemImage: "tray",
                    description: Text("Skill 发布的候选会在这里等待人工确认；不会自动应用。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "选择一份候选",
                    systemImage: "checklist",
                    description: Text("选择候选后，在左侧目录检查片段与资产，在右侧阅读正文。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editingAsset) { item in
            ChatCandidateAssetEditorSheet(asset: item.asset) {
                title,
                kind,
                subtype,
                uses,
                draftText in
                try? store.updateCandidateAsset(
                    jobID: item.jobID,
                    assetID: item.asset.id,
                    title: title,
                    kind: kind,
                    subtype: subtype,
                    uses: uses,
                    draftText: draftText
                )
            }
        }
    }

    @ViewBuilder
    private func candidateWorkspace(_ candidate: ChatConversationProposal) -> some View {
        VStack(spacing: 0) {
            toolbar(candidate)
            Divider()
            HSplitView {
                catalogPane(candidate)
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
                detailPane(candidate)
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            ensureSelection(in: candidate)
        }
        .onChange(of: candidate.jobId) { _, _ in
            selection = nil
            ensureSelection(in: candidate)
        }
        .onChange(of: candidate.assets.map(\.id)) { _, _ in
            ensureSelection(in: candidate)
        }
    }

    private func toolbar(_ candidate: ChatConversationProposal) -> some View {
        HStack(spacing: 12) {
            if store.candidates.count > 1 {
                Picker("候选", selection: candidateSelection) {
                    ForEach(store.candidates, id: \.jobId) { item in
                        Text(shortJobID(item.jobId)).tag(Optional(item.jobId))
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            Label("片段 \(candidate.segments.count)", systemImage: "rectangle.3.group")
                .foregroundStyle(.secondary)
            Label("资产 \(candidate.assets.count)", systemImage: "books.vertical")
                .foregroundStyle(.secondary)
            Label("忽略 \(candidate.ignoredMessages.count)", systemImage: "eye.slash")
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button("拒绝候选") {
                _ = try? store.rejectCandidate(jobID: candidate.jobId, reason: "User rejected candidate")
            }
            .buttonStyle(.bordered)

            Button("确认写入") {
                _ = try? store.confirmCandidate(jobID: candidate.jobId)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func catalogPane(_ candidate: ChatConversationProposal) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("候选目录")
                    .font(.headline)
                    .padding(.horizontal, 4)

                ForEach(candidate.segments) { segment in
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            selection = .segment(segment.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(segment.title.isEmpty ? "未命名片段" : segment.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                if !segment.summary.isEmpty {
                                    Text(segment.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                Text(topicLabel(segment.topicTarget))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selection == .segment(segment.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        selection == .segment(segment.id) ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)

                        let assets = candidate.assets.filter { $0.segmentId == segment.id }
                        ForEach(assets) { asset in
                            Button {
                                selection = .asset(asset.id)
                            } label: {
                                ChatStudyAssetCatalogRow(
                                    title: asset.title,
                                    kind: asset.kind,
                                    subtype: asset.subtype,
                                    uses: asset.uses,
                                    isSelected: selection == .asset(asset.id),
                                    isIncluded: store.isCandidateAssetIncluded(
                                        jobID: candidate.jobId,
                                        assetID: asset.id
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !candidate.ignoredMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("明确忽略")
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(candidate.ignoredMessages.enumerated()), id: \.offset) { _, item in
                            Text("\(item.sourceMessage.messageId)：\(item.reason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

        @ViewBuilder
    private func detailPane(_ candidate: ChatConversationProposal) -> some View {
        VStack(spacing: 0) {
            ChatStageHeader(
                mode: $stageMode,
                title: detailTitle(candidate),
                subtitle: "待确认 · 人工核对后写入",
                enabledModes: [.read, .source, .excerpt]
            )
            Divider()
            Group {
                switch selection {
                case .segment(let id):
                    if let segment = candidate.segments.first(where: { $0.id == id }) {
                        if stageMode == .source || stageMode == .excerpt {
                            ChatConversationSourceStage(
                                store: store,
                                references: segment.sourceMessages,
                                purpose: .coverage,
                                destination: .candidate(jobID: candidate.jobId, segmentID: segment.id),
                                allowsExcerpt: true,
                                excerptMode: stageMode == .excerpt
                            )
                        } else {
                            segmentEditor(segment, candidate: candidate)
                        }
                    } else {
                        emptyDetail
                    }
                case .asset(let id):
                    if let asset = candidate.assets.first(where: { $0.id == id }) {
                        if stageMode == .source || stageMode == .excerpt {
                            if let context = store.candidateSourceContext(for: asset, in: candidate) {
                                ChatConversationSourceStage(
                                    store: store,
                                    references: context.references,
                                    purpose: .evidence,
                                    destination: context.destination,
                                    allowsExcerpt: true,
                                    excerptMode: stageMode == .excerpt
                                )
                            } else {
                                emptyDetail
                            }
                        } else {
                            assetReader(asset, candidate: candidate)
                        }
                    } else {
                        emptyDetail
                    }
                case nil:
                    emptyDetail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailTitle(_ candidate: ChatConversationProposal) -> String? {
        switch selection {
        case .segment(let id):
            return candidate.segments.first(where: { $0.id == id })?.title
        case .asset(let id):
            return candidate.assets.first(where: { $0.id == id })?.title
        case nil:
            return candidate.jobId
        }
    }
    private var emptyDetail: some View {
        ContentUnavailableView(
            "选择片段或资产",
            systemImage: "doc.richtext",
            description: Text("左侧点选后，这里显示元数据编辑或正文阅读。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func segmentEditor(
        _ segment: ChatConversationProposalSegment,
        candidate: ChatConversationProposal
    ) -> some View {
        let summary = store.sourceSummary(for: segment.sourceMessages)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("片段设置")
                    .font(.title2.weight(.bold))

                VStack(alignment: .leading, spacing: 8) {
                    Text("标题")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("片段标题", text: segmentTitleBinding(candidate.jobId, segment))
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("摘要")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("片段摘要", text: segmentSummaryBinding(candidate.jobId, segment))
                        .textFieldStyle(.roundedBorder)
                }

                Text(topicLabel(segment.topicTarget))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("来源 \(summary.messageCount) 条 · 轮次 \(summary.turnCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if summary.attachmentMessageCount > 0 {
                    ChatConversationAttachmentNotice()
                }

                ChatConversationSourceView(
                    store: store,
                    references: segment.sourceMessages,
                    purpose: .coverage
                )

                let assets = candidate.assets.filter { $0.segmentId == segment.id }
                if !assets.isEmpty {
                    Divider()
                    Text("该片段下的资产")
                        .font(.headline)
                    ForEach(assets) { asset in
                        Button {
                            selection = .asset(asset.id)
                        } label: {
                            ChatStudyAssetCatalogRow(
                                title: asset.title,
                                kind: asset.kind,
                                subtype: asset.subtype,
                                uses: asset.uses,
                                isSelected: false,
                                isIncluded: store.isCandidateAssetIncluded(
                                    jobID: candidate.jobId,
                                    assetID: asset.id
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func assetReader(
        _ asset: ChatConversationProposalAsset,
        candidate: ChatConversationProposal
    ) -> some View {
        let preview: String = {
            if asset.preservation == .verbatim {
                return asset.draftText?.isEmpty == false
                    ? (asset.draftText ?? "")
                    : "原文资产将在确认时从来源块截取保存。可先点“查看原文上下文”核对范围。"
            }
            return asset.draftText ?? ""
        }()
        let sourceContext = store.candidateSourceContext(for: asset, in: candidate)
        return ChatStudyAssetReaderPane(
            title: asset.title,
            kind: asset.kind,
            subtype: asset.subtype,
            uses: asset.uses,
            preservation: asset.preservation,
            origin: asset.origin,
            bodyText: preview,
            isIncluded: inclusionBinding(candidate.jobId, asset.id),
            sourceView: sourceContext.map {
                ChatConversationSourceView(
                    store: store,
                    references: $0.references,
                    purpose: .evidence,
                    destination: $0.destination
                )
            },
            onEditCandidate: {
                editingAsset = ChatCandidateAssetEditorItem(
                    jobID: candidate.jobId,
                    asset: asset
                )
            },
            draftTextBinding: asset.preservation == .distilled
                ? draftBinding(candidate.jobId, asset)
                : nil,
            emptyBodyPlaceholder: "暂无候选正文"
        )
    }

    private func ensureSelection(in candidate: ChatConversationProposal) {
        switch selection {
        case .asset(let id) where candidate.assets.contains(where: { $0.id == id }):
            return
        case .segment(let id) where candidate.segments.contains(where: { $0.id == id }):
            return
        default:
            break
        }

        if let firstAsset = candidate.assets.first {
            selection = .asset(firstAsset.id)
        } else if let firstSegment = candidate.segments.first {
            selection = .segment(firstSegment.id)
        } else {
            selection = nil
        }
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

    private func shortJobID(_ jobID: String) -> String {
        if jobID.count <= 12 {
            return jobID
        }
        return String(jobID.prefix(8)) + "…"
    }
}

private struct ChatCandidateAssetEditorItem: Identifiable {
    var jobID: String
    var asset: ChatConversationProposalAsset

    var id: String { "\(jobID):\(asset.id)" }
}
