import Foundation

/// Payloads carried inside SyncEnvelope for TimeLedger ↔ Hub exchange.
public struct ProjectSyncPayload: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var categoryName: String
    public var isArchived: Bool
    public var updatedAt: Date

    public init(id: String, name: String, categoryName: String, isArchived: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.categoryName = categoryName
        self.isArchived = isArchived
        self.updatedAt = updatedAt
    }
}

public struct TimeEntrySyncPayload: Codable, Sendable, Hashable {
    public var id: String
    public var projectId: String
    public var projectNameSnapshot: String
    public var categoryNameSnapshot: String
    public var startAt: Date
    public var endAt: Date
    public var note: String
    public var status: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        projectId: String,
        projectNameSnapshot: String,
        categoryNameSnapshot: String,
        startAt: Date,
        endAt: Date,
        note: String,
        status: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.projectId = projectId
        self.projectNameSnapshot = projectNameSnapshot
        self.categoryNameSnapshot = categoryNameSnapshot
        self.startAt = startAt
        self.endAt = endAt
        self.note = note
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ThoughtNoteSyncPayload: Codable, Sendable, Hashable {
    public var id: String
    public var body: String
    public var capturedAt: Date
    public var anchorAt: Date
    public var linkedEntryId: String?
    public var linkSource: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        body: String,
        capturedAt: Date,
        anchorAt: Date,
        linkedEntryId: String?,
        linkSource: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.body = body
        self.capturedAt = capturedAt
        self.anchorAt = anchorAt
        self.linkedEntryId = linkedEntryId
        self.linkSource = linkSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct DailyReviewSyncPayload: Codable, Sendable, Hashable {
    public var id: String
    public var date: String
    public var mainFocus: String
    public var verifiedOutputs: String
    public var mainDeviation: String
    public var nextAdjustment: String
    public var status: String
    public var confirmedAt: Date?
    public var updatedAt: Date

    public init(
        id: String,
        date: String,
        mainFocus: String,
        verifiedOutputs: String,
        mainDeviation: String,
        nextAdjustment: String,
        status: String,
        confirmedAt: Date?,
        updatedAt: Date
    ) {
        self.id = id
        self.date = date
        self.mainFocus = mainFocus
        self.verifiedOutputs = verifiedOutputs
        self.mainDeviation = mainDeviation
        self.nextAdjustment = nextAdjustment
        self.status = status
        self.confirmedAt = confirmedAt
        self.updatedAt = updatedAt
    }
}

/// File-level batch for import/export (not raw SQLite).
public struct SyncBatchFile: Codable, Sendable {
    public var protocolVersion: String
    public var deviceId: String
    public var exportedAt: Date
    public var envelopes: [AnySyncEnvelope]

    public init(
        protocolVersion: String = EvolutionSchema.protocolVersion,
        deviceId: String,
        exportedAt: Date = Date(),
        envelopes: [AnySyncEnvelope]
    ) {
        self.protocolVersion = protocolVersion
        self.deviceId = deviceId
        self.exportedAt = exportedAt
        self.envelopes = envelopes
    }
}

/// Type-erased envelope using JSON payload blob for heterogeneous batches.
public struct AnySyncEnvelope: Codable, Sendable, Hashable {
    public var protocolVersion: String
    public var deviceId: String
    public var entityType: SyncEntityType
    public var entityId: String
    public var operation: SyncOperation
    public var revision: Int
    public var updatedAt: Date
    public var payloadJSON: String

    public init(
        protocolVersion: String = EvolutionSchema.protocolVersion,
        deviceId: String,
        entityType: SyncEntityType,
        entityId: String,
        operation: SyncOperation = .upsert,
        revision: Int,
        updatedAt: Date,
        payloadJSON: String
    ) {
        self.protocolVersion = protocolVersion
        self.deviceId = deviceId
        self.entityType = entityType
        self.entityId = entityId
        self.operation = operation
        self.revision = revision
        self.updatedAt = updatedAt
        self.payloadJSON = payloadJSON
    }

    public init<T: Codable>(
        deviceId: String,
        entityType: SyncEntityType,
        entityId: String,
        operation: SyncOperation = .upsert,
        revision: Int,
        updatedAt: Date,
        payload: T
    ) throws {
        let data = try ISO8601Codec.encoder.encode(payload)
        self.init(
            deviceId: deviceId,
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            revision: revision,
            updatedAt: updatedAt,
            payloadJSON: String(data: data, encoding: .utf8) ?? "{}"
        )
    }

    public func decodePayload<T: Codable>(_ type: T.Type) throws -> T {
        guard let data = payloadJSON.data(using: .utf8) else {
            throw SyncMergeError.invalidPayload
        }
        return try ISO8601Codec.decoder.decode(T.self, from: data)
    }
}

public enum SyncMergeError: Error, Sendable {
    case invalidPayload
    case conflictLogged
}

public struct SyncMergeLogEntry: Codable, Sendable, Hashable {
    public var entityType: SyncEntityType
    public var entityId: String
    public var reason: String
    public var at: Date

    public init(entityType: SyncEntityType, entityId: String, reason: String, at: Date = Date()) {
        self.entityType = entityType
        self.entityId = entityId
        self.reason = reason
        self.at = at
    }
}

public struct RevisionedRecord: Sendable, Hashable {
    public var revision: Int
    public var updatedAt: Date

    public init(revision: Int, updatedAt: Date) {
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

public enum SyncMerger {
    /// Applies envelopes. Returns accepted entity ids and conflict logs (never silent overwrite on lower revision).
    public static func apply(
        envelopes: [AnySyncEnvelope],
        existing: [String: RevisionedRecord]
    ) -> (accepted: [AnySyncEnvelope], conflicts: [SyncMergeLogEntry], nextState: [String: RevisionedRecord]) {
        var state = existing
        var accepted: [AnySyncEnvelope] = []
        var conflicts: [SyncMergeLogEntry] = []

        for envelope in envelopes.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            let key = "\(envelope.entityType.rawValue):\(envelope.entityId)"
            if envelope.operation == .delete {
                conflicts.append(SyncMergeLogEntry(
                    entityType: envelope.entityType,
                    entityId: envelope.entityId,
                    reason: "V3 暂不跨端删除，已跳过"
                ))
                continue
            }
            if let current = state[key] {
                if SyncRevisionPolicy.shouldAccept(
                    existingRevision: current.revision,
                    existingUpdatedAt: current.updatedAt,
                    incomingRevision: envelope.revision,
                    incomingUpdatedAt: envelope.updatedAt
                ) {
                    accepted.append(envelope)
                    state[key] = RevisionedRecord(revision: envelope.revision, updatedAt: envelope.updatedAt)
                } else {
                    conflicts.append(SyncMergeLogEntry(
                        entityType: envelope.entityType,
                        entityId: envelope.entityId,
                        reason: "本地 revision 更新，拒绝覆盖"
                    ))
                }
            } else {
                accepted.append(envelope)
                state[key] = RevisionedRecord(revision: envelope.revision, updatedAt: envelope.updatedAt)
            }
        }
        return (accepted, conflicts, state)
    }
}
