import EvolutionCore
@testable import EvolutionHubCore
import Foundation
import XCTest

final class ChatConversationHubStoreTests: XCTestCase {
    @MainActor
    func testDateAndStatusFiltersOnlyChangeVisibleConversationsNotSelection() throws {
        let fixture = try ChatConversationHubFixture()
        try fixture.writeConversation(
            id: "older",
            updatedAt: "2026-07-10T10:00:00Z",
            messages: [fixture.message(id: "old-message", content: "Older pending")]
        )
        try fixture.writeConversation(
            id: "newer",
            updatedAt: "2026-07-20T10:00:00Z",
            messages: [fixture.message(id: "new-message", content: "Newer pending")]
        )
        try fixture.writeManifest(ids: ["older", "newer"])

        let store = ChatConversationHubStore(layout: fixture.layout)
        try store.refresh(archiveRoot: fixture.archiveRoot)
        store.setSelectedConversationIDs(["older", "newer"])
        store.dateRange = ChatConversationDateRange(
            start: try XCTUnwrap(ISO8601Codec.date(from: "2026-07-19T00:00:00Z")),
            end: try XCTUnwrap(ISO8601Codec.date(from: "2026-07-21T23:59:59Z"))
        )
        store.statusFilter = [.pending]

        XCTAssertEqual(store.visibleConversations.map(\.conversationId), ["newer"])
        XCTAssertEqual(store.selectedConversationIDs, ["older", "newer"])
    }

