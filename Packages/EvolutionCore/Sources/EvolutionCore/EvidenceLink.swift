import Foundation

public enum EvidenceLinkMethod: String, Codable, Sendable, Hashable {
    case timeOverlap
    case cwdMapping
    case projectName
    case semantic
    case manual
}

public enum EvidenceUserState: String, Codable, Sendable, Hashable {
    case suggested
    case confirmed
    case rejected
}

public struct EvidenceLink: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var timeEntryId: String
    public var contextEventId: String
    public var method: EvidenceLinkMethod
    public var confidence: Double
    public var userState: EvidenceUserState
    public var createdAt: Date
    public var updatedAt: Date
    public var schemaVersion: Int

    public init(
        id: String = UUID().uuidString,
        timeEntryId: String,
        contextEventId: String,
        method: EvidenceLinkMethod,
        confidence: Double,
        userState: EvidenceUserState = .suggested,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        schemaVersion: Int = EvolutionSchema.current
    ) {
        self.id = id
        self.timeEntryId = timeEntryId
        self.contextEventId = contextEventId
        self.method = method
        self.confidence = confidence
        self.userState = userState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
    }

    /// Manual confirmed/rejected links must not be overwritten by automatic suggestions.
    public var isUserLocked: Bool {
        userState == .confirmed || userState == .rejected || method == .manual
    }
}
