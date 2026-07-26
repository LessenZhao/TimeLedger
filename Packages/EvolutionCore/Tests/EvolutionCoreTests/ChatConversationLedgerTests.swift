import Foundation
import XCTest
@testable import EvolutionCore

final class ChatConversationLedgerTests: XCTestCase {
    func testCreatesImmutableTaskForPendingMessagesAndAppliesProposalOnlyOnce() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(
            id: "conversation-1",
            messages: [
                fixture.message(id: "old-user", role: "user", content: "Old question"),
                fixture.message(id: "old-assistant", role: "assistant", content: "Old response"),
                fixture.message(id: "new-user", role: "user", content: "New question"),
                fixture.message(id: "new-assistant", role: "assistant", content: "New response"),
            ]
        )
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let store = JSONChatConversationLedgerStore(layout: layout)
        try store.save(ChatConversationLedgerDocument(
            processedRevisions: [
                ChatConversationProcessedRevision(
                    conversationId: "conversation-1",
                    messageId: "old-user",
                    contentHash: ContentHasher.hash("Old question"),
                    taskId: "previous-job"
                ),
                ChatConversationProcessedRevision(
                    conversationId: "conversation-1",
                    messageId: "old-assistant",
                    contentHash: ContentHasher.hash("Old response"),
                    taskId: "previous-job"
                ),
            ]
        ))
        let ledger = ChatConversationLedger(layout: layout)

        let task = try ledger.createTask(
            jobId: "job-1",
            selectedConversationIDs: ["conversation-1"],
            archiveRoot: fixture.rootURL
        )

        XCTAssertEqual(task.inputMessages.filter(\.contextOnly).map(\.messageId), ["old-user", "old-assistant"])
        XCTAssertEqual(task.inputMessages.filter { !$0.contextOnly }.map(\.messageId), ["new-user", "new-assistant"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.chatConversationJobURL(jobId: "job-1").path))

        let proposal = proposal(for: task)
        let receipt = try ledger.apply(proposal)
        let repeatedReceipt = try ledger.apply(proposal)
        let document = try ledger.load()