    @MainActor
    func testPartialConversationGeneratesTaskForPendingVersionsAndShowsExplicitCommand() throws {
        let fixture = try ChatConversationHubFixture()
        try fixture.writeConversation(
            id: "partial",
            updatedAt: "2026-07-20T10:00:00Z",
            messages: [
                fixture.message(id: "processed", content: "Already accepted"),
                fixture.message(id: "pending", content: "Only this revision is pending"),
            ]
        )
        try fixture.writeManifest(ids: ["partial"])
        let acceptedReceipt = ChatConversationReceipt(
            jobId: "previous-job",
            proposalDigest: "previous-proposal",
            status: .accepted,
            recordedAt: "2026-07-20T10:01:00Z"
        )
        try JSONChatConversationLedgerStore(layout: fixture.layout).save(
            ChatConversationLedgerDocument(processedRevisions: [
                ChatConversationProcessedRevision(
                    conversationId: "partial",
                    messageId: "processed",
                    contentHash: ContentHasher.hash("Already accepted"),
                    taskId: "previous-job"
                )
            ], receipts: [acceptedReceipt])
        )
        try JSONEncoder().encode(acceptedReceipt).write(
            to: fixture.layout.chatConversationReceiptURL(jobId: acceptedReceipt.jobId)
        )

        let store = ChatConversationHubStore(
            layout: fixture.layout,
            jobIDGenerator: { "job-partial" }
        )
        try store.refresh(archiveRoot: fixture.archiveRoot)
        store.setSelectedConversationIDs(["partial"])

        let task = try store.generateTask()

        XCTAssertEqual(store.visibleConversations.first?.status, .partiallyProcessed)
        XCTAssertEqual(task.inputMessages.filter { !$0.contextOnly }.map(\.messageId), ["pending"])
        XCTAssertEqual(store.lastGeneratedCommand, "$chatgpt-ledger process job-partial")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.layout.chatConversationJobURL(jobId: "job-partial").path))
    }

    @MainActor
    func testRefreshReportsArchiveConfigurationAndReexportProblemsExplicitly() throws {
        let fixture = try ChatConversationHubFixture()
        try fixture.writeManifest(ids: ["missing-data"])
        let store = ChatConversationHubStore(layout: fixture.layout)

        store.refresh(archiveRootPath: "")

        XCTAssertEqual(store.lastError, "请先在设置中配置 ChatGPT archive 根目录。")
        XCTAssertTrue(store.conversations.isEmpty)

        try store.refresh(archiveRoot: fixture.archiveRoot)

        XCTAssertEqual(store.conversations.first?.status, .needsReexport)
        XCTAssertEqual(store.conversations.first?.issue, .missingStructuredData)
        XCTAssertFalse(store.isSelectable(conversationID: "missing-data"))
    }

    @MainActor
    func testCandidateConfirmationAndBothProjectionsReuseTheSameFormalSources() throws {
        let fixture = try ChatConversationHubFixture()
        try fixture.writeConversation(
            id: "conversation-1",
            updatedAt: "2026-07-20T10:00:00Z",
            messages: [fixture.message(id: "message-1", content: "Source message")]
        )
        try fixture.writeConversation(
            id: "empty-conversation",
            updatedAt: "2026-07-20T10:00:00Z",
            messages: [fixture.message(id: "empty-message", content: "Not yet accepted")]
        )
        try fixture.writeManifest(ids: ["conversation-1", "empty-conversation"])
        let store = ChatConversationHubStore(layout: fixture.layout, jobIDGenerator: { "job-review" })
        try store.refresh(archiveRoot: fixture.archiveRoot)
        store.setSelectedConversationIDs(["conversation-1"])
        let task = try store.generateTask()
        let sourceMessage = try XCTUnwrap(task.inputMessages.first(where: { !$0.contextOnly }))
        let source = sourceMessage.reference
        let candidate = ChatConversationProposal(
            jobId: task.jobId,
            sourceDigest: task.sourceDigest,
            baseLedgerDigest: task.baseLedgerDigest,
            segments: [
                ChatConversationProposalSegment(
                    id: "segment-1",
                    title: "候选片段",
                    summary: "覆盖选中消息",
                    topicTarget: .new(id: "topic-1", name: "Candidate topic"),
                    sourceMessages: [source]
                )
            ],
            assets: [
                ChatConversationProposalAsset(
                    id: "asset-1",
                    segmentId: "segment-1",
                    title: "Supported asset",
                    kind: .viewpointKnowledge,
                    subtype: "观点",
                    uses: [.review],
                    preservation: .distilled,
                    draftText: "Supported finding",
                    sourceBlockIDs: sourceMessage.sourceBlocks.map(\.id),
                    sourceSpans: [],
                    replacesAssetID: nil,
                    origin: .skill
                )
            ],
            ignoredMessages: []
        )
        try fixture.writeCandidate(candidate)

        try store.refresh(archiveRoot: fixture.archiveRoot)
        XCTAssertEqual(store.candidates.map(\.jobId), [candidate.jobId])
        XCTAssertTrue(store.hasPendingCandidates)
        XCTAssertNil(store.lastGeneratedCommand)
        store.selectCandidate(jobID: task.jobId)
        try store.setCandidateSegmentTopic(
            segmentID: "segment-1",
            target: .new(id: "topic-2", name: "Moved topic")
        )
        let movedCandidate = try XCTUnwrap(store.selectedCandidate)
        XCTAssertEqual(movedCandidate.segments[0].topicTarget, .new(id: "topic-2", name: "Moved topic"))
        try store.renameCandidateTopic(id: "topic-2", name: "User topic")
        let receipt = try store.confirmCandidate(jobID: task.jobId)

        XCTAssertEqual(receipt.status, .accepted)
        XCTAssertTrue(store.candidates.isEmpty)
        XCTAssertNil(store.lastGeneratedCommand)
        XCTAssertEqual(store.conversationProjections.first?.segments.map(\.id), ["segment-1"])
        XCTAssertEqual(store.topicProjections.first?.topic.name, "User topic")
        XCTAssertEqual(store.topicProjections.first?.assets.map(\.assetID), ["asset-1"])
        XCTAssertEqual(
            Set(store.formalConversationProjections.map(\.conversationId)),
            ["conversation-1"]
        )
        XCTAssertEqual(store.sourceMessage(for: source)?.content, "Source message")
    }

    @MainActor
    func testCandidateCanExcludeOneAssetWithoutDroppingSegmentCoverage() throws {
        let store = try makeStoreWithCandidate(assetCount: 2)
        let candidate = try XCTUnwrap(store.selectedCandidate)

        try store.setCandidateAssetIncluded(
            jobID: candidate.jobId,
            assetID: candidate.assets[0].id,
            isIncluded: false
        )
        let receipt = try store.confirmCandidate(jobID: candidate.jobId)

        XCTAssertEqual(receipt.status, .accepted)
        XCTAssertEqual(store.ledgerDocument.segments.count, 1)
        XCTAssertEqual(store.ledgerDocument.assets.count, 1)
    }

    @MainActor
    func testCandidateMetadataAndDistilledBodyCanBeCorrectedBeforeConfirmation() throws {
        let store = try makeStoreWithCandidate(
            assetCount: 1,
            preservation: .distilled
        )
        let candidate = try XCTUnwrap(store.selectedCandidate)
        let asset = try XCTUnwrap(candidate.assets.first)

        try store.updateCandidateAsset(
            jobID: candidate.jobId,
            assetID: asset.id,
            title: "用户修正标题",
            kind: .methodStrategy,
            subtype: "备考策略",
            uses: [.practice, .review],
            draftText: "用户修正后的提炼正文"
        )

        let updated = try XCTUnwrap(store.selectedCandidate?.assets.first)
        XCTAssertEqual(updated.title, "用户修正标题")
        XCTAssertEqual(updated.kind, .methodStrategy)
        XCTAssertEqual(updated.subtype, "备考策略")
        XCTAssertEqual(updated.uses, [.practice, .review])
        XCTAssertEqual(updated.draftText, "用户修正后的提炼正文")
        XCTAssertEqual(updated.origin, .userEdited)
    }

    @MainActor
    func testOneAssetAppearsInConversationTopicAndKindProjections() throws {
        let store = try makeStoreWithAcceptedAsset(kind: .finishedWork)
        let assetID = try XCTUnwrap(store.ledgerDocument.assets.first?.id)

        XCTAssertEqual(store.formalConversationProjections.flatMap(\.assets).map(\.id), [assetID])
        XCTAssertEqual(store.topicProjections.flatMap(\.assets).map(\.id), [assetID])
        XCTAssertEqual(store.kindProjections.flatMap(\.assets).map(\.id), [assetID])
    }

    @MainActor
    func testUserEditAppendsVersionAndKeepsOldText() throws {
        let store = try makeStoreWithAcceptedAsset(kind: .finishedWork)
        let asset = try XCTUnwrap(store.ledgerDocument.assets.first)
        let oldVersionID = asset.currentVersionId
        let oldText = asset.versions.first?.textSnapshot

        try store.appendUserEditedVersion(
            assetID: asset.id,
            text: "用户确认后的完整新版本"
        )

        let updated = try XCTUnwrap(store.ledgerDocument.assets.first)
        XCTAssertEqual(updated.versions.count, 2)
        XCTAssertEqual(updated.versions.last?.supersedesVersionId, oldVersionID)
        XCTAssertEqual(updated.versions.last?.origin, .userEdited)
        XCTAssertEqual(updated.versions.first?.textSnapshot, oldText)
        XCTAssertTrue(updated.isUserLocked)
    }

    @MainActor
    func testManualFormalAssetIsLockedAgainstSkillReplace() throws {
        let store = try makeStoreWithAcceptedAsset(kind: .finishedWork)
        let segmentID = try XCTUnwrap(store.ledgerDocument.segments.first?.id)
        let message = ChatConversationMessage(
            id: "assistant-manual",
            role: .assistant,
            createdAt: "2026-07-27T00:00:00Z",
            content: "前文🙂需要背诵的规范表述。\n后文"
        )
        let range = (message.content as NSString).range(of: "需要背诵的规范表述。")
        let selection = try ChatConversationTextSelection.make(
            conversationID: "conversation-1",
            message: message,
            rangeUTF16: range
        )
        try store.addManualFormalAsset(
            segmentID: segmentID,
            selection: selection,
            title: "规范表述",
            kind: .expressionModule,
            subtype: "规范表述",
            uses: [.memorize]
        )
        let manual = try XCTUnwrap(store.ledgerDocument.assets.first(where: { $0.originLocked }))
        XCTAssertTrue(manual.isUserLocked)
        XCTAssertEqual(manual.currentVersion?.textSnapshot, "需要背诵的规范表述。")
    }

    @MainActor
    func testHunanBatchOneAssetsAndProjections() throws {
        let fixture = try ChatConversationHubFixture()
        try fixture.writeHunanConversation(batch: 1)
        try fixture.writeManifest(ids: ["hunan-selection-1"])
        let store = ChatConversationHubStore(layout: fixture.layout, jobIDGenerator: { "job-hunan-1" })
        try store.refresh(archiveRoot: fixture.archiveRoot)
        store.setSelectedConversationIDs(["hunan-selection-1"])
        let task = try store.generateTask()
        let proposal = try fixture.makeHunanBatchOneProposal(task: task)
        try fixture.writeCandidate(proposal)
        try store.refresh(archiveRoot: fixture.archiveRoot)
        store.selectCandidate(jobID: task.jobId)
        _ = try store.confirmCandidate(jobID: task.jobId)

        XCTAssertEqual(store.ledgerDocument.segments.count, 3)
        let essay = try XCTUnwrap(store.ledgerDocument.assets.first(where: { $0.kind == .finishedWork }))
        let essayVersion = try XCTUnwrap(essay.currentVersion)
        let essayBlocks = task.inputMessages
            .first(where: { $0.messageId == "batch1-assistant-essay" })?
            .sourceBlocks ?? []
        XCTAssertEqual(essayVersion.textHash, ContentHasher.hash(essayBlocks.map(\.text).joined()))
        XCTAssertTrue(store.ledgerDocument.assets.contains(where: {
            $0.kind == .expressionModule && $0.uses.contains(.memorize)
        }))
        XCTAssertTrue(store.ledgerDocument.assets.contains(where: {
            $0.kind == .methodStrategy && $0.currentVersion?.preservation == .distilled
        }))
        let assetID = essay.id
        XCTAssertEqual(store.formalConversationProjections.flatMap(\.assets).filter { $0.id == assetID }.count, 1)
        XCTAssertEqual(store.topicProjections.flatMap(\.assets).filter { $0.id == assetID }.count, 1)
        XCTAssertEqual(store.kindProjections.flatMap(\.assets).filter { $0.id == assetID }.count, 1)
    }

    @MainActor
    func testHunanBatchTwoOnlyContainsNewMessages() throws {
        let fixture = try ChatConversationHubFixture()
        try fixture.writeHunanConversation(batch: 1)
        try fixture.writeManifest(ids: ["hunan-selection-1"])
        let store = ChatConversationHubStore(layout: fixture.layout, jobIDGenerator: { "job-hunan-1" })
        try store.refresh(archiveRoot: fixture.archiveRoot)
        store.setSelectedConversationIDs(["hunan-selection-1"])
        let firstTask = try store.generateTask()
        try fixture.writeCandidate(try fixture.makeHunanBatchOneProposal(task: firstTask))
        try store.refresh(archiveRoot: fixture.archiveRoot)
        _ = try store.confirmCandidate(jobID: firstTask.jobId)

        try fixture.writeHunanConversation(batch: 2)
        let secondStore = ChatConversationHubStore(layout: fixture.layout, jobIDGenerator: { "job-hunan-2" })
        try secondStore.refresh(archiveRoot: fixture.archiveRoot)
        secondStore.setSelectedConversationIDs(["hunan-selection-1"])
        let secondTask = try secondStore.generateTask()
        let pendingIDs = secondTask.inputMessages.filter { !$0.contextOnly }.map(\.messageId)
        XCTAssertEqual(Set(pendingIDs), [
            "batch2-user-patch",
            "batch2-assistant-patch",
            "batch2-user-case",
            "batch2-assistant-case",
        ])
        XCTAssertFalse(pendingIDs.contains("batch1-assistant-essay"))
    }

    @MainActor
    func testRejectingCandidateLeavesSourcePendingAndRemovesItFromReview() throws {
        let fixture = try ChatConversationHubFixture()
        try fixture.writeConversation(
            id: "conversation-1",
            updatedAt: "2026-07-20T10:00:00Z",
            messages: [fixture.message(id: "message-1", content: "Source message")]
        )
        try fixture.writeManifest(ids: ["conversation-1"])
        let store = ChatConversationHubStore(layout: fixture.layout, jobIDGenerator: { "job-reject" })
        try store.refresh(archiveRoot: fixture.archiveRoot)
        store.setSelectedConversationIDs(["conversation-1"])
        let task = try store.generateTask()
        let source = try XCTUnwrap(task.inputMessages.first(where: { !$0.contextOnly })?.reference)
        try fixture.writeCandidate(ChatConversationProposal(
            jobId: task.jobId,
            sourceDigest: task.sourceDigest,
            baseLedgerDigest: task.baseLedgerDigest,
            segments: [
                ChatConversationProposalSegment(
                    id: "segment-1",
                    title: "片段",
                    summary: "摘要",
                    topicTarget: .new(id: "topic-1", name: "Candidate topic"),
                    sourceMessages: [source]
                )
            ],
            assets: [],
            ignoredMessages: []
        ))
        try store.refresh(archiveRoot: fixture.archiveRoot)

        let receipt = try store.rejectCandidate(jobID: task.jobId, reason: "Not useful")

        XCTAssertEqual(receipt.status, .rejected)
        XCTAssertTrue(store.candidates.isEmpty)
        XCTAssertEqual(store.conversations.first?.pendingMessageCount, 1)
        XCTAssertTrue(store.ledgerDocument.processedRevisions.isEmpty)
    }
}

