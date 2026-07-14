import Foundation

public enum DailyReviewStatus: String, Codable, Sendable, Hashable {
    case draft
    case confirmed
}

public struct DailyReview: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var date: String
    public var mainFocus: String
    public var verifiedOutputs: String
    public var keyInsights: String
    public var mainDeviation: String
    public var nextAdjustment: String
    public var evidenceIds: [String]
    public var aiDraft: String?
    public var status: DailyReviewStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var confirmedAt: Date?
    public var schemaVersion: Int

    public init(
        id: String = UUID().uuidString,
        date: String,
        mainFocus: String = "",
        verifiedOutputs: String = "",
        keyInsights: String = "",
        mainDeviation: String = "",
        nextAdjustment: String = "",
        evidenceIds: [String] = [],
        aiDraft: String? = nil,
        status: DailyReviewStatus = .draft,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        confirmedAt: Date? = nil,
        schemaVersion: Int = EvolutionSchema.current
    ) {
        self.id = id
        self.date = date
        self.mainFocus = mainFocus
        self.verifiedOutputs = verifiedOutputs
        self.keyInsights = keyInsights
        self.mainDeviation = mainDeviation
        self.nextAdjustment = nextAdjustment
        self.evidenceIds = evidenceIds
        self.aiDraft = aiDraft
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.confirmedAt = confirmedAt
        self.schemaVersion = schemaVersion
    }
}
