import Foundation

public enum SyncEntityType: String, Codable, Sendable, Hashable {
    case project
    case timeEntry
    case thoughtNote
    case timeCursor
    case contextThread
    case contextMessage
    case contextEvent
    case evidenceLink
    case dailyReview
}

public enum SyncOperation: String, Codable, Sendable, Hashable {
    case upsert
    case delete
}

/// Versioned file-exchange envelope. Never sync raw SQLite / SwiftData stores.
public struct SyncEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public var protocolVersion: String
    public var deviceId: String
    public var entityType: SyncEntityType
    public var entityId: String
    public var operation: SyncOperation
    public var revision: Int
    public var updatedAt: Date
    public var payload: Payload

    public init(
        protocolVersion: String = EvolutionSchema.protocolVersion,
        deviceId: String,
        entityType: SyncEntityType,
        entityId: String,
        operation: SyncOperation = .upsert,
        revision: Int,
        updatedAt: Date = Date(),
        payload: Payload
    ) {
        self.protocolVersion = protocolVersion
        self.deviceId = deviceId
        self.entityType = entityType
        self.entityId = entityId
        self.operation = operation
        self.revision = revision
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

/// Empty payload marker for delete operations when body is not needed.
public struct EmptySyncPayload: Codable, Sendable, Hashable {
    public init() {}
}

public enum SyncRevisionPolicy {
    /// Returns true if incoming should replace existing (higher revision wins; tie → newer updatedAt).
    public static func shouldAccept(
        existingRevision: Int,
        existingUpdatedAt: Date,
        incomingRevision: Int,
        incomingUpdatedAt: Date
    ) -> Bool {
        if incomingRevision > existingRevision { return true }
        if incomingRevision < existingRevision { return false }
        return incomingUpdatedAt > existingUpdatedAt
    }
}
