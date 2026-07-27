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
}
