import Foundation
import XCTest
@testable import EvolutionCore

final class ChatConversationArchiveReaderTests: XCTestCase {
    func testDerivesEighteenProcessedAndFourPendingMessages() throws {
        let fixture = try ChatArchiveFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let messages = (1...22).map { index in
            fixture.message(id: "message-\(index)", content: "message body \(index)")
        }
        try fixture.writeConversation(id: "conversation-1", title: "Incremental archive", messages: messages)
        try fixture.writeManifest([
            "conversation-1": fixture.manifestEntry(dataFilename: "data/conversations/conversation-1.json"),
        ])
        let revisions = (1...18).map { index in
            ChatConversationProcessedRevision(
                conversationId: "conversation-1",
                messageId: "message-\(index)",
                contentHash: ContentHasher.hash("message body \(index)"),
                taskId: "accepted-job"
            )
        }

        let summaries = try ChatConversationArchiveReader().read(
            archiveRoot: fixture.rootURL,
            processedRevisions: revisions
        )

        let conversation = try XCTUnwrap(summaries.first)
        XCTAssertEqual(conversation.status, .partiallyProcessed)
        XCTAssertEqual(conversation.processedMessageCount, 18)
        XCTAssertEqual(conversation.pendingMessageCount, 4)
        XCTAssertEqual(conversation.pendingMessageIDs, ["message-19", "message-20", "message-21", "message-22"])
    }

    func testTreatsChangedMessageContentAsPendingAndMissingSidecarAsNeedsReexport() throws {
        let fixture = try ChatArchiveFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(
            id: "changed",
            title: "Changed message",
            messages: [fixture.message(id: "message-1", content: "new body")]
        )
        try fixture.writeManifest([
            "changed": fixture.manifestEntry(dataFilename: "data/conversations/changed.json"),
            "legacy": fixture.manifestEntry(dataFilename: nil),
        ])

        let summaries = try ChatConversationArchiveReader().read(
            archiveRoot: fixture.rootURL,
            processedRevisions: [
                ChatConversationProcessedRevision(
                    conversationId: "changed",
                    messageId: "message-1",
                    contentHash: ContentHasher.hash("old body"),
                    taskId: "accepted-job"
                ),
            ]
        )

        let changed = try XCTUnwrap(summaries.first { $0.conversationId == "changed" })
        XCTAssertEqual(changed.status, .pending)
        XCTAssertEqual(changed.processedMessageCount, 0)
        XCTAssertEqual(changed.pendingMessageCount, 1)

        let legacy = try XCTUnwrap(summaries.first { $0.conversationId == "legacy" })
        XCTAssertEqual(legacy.status, .needsReexport)
        XCTAssertEqual(legacy.issue, .missingStructuredData)
    }

    func testReportsNewAndFullyProcessedConversationFromTheSameSourceMessages() throws {
        let fixture = try ChatArchiveFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(
            id: "conversation-1",
            title: "Status transitions",
            messages: [fixture.message(id: "message-1", content: "Original body")]
        )
        try fixture.writeManifest([
            "conversation-1": fixture.manifestEntry(dataFilename: "data/conversations/conversation-1.json"),
        ])

        let newConversation = try XCTUnwrap(
            ChatConversationArchiveReader().read(archiveRoot: fixture.rootURL, processedRevisions: []).first
        )
        XCTAssertEqual(newConversation.status, .pending)
        XCTAssertEqual(newConversation.processedMessageCount, 0)
        XCTAssertEqual(newConversation.pendingMessageCount, 1)

        let fullyProcessed = try XCTUnwrap(
            ChatConversationArchiveReader().read(
                archiveRoot: fixture.rootURL,
                processedRevisions: [
                    ChatConversationProcessedRevision(
                        conversationId: "conversation-1",
                        messageId: "message-1",
                        contentHash: ContentHasher.hash("Original body"),
                        taskId: "accepted-job"
                    ),
                ]
            ).first
        )
        XCTAssertEqual(fullyProcessed.status, .processed)
        XCTAssertEqual(fullyProcessed.processedMessageCount, 1)
        XCTAssertEqual(fullyProcessed.pendingMessageCount, 0)
    }

    func testArchiveAndProcessedRevisionCodableRoundTrip() throws {
        let archive = ChatConversationArchiveFile(
            schemaVersion: 1,
            conversationId: "conversation-1",
            title: "A conversation",
            sourceURL: "https://chatgpt.com/c/conversation-1",
            createdAt: "2026-07-01T00:00:00Z",
            updatedAt: "2026-07-02T00:00:00Z",
            messages: [
                ChatConversationMessage(
                    id: "message-1",
                    role: .user,
                    createdAt: "2026-07-02T00:00:00Z",
                    content: "Original message"
                ),
            ]
        )
        let revision = ChatConversationProcessedRevision(
            conversationId: "conversation-1",
            messageId: "message-1",
            contentHash: ContentHasher.hash("Original message"),
            taskId: "job-1"
        )

        XCTAssertEqual(try JSONDecoder().decode(
            ChatConversationArchiveFile.self,
            from: JSONEncoder().encode(archive)
        ), archive)
        XCTAssertEqual(try JSONDecoder().decode(
            ChatConversationProcessedRevision.self,
            from: JSONEncoder().encode(revision)
        ), revision)
    }
}

private final class ChatArchiveFixture {
    let rootURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatConversationArchiveReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func manifestEntry(dataFilename: String?) -> [String: Any] {
        var entry: [String: Any] = [
            "createdAt": "2026-07-01T00:00:00Z",
            "lastActivityAt": "2026-07-02T00:00:00Z",
            "lastSnapshotFilename": "2026-07-01--conversation.md",
        ]
        if let dataFilename {
            entry["lastDataFilename"] = dataFilename
        }
        return entry
    }

    func message(id: String, content: String) -> [String: String] {
        [
            "id": id,
            "role": "user",
            "createdAt": "2026-07-02T00:00:00Z",
            "content": content,
        ]
    }

    func writeManifest(_ manifest: [String: [String: Any]]) throws {
        try writeJSON(manifest, to: rootURL.appendingPathComponent("_archive-index.json"))
    }

    func writeConversation(id: String, title: String, messages: [[String: String]]) throws {
        let fileURL = rootURL.appendingPathComponent("data/conversations/\(id).json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSON([
            "schemaVersion": 1,
            "conversationId": id,
            "title": title,
            "sourceURL": "https://chatgpt.com/c/\(id)",
            "createdAt": "2026-07-01T00:00:00Z",
            "updatedAt": "2026-07-02T00:00:00Z",
            "messages": messages,
        ], to: fileURL)
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        try data.write(to: url)
    }
}