private extension ChatStudyAsset {
    var originLocked: Bool { isUserLocked }
}

@MainActor
private func makeStoreWithCandidate(
    assetCount: Int,
    preservation: ChatStudyAssetPreservation = .verbatim
) throws -> ChatConversationHubStore {
    let fixture = try ChatConversationHubFixture()
    try fixture.writeConversation(
        id: "conversation-1",
        updatedAt: "2026-07-20T10:00:00Z",
        messages: [
            fixture.message(id: "user-1", content: "请写范文", role: .user),
            fixture.message(id: "assistant-1", content: "申论范文\n第一段。\n第二段。\n", role: .assistant),
        ]
    )
    try fixture.writeManifest(ids: ["conversation-1"])
    let store = ChatConversationHubStore(layout: fixture.layout, jobIDGenerator: { "job-assets" })
    try store.refresh(archiveRoot: fixture.archiveRoot)
    store.setSelectedConversationIDs(["conversation-1"])
    let task = try store.generateTask()
    let assistant = try XCTUnwrap(task.inputMessages.first { $0.role == .assistant })
    let user = try XCTUnwrap(task.inputMessages.first { $0.role == .user })
    let blocks = assistant.sourceBlocks
    var assets: [ChatConversationProposalAsset] = []
    for index in 0..<assetCount {
        assets.append(
            ChatConversationProposalAsset(
                id: "asset-\(index + 1)",
                segmentId: "segment-1",
                title: "资产 \(index + 1)",
                kind: .finishedWork,
                subtype: "范文",
                uses: [.memorize],
                preservation: preservation,
                draftText: preservation == .distilled ? "原始提炼正文" : nil,
                sourceBlockIDs: blocks.map(\.id),
                sourceSpans: [],
                replacesAssetID: nil,
                origin: .skill
            )
        )
    }
    let candidate = ChatConversationProposal(
        jobId: task.jobId,
        sourceDigest: task.sourceDigest,
        baseLedgerDigest: task.baseLedgerDigest,
        segments: [
            ChatConversationProposalSegment(
                id: "segment-1",
                title: "完整范文",
                summary: "生成范文",
                topicTarget: .new(id: "topic-1", name: "写作训练"),
                sourceMessages: [user.reference, assistant.reference]
            )
        ],
        assets: assets,
        ignoredMessages: []
    )
    try fixture.writeCandidate(candidate)
    try store.refresh(archiveRoot: fixture.archiveRoot)
    store.selectCandidate(jobID: task.jobId)
    return store
}

