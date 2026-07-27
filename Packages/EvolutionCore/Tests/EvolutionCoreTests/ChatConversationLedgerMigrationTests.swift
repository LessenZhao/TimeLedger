import Foundation
import XCTest
@testable import EvolutionCore

final class ChatConversationLedgerMigrationTests: XCTestCase {
    func testMigratesV1FindingToLockedDistilledAssetWithoutLosingReceipts() throws {
        let legacy = try makeLegacyLedgerData()
        let migrated = try ChatConversationLedgerMigrator().migrateV1(
            data: legacy,
            migratedAt: "2026-07-27T00:00:00Z"
        )

        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.topics.count, 1)
        XCTAssertEqual(migrated.segments.count, 1)
        XCTAssertEqual(migrated.assets.count, 1)
        XCTAssertEqual(migrated.assets[0].kind, .viewpointKnowledge)
        XCTAssertEqual(migrated.assets[0].subtype, "历史结论")
        XCTAssertEqual(migrated.assets[0].versions[0].textSnapshot, "旧版正式结论")
        XCTAssertEqual(migrated.assets[0].versions[0].preservation, .distilled)
        XCTAssertTrue(migrated.assets[0].isHighlighted)
        XCTAssertEqual(migrated.assets[0].note, "保留备注")
        XCTAssertEqual(migrated.processedRevisions.count, 1)
        XCTAssertEqual(migrated.receipts.map(\.status), [.accepted])
        XCTAssertEqual(migrated.segments[0].title, "旧主题")
        XCTAssertEqual(
            migrated.segments[0].summary,
            "由旧版会话账本迁移；打开原文查看完整上下文。"
        )
        XCTAssertTrue(migrated.assets[0].versions[0].sourceSpans.isEmpty)
        XCTAssertEqual(migrated.assets[0].uses, [.review])
    }

    func testInspectDetectsMissingCurrentV1AndUnsupported() throws {
        let migrator = ChatConversationLedgerMigrator()
        XCTAssertEqual(try migrator.inspect(data: nil), .missing)

        let v2 = ChatConversationLedgerDocument.empty
        let v2Data = try JSONEncoder().encode(v2)
        XCTAssertEqual(try migrator.inspect(data: v2Data), .current)

        let legacy = try makeLegacyLedgerData()
        XCTAssertEqual(try migrator.inspect(data: legacy), .requiresV1Migration)

        let unsupported = #"{"schemaVersion":3,"topics":[]}"#.data(using: .utf8)!
        XCTAssertEqual(try migrator.inspect(data: unsupported), .unsupported(3))
    }

    func testBackupThenMigratePreservesHashAndCounts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatLedgerMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = EvolutionLedgerLayout(rootURL: root.appendingPathComponent("Personal Evolution"))
        try layout.ensureDirectories()
        let legacy = try makeLegacyLedgerData()
        try legacy.write(to: layout.chatConversationLedgerFileURL, options: .atomic)
        let originalHash = ContentHasher.hash(String(decoding: legacy, as: UTF8.self))

        let ledger = ChatConversationLedger(layout: layout)
        let backupURL = root.appendingPathComponent("chatgpt-ledger.v1-backup.json")
        let migrated = try ledger.migrateLegacyLedger(backupURL: backupURL)

        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.assets.count, 1)
        let backupData = try Data(contentsOf: backupURL)
        XCTAssertEqual(ContentHasher.hash(String(decoding: backupData, as: UTF8.self)), originalHash)
        let reloaded = try ledger.load()
        XCTAssertEqual(reloaded.topics.count, 1)
        XCTAssertEqual(reloaded.segments.count, 1)
        XCTAssertEqual(reloaded.assets.count, 1)
        XCTAssertEqual(reloaded.receipts.count, 1)
        XCTAssertEqual(reloaded.processedRevisions.count, 1)
    }

    func testMigrateLegacyRejectsWhenAlreadyV2() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatLedgerMigrationV2-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = EvolutionLedgerLayout(rootURL: root.appendingPathComponent("Personal Evolution"))
        try layout.ensureDirectories()
        try JSONChatConversationLedgerStore(layout: layout).save(.empty)
        let ledger = ChatConversationLedger(layout: layout)
        let backupURL = root.appendingPathComponent("backup.json")
        XCTAssertThrowsError(try ledger.migrateLegacyLedger(backupURL: backupURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }
}

private func makeLegacyLedgerData() throws -> Data {
    let fixture = LegacyV1LedgerFixture(
        schemaVersion: 1,
        topics: [
            LegacyV1Topic(id: "topic-1", name: "旧主题", isUserLocked: false),
        ],
        segments: [
            LegacyV1Segment(
                id: "segment-1",
                conversationId: "conversation-1",
                topicId: "topic-1",
                sourceMessages: [
                    LegacyV1MessageRef(conversationId: "conversation-1", messageId: "message-1"),
                ],
                isUserLocked: false
            ),
        ],
        findings: [
            LegacyV1Finding(
                id: "finding-1",
                topicId: "topic-1",
                body: "旧版正式结论",
                sourceMessages: [
                    LegacyV1MessageRef(conversationId: "conversation-1", messageId: "message-1"),
                ]
            ),
        ],
        processedRevisions: [
            LegacyV1ProcessedRevision(
                conversationId: "conversation-1",
                messageId: "message-1",
                contentHash: ContentHasher.hash("body"),
                taskId: "job-1"
            ),
        ],
        marks: [
            LegacyV1Mark(findingId: "finding-1", isHighlighted: true, note: "保留备注"),
        ],
        receipts: [
            LegacyV1Receipt(
                jobId: "job-1",
                proposalDigest: "digest",
                status: "accepted",
                recordedAt: "2026-07-01T00:00:00Z",
                reason: nil
            ),
        ],
        updatedAt: "2026-07-01T00:00:00Z"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(fixture)
}

private struct LegacyV1LedgerFixture: Codable {
    var schemaVersion: Int
    var topics: [LegacyV1Topic]
    var segments: [LegacyV1Segment]
    var findings: [LegacyV1Finding]
    var processedRevisions: [LegacyV1ProcessedRevision]
    var marks: [LegacyV1Mark]
    var receipts: [LegacyV1Receipt]
    var updatedAt: String
}

private struct LegacyV1Topic: Codable {
    var id: String
    var name: String
    var isUserLocked: Bool
}

private struct LegacyV1Segment: Codable {
    var id: String
    var conversationId: String
    var topicId: String
    var sourceMessages: [LegacyV1MessageRef]
    var isUserLocked: Bool
}

private struct LegacyV1Finding: Codable {
    var id: String
    var topicId: String
    var body: String
    var sourceMessages: [LegacyV1MessageRef]
}

private struct LegacyV1MessageRef: Codable {
    var conversationId: String
    var messageId: String
}

private struct LegacyV1ProcessedRevision: Codable {
    var conversationId: String
    var messageId: String
    var contentHash: String
    var taskId: String
}

private struct LegacyV1Mark: Codable {
    var findingId: String
    var isHighlighted: Bool
    var note: String?
}

private struct LegacyV1Receipt: Codable {
    var jobId: String
    var proposalDigest: String
    var status: String
    var recordedAt: String
    var reason: String?
}