        XCTAssertEqual(receipt.status, .accepted)
        XCTAssertEqual(repeatedReceipt.status, .noOp)
        XCTAssertEqual(document.topics.map(\.id), ["topic:planning"])
        XCTAssertEqual(document.segments.count, 1)
        XCTAssertEqual(document.findings.count, 1)
        XCTAssertEqual(
            document.processedRevisions.map(\.messageId),
            ["old-user", "old-assistant", "new-user", "new-assistant"]
        )
    }

    func testRejectsIncompleteProposalAndRejectedTaskLeavesMessagesPending() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(
            id: "conversation-1",
            messages: [
                fixture.message(id: "message-1", role: "user", content: "One"),
                fixture.message(id: "message-2", role: "assistant", content: "Two"),
            ]
        )
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let ledger = ChatConversationLedger(layout: layout)
        let task = try ledger.createTask(jobId: "job-incomplete", selectedConversationIDs: ["conversation-1"], archiveRoot: fixture.rootURL)
        var invalid = proposal(for: task)
        invalid.segments[0].sourceMessages = [task.inputMessages[0].reference]

        XCTAssertThrowsError(try ledger.apply(invalid)) { error in
            XCTAssertEqual(error as? ChatConversationLedgerError, .incompleteInputCoverage)
        }
        XCTAssertTrue(try ledger.load().processedRevisions.isEmpty)

        let rejected = try ledger.reject(jobId: task.jobId, reason: "User declined this candidate")
        XCTAssertEqual(rejected.status, .rejected)
        XCTAssertTrue(try ledger.load().processedRevisions.isEmpty)
    }

    func testRecoversMissingReceiptAndRejectsOldTaskWithoutChangingItsMessages() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(id: "conversation-1", messages: [fixture.message(id: "one", role: "user", content: "One")])
        try fixture.writeConversation(id: "conversation-2", messages: [fixture.message(id: "two", role: "user", content: "Two")])
        try fixture.writeManifest(conversationIDs: ["conversation-1", "conversation-2"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let ledger = ChatConversationLedger(layout: layout)
        let oldTask = try ledger.createTask(jobId: "job-old", selectedConversationIDs: ["conversation-1"], archiveRoot: fixture.rootURL)
        let currentTask = try ledger.createTask(jobId: "job-current", selectedConversationIDs: ["conversation-2"], archiveRoot: fixture.rootURL)

        _ = try ledger.apply(proposal(for: currentTask))
        try FileManager.default.removeItem(at: layout.chatConversationReceiptURL(jobId: currentTask.jobId))
        let recovered = try ledger.apply(proposal(for: currentTask))

        XCTAssertEqual(recovered.status, .noOp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.chatConversationReceiptURL(jobId: currentTask.jobId).path))
        XCTAssertThrowsError(try ledger.apply(proposal(for: oldTask))) { error in
            XCTAssertEqual(error as? ChatConversationLedgerError, .staleLedger)
        }
        XCTAssertEqual(try ledger.load().processedRevisions.map(\.messageId), ["two"])
    }

    func testApplyingToExistingLockedTopicPreservesUserControl() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(id: "conversation-1", messages: [fixture.message(id: "message-1", role: "user", content: "User message")])
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let store = JSONChatConversationLedgerStore(layout: layout)
        try store.save(ChatConversationLedgerDocument(topics: [
            ChatConversationTopic(id: "topic:locked", name: "User name", isUserLocked: true),
        ]))
        let ledger = ChatConversationLedger(layout: layout)
        let task = try ledger.createTask(jobId: "job-locked", selectedConversationIDs: ["conversation-1"], archiveRoot: fixture.rootURL)

        _ = try ledger.apply(proposal(for: task, topicTarget: .existing(id: "topic:locked")))

        XCTAssertEqual(try ledger.load().topics, [
            ChatConversationTopic(id: "topic:locked", name: "User name", isUserLocked: true),
        ])
    }

    func testRejectsUnsafeJobIDAndOnlyUsesUserAssistantContextInOrder() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(
            id: "conversation-1",
            messages: [
                fixture.message(id: "old-assistant", role: "assistant", content: "Old response"),
                fixture.message(id: "old-user", role: "user", content: "Old follow-up"),
                fixture.message(id: "new-user", role: "user", content: "New question"),
            ]
        )
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let ledger = ChatConversationLedger(layout: layout)

        XCTAssertThrowsError(try ledger.createTask(
            jobId: "../outside",
            selectedConversationIDs: ["conversation-1"],
            archiveRoot: fixture.rootURL
        )) { error in
            XCTAssertEqual(error as? ChatConversationLedgerError, .invalidJobId)
        }

        let task = try ledger.createTask(
            jobId: "job-safe",
            selectedConversationIDs: ["conversation-1"],
            archiveRoot: fixture.rootURL
        )
        XCTAssertTrue(task.inputMessages.allSatisfy { !$0.contextOnly })
    }

    private func proposal(
        for task: ChatConversationProcessingTask,
        topicTarget: ChatConversationTopicTarget = .new(id: "topic:planning", name: "Planning")
    ) -> ChatConversationProposal {
        let selectedMessages = task.inputMessages.filter { !$0.contextOnly }
        return ChatConversationProposal(
            jobId: task.jobId,
            sourceDigest: task.sourceDigest,
            baseLedgerDigest: task.baseLedgerDigest,
            segments: [
                ChatConversationProposalSegment(
                    id: "segment:1",
                    topicTarget: topicTarget,
                    sourceMessages: selectedMessages.map(\.reference)
                ),
            ],
            findings: [
                ChatConversationProposalFinding(
                    id: "finding:1",
                    topicTarget: topicTarget,
                    body: "A supported finding",
                    sourceMessages: [selectedMessages[0].reference]
                ),
            ],
            ignoredMessages: []
        )
    }
}

private final class ChatLedgerFixture {
    let rootURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatConversationLedgerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func message(id: String, role: String, content: String) -> [String: String] {
        [
            "id": id,
            "role": role,
            "createdAt": "2026-07-02T00:00:00Z",
            "content": content,
        ]
    }

    func writeManifest(conversationIDs: [String]) throws {
        let manifest = Dictionary(uniqueKeysWithValues: conversationIDs.map { id in
            (id, [
                "createdAt": "2026-07-01T00:00:00Z",
                "lastActivityAt": "2026-07-02T00:00:00Z",
                "lastSnapshotFilename": "2026-07-01--\(id).md",
                "lastDataFilename": "data/conversations/\(id).json",
            ])
        })
        try writeJSON(manifest, to: rootURL.appendingPathComponent("_archive-index.json"))
    }

    func writeConversation(id: String, messages: [[String: String]]) throws {
        let fileURL = rootURL.appendingPathComponent("data/conversations/\(id).json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSON([
            "schemaVersion": 1,
            "conversationId": id,
            "title": id,
            "sourceURL": "https://chatgpt.com/c/\(id)",
            "createdAt": "2026-07-01T00:00:00Z",
            "updatedAt": "2026-07-02T00:00:00Z",
            "messages": messages,
        ], to: fileURL)
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: url)
    }
}