@MainActor
private func makeStoreWithAcceptedAsset(kind: ChatStudyAssetKind) throws -> ChatConversationHubStore {
    let store = try makeStoreWithCandidate(assetCount: 1)
    if var candidate = store.selectedCandidate, !candidate.assets.isEmpty {
        candidate.assets[0].kind = kind
        // update via inclusion path already selected
        _ = candidate
    }
    let candidate = try XCTUnwrap(store.selectedCandidate)
    _ = try store.confirmCandidate(jobID: candidate.jobId)
    return store
}

private struct ChatConversationHubFixture {
    let root: URL
    let archiveRoot: URL
    let layout: EvolutionLedgerLayout

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatConversationHubStoreTests-\(UUID().uuidString)", isDirectory: true)
        archiveRoot = root.appendingPathComponent("archive", isDirectory: true)
        layout = EvolutionLedgerLayout(rootURL: root.appendingPathComponent("Personal Evolution", isDirectory: true))
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        try layout.ensureDirectories()
    }

    func message(id: String, content: String, role: ChatConversationRole = .user) -> ChatConversationMessage {
        ChatConversationMessage(
            id: id,
            role: role,
            createdAt: "2026-07-20T10:00:00Z",
            content: content
        )
    }

    func writeConversation(id: String, updatedAt: String, messages: [ChatConversationMessage]) throws {
        let file = ChatConversationArchiveFile(
            schemaVersion: 1,
            conversationId: id,
            title: "Conversation \(id)",
            sourceURL: "https://chatgpt.com/c/\(id)",
            createdAt: "2026-07-01T10:00:00Z",
            updatedAt: updatedAt,
            messages: messages
        )
        let url = archiveRoot.appendingPathComponent("data/conversations/\(id).json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(file).write(to: url)
    }

    func writeManifest(ids: [String]) throws {
        let manifest = Dictionary(uniqueKeysWithValues: ids.map { id in
            (
                id,
                [
                    "createdAt": "2026-07-01T10:00:00Z",
                    "lastActivityAt": "2026-07-20T10:00:00Z",
                    "lastSnapshotFilename": "2026-07-20--Conversation \(id).md",
                    "lastDataFilename": "data/conversations/\(id).json",
                ]
            )
        })
        let url = archiveRoot.appendingPathComponent("_archive-index.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: url)
    }

    func writeCandidate(_ candidate: ChatConversationProposal) throws {
        try JSONEncoder().encode(candidate).write(
            to: layout.chatConversationProposalInboxDirectoryURL
                .appendingPathComponent("\(candidate.jobId).json"),
            options: .atomic
        )
    }

    func writeHunanConversation(batch: Int) throws {
        let url = Bundle.module.url(
            forResource: "HunanSelectionConversation",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/HunanSelectionConversation.json")
        let file = try JSONDecoder().decode(ChatConversationArchiveFile.self, from: Data(contentsOf: url))
        let keepIDs: Set<String>
        if batch == 1 {
            keepIDs = Set(file.messages.prefix(6).map(\.id))
        } else {
            keepIDs = Set(file.messages.map(\.id))
        }
        let trimmed = ChatConversationArchiveFile(
            schemaVersion: file.schemaVersion,
            conversationId: file.conversationId,
            title: file.title,
            sourceURL: file.sourceURL,
            createdAt: file.createdAt,
            updatedAt: file.updatedAt,
            messages: file.messages.filter { keepIDs.contains($0.id) }
        )
        let out = archiveRoot.appendingPathComponent("data/conversations/\(file.conversationId).json")
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(trimmed).write(to: out)
    }

    func makeHunanBatchOneProposal(task: ChatConversationProcessingTask) throws -> ChatConversationProposal {
        func message(_ id: String) throws -> ChatConversationTaskMessage {
            try XCTUnwrap(task.inputMessages.first(where: { $0.messageId == id }))
        }
        let strategyAssistant = try message("batch1-assistant-strategy")
        let essayAssistant = try message("batch1-assistant-essay")
        let modulesAssistant = try message("batch1-assistant-modules")
        let strategyUser = try message("batch1-user-strategy")
        let essayUser = try message("batch1-user-essay")
        let modulesUser = try message("batch1-user-modules")
        return ChatConversationProposal(
            jobId: task.jobId,
            sourceDigest: task.sourceDigest,
            baseLedgerDigest: task.baseLedgerDigest,
            segments: [
                ChatConversationProposalSegment(
                    id: "seg-strategy",
                    title: "三阶段备考策略",
                    summary: "给出备考三阶段方法。",
                    topicTarget: .new(id: "topic-hunan", name: "湖南省直遴选"),
                    sourceMessages: [strategyUser.reference, strategyAssistant.reference]
                ),
                ChatConversationProposalSegment(
                    id: "seg-essay",
                    title: "扩大内需完整范文",
                    summary: "生成完整范文。",
                    topicTarget: .new(id: "topic-hunan", name: "湖南省直遴选"),
                    sourceMessages: [essayUser.reference, essayAssistant.reference]
                ),
                ChatConversationProposalSegment(
                    id: "seg-modules",
                    title: "背诵表达模块",
                    summary: "提炼两个背诵模块。",
                    topicTarget: .new(id: "topic-hunan", name: "湖南省直遴选"),
                    sourceMessages: [modulesUser.reference, modulesAssistant.reference]
                ),
            ],
            assets: [
                ChatConversationProposalAsset(
                    id: "asset-strategy",
                    segmentId: "seg-strategy",
                    title: "三阶段备考策略",
                    kind: .methodStrategy,
                    subtype: "备考策略",
                    uses: [.practice, .review],
                    preservation: .distilled,
                    draftText: "基础、专项、冲刺三阶段推进。",
                    sourceBlockIDs: strategyAssistant.sourceBlocks.map(\.id),
                    sourceSpans: [],
                    replacesAssetID: nil,
                    origin: .skill
                ),
                ChatConversationProposalAsset(
                    id: "asset-essay",
                    segmentId: "seg-essay",
                    title: "扩大内需完整范文",
                    kind: .finishedWork,
                    subtype: "范文",
                    uses: [.memorize, .imitate],
                    preservation: .verbatim,
                    draftText: nil,
                    sourceBlockIDs: essayAssistant.sourceBlocks.map(\.id),
                    sourceSpans: [],
                    replacesAssetID: nil,
                    origin: .skill
                ),
                ChatConversationProposalAsset(
                    id: "asset-modules",
                    segmentId: "seg-modules",
                    title: "两个背诵表达模块",
                    kind: .expressionModule,
                    subtype: "表达模块",
                    uses: [.memorize],
                    preservation: .verbatim,
                    draftText: nil,
                    sourceBlockIDs: modulesAssistant.sourceBlocks.map(\.id),
                    sourceSpans: [],
                    replacesAssetID: nil,
                    origin: .skill
                ),
            ],
            ignoredMessages: []
        )
    }
}
