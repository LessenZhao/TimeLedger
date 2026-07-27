import Foundation

public enum ChatConversationLedgerSchemaState: Sendable, Equatable {
    case missing
    case current
    case requiresV1Migration
    case unsupported(Int)
}

public enum ChatConversationLedgerMigrationError: Error, Sendable, Equatable {
    case missingLedger
    case notV1
    case unsupportedSchema(Int)
    case backupHashMismatch
    case conservationFailed(String)
    case decodeFailed
}

public struct ChatConversationLedgerMigrator: Sendable {
    public init() {}

    public func inspect(data: Data?) throws -> ChatConversationLedgerSchemaState {
        guard let data else { return .missing }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatConversationLedgerMigrationError.decodeFailed
        }
        let version = root["schemaVersion"] as? Int ?? 1
        if version == 2 { return .current }
        if version == 1 { return .requiresV1Migration }
        if version > 2 { return .unsupported(version) }
        return .unsupported(version)
    }

    public func migrateV1(data: Data, migratedAt: String) throws -> ChatConversationLedgerDocument {
        let legacy = try JSONDecoder().decode(LegacyChatConversationLedgerDocument.self, from: data)
        guard legacy.schemaVersion == 1 else {
            if legacy.schemaVersion > 2 {
                throw ChatConversationLedgerMigrationError.unsupportedSchema(legacy.schemaVersion)
            }
            throw ChatConversationLedgerMigrationError.notV1
        }

        let topics = legacy.topics.map {
            ChatConversationTopic(id: $0.id, name: $0.name, isUserLocked: $0.isUserLocked)
        }
        let topicNameByID = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0.name) })
        let segments = legacy.segments.map { segment in
            ChatConversationSegment(
                id: segment.id,
                conversationId: segment.conversationId,
                topicId: segment.topicId,
                title: topicNameByID[segment.topicId] ?? segment.topicId,
                summary: "由旧版会话账本迁移；打开原文查看完整上下文。",
                sourceMessages: segment.sourceMessages.map {
                    ChatConversationMessageReference(conversationId: $0.conversationId, messageId: $0.messageId)
                },
                isUserLocked: segment.isUserLocked
            )
        }

        let marksByFinding = Dictionary(uniqueKeysWithValues: legacy.marks.map { ($0.findingId, $0) })
        let segmentsByTopic = Dictionary(grouping: segments, by: \.topicId)

        let assets: [ChatStudyAsset] = legacy.findings.map { finding in
            let mark = marksByFinding[finding.id]
            let version = ChatStudyAssetVersion(
                id: "\(finding.id)-v1",
                textSnapshot: finding.body,
                textHash: ContentHasher.hash(finding.body),
                preservation: .distilled,
                origin: .skill,
                sourceMessages: finding.sourceMessages.map {
                    ChatConversationMessageReference(conversationId: $0.conversationId, messageId: $0.messageId)
                },
                sourceSpans: [],
                supersedesVersionId: nil,
                createdAt: migratedAt
            )
            let segmentId = segmentsByTopic[finding.topicId]?.first?.id
                ?? segments.first?.id
                ?? "migrated-segment-\(finding.id)"
            return ChatStudyAsset(
                id: finding.id,
                segmentId: segmentId,
                title: finding.body,
                kind: .viewpointKnowledge,
                subtype: "历史结论",
                uses: [.review],
                versions: [version],
                currentVersionId: version.id,
                isHighlighted: mark?.isHighlighted ?? false,
                note: mark?.note,
                isUserLocked: true
            )
        }

        return ChatConversationLedgerDocument(
            schemaVersion: 2,
            topics: topics,
            segments: segments,
            assets: assets,
            processedRevisions: legacy.processedRevisions.map {
                ChatConversationProcessedRevision(
                    conversationId: $0.conversationId,
                    messageId: $0.messageId,
                    contentHash: $0.contentHash,
                    taskId: $0.taskId
                )
            },
            receipts: legacy.receipts.map {
                ChatConversationReceipt(
                    jobId: $0.jobId,
                    proposalDigest: $0.proposalDigest,
                    status: ChatConversationReceiptStatus(rawValue: $0.status) ?? .pending,
                    recordedAt: $0.recordedAt,
                    reason: $0.reason
                )
            },
            updatedAt: legacy.updatedAt
        )
    }
}

private struct LegacyChatConversationLedgerDocument: Codable {
    var schemaVersion: Int
    var topics: [LegacyTopic]
    var segments: [LegacySegment]
    var findings: [LegacyFinding]
    var processedRevisions: [LegacyProcessedRevision]
    var marks: [LegacyMark]
    var receipts: [LegacyReceipt]
    var updatedAt: String
}

private struct LegacyTopic: Codable {
    var id: String
    var name: String
    var isUserLocked: Bool
}

private struct LegacySegment: Codable {
    var id: String
    var conversationId: String
    var topicId: String
    var sourceMessages: [LegacyMessageRef]
    var isUserLocked: Bool
}

private struct LegacyFinding: Codable {
    var id: String
    var topicId: String
    var body: String
    var sourceMessages: [LegacyMessageRef]
}

private struct LegacyMessageRef: Codable {
    var conversationId: String
    var messageId: String
}

private struct LegacyProcessedRevision: Codable {
    var conversationId: String
    var messageId: String
    var contentHash: String
    var taskId: String
}

private struct LegacyMark: Codable {
    var findingId: String
    var isHighlighted: Bool
    var note: String?
}

private struct LegacyReceipt: Codable {
    var jobId: String
    var proposalDigest: String
    var status: String
    var recordedAt: String
    var reason: String?
}
