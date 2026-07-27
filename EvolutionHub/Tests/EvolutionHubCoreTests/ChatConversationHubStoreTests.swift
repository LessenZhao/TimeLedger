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
        let source = try XCTUnwrap(task.inputMessages.first(where: { !$0.contextOnly })?.reference)
        let candidate = ChatConversationProposal(
            jobId: task.jobId,
            sourceDigest: task.sourceDigest,
            baseLedgerDigest: task.baseLedgerDigest,
            segments: [
                ChatConversationProposalSegment(
                    id: "segment-1",
                    topicTarget: .new(id: "topic-1", name: "Candidate topic"),
                    sourceMessages: [source]
                )
            ],
            findings: [
                ChatConversationProposalFinding(
                    id: "finding-1",
                    topicTarget: .new(id: "topic-1", name: "Candidate topic"),
                    body: "Supported finding",
                    sourceMessages: [source]
                )
            ],
            ignoredMessages: []
        )
        try fixture.writeCandidate(candidate)

        try store.refresh(archiveRoot: fixture.archiveRoot)
        XCTAssertEqual(store.candidates, [candidate])
        XCTAssertTrue(store.hasPendingCandidates)
        XCTAssertNil(store.lastGeneratedCommand)
        store.selectCandidate(jobID: task.jobId)
        try store.setCandidateSegmentTopic(
            segmentID: "segment-1",
            target: .new(id: "topic-2", name: "Moved topic")
        )
        let movedCandidate = try XCTUnwrap(store.selectedCandidate)
        XCTAssertEqual(movedCandidate.segments[0].topicTarget, .new(id: "topic-2", name: "Moved topic"))
        XCTAssertEqual(movedCandidate.findings[0].topicTarget, .new(id: "topic-2", name: "Moved topic"))
        try store.renameCandidateTopic(id: "topic-2", name: "User topic")
        let receipt = try store.confirmCandidate(jobID: task.jobId)

        XCTAssertEqual(receipt.status, .accepted)
        XCTAssertTrue(store.candidates.isEmpty)
        XCTAssertEqual(store.conversationProjections.first?.segments.map(\.id), ["segment-1"])
        XCTAssertEqual(store.topicProjections.first?.topic.name, "User topic")
        XCTAssertEqual(store.topicProjections.first?.findings.map(\.id), ["finding-1"])
        XCTAssertEqual(
            Set(store.formalConversationProjections.map(\.conversationId)),
            ["conversation-1"]
        )
        XCTAssertEqual(
            store.conversationProjections.first?.segments.first?.sourceMessages,
            store.topicProjections.first?.segments.first?.sourceMessages
        )
        XCTAssertEqual(
            store.conversationProjections.first?.findings.first?.sourceMessages,
            store.topicProjections.first?.findings.first?.sourceMessages
        )
        XCTAssertEqual(store.sourceMessage(for: source)?.content, "Source message")
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
                    topicTarget: .new(id: "topic-1", name: "Candidate topic"),
                    sourceMessages: [source]
                )
            ],
            findings: [],
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

    func message(id: String, content: String) -> ChatConversationMessage {
        ChatConversationMessage(
            id: id,
            role: .user,
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
}
