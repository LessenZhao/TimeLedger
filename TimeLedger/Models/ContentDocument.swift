import Foundation
import SwiftData

enum ContentOwnerKind: String, CaseIterable, Codable, Sendable {
    case timeEntry
    case journalEntry
}

/// V3 内容模型的链接来源枚举，替代旧 ThoughtLinkSource。
enum JournalLinkSource: String, CaseIterable, Codable, Sendable {
    case none
    case auto
    case manual
}

@Model
final class ContentDocument {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var ownerKey: String
    var ownerID: UUID
    var ownerKind: String
    var body: String
    var revision: Int
    var createdAt: Date
    var updatedAt: Date

    var ownerKindEnum: ContentOwnerKind {
        ContentOwnerKind(rawValue: ownerKind) ?? .journalEntry
    }

    init(
        id: UUID = UUID(),
        ownerID: UUID,
        ownerKind: ContentOwnerKind,
        body: String = "",
        revision: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ownerID = ownerID
        self.ownerKind = ownerKind.rawValue
        self.ownerKey = Self.key(ownerID: ownerID, ownerKind: ownerKind)
        self.body = body
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func key(ownerID: UUID, ownerKind: ContentOwnerKind) -> String {
        "\(ownerKind.rawValue):\(ownerID.uuidString.lowercased())"
    }
}

@Model
final class JournalEntry {
    @Attribute(.unique) var id: UUID
    var capturedAt: Date
    var anchorAt: Date
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool = false

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        anchorAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavorite: Bool = false
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.anchorAt = anchorAt ?? capturedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
    }
}

@Model
final class JournalTimeLink {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var journalEntryID: UUID
    var timeEntryID: UUID
    var linkSource: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        journalEntryID: UUID,
        timeEntryID: UUID,
        linkSource: JournalLinkSource,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.journalEntryID = journalEntryID
        self.timeEntryID = timeEntryID
        self.linkSource = linkSource.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ContentAttachment {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var mediaMomentID: UUID
    var contentDocumentID: UUID
    var sortOrder: Int
    var state: String
    var lastError: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        contentDocumentID: UUID,
        mediaMomentID: UUID,
        sortOrder: Int = 0,
        state: ContentAttachmentState = .ready,
        lastError: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.contentDocumentID = contentDocumentID
        self.mediaMomentID = mediaMomentID
        self.sortOrder = sortOrder
        self.state = state.rawValue
        self.lastError = lastError
        self.createdAt = createdAt
    }

    var stateEnum: ContentAttachmentState {
        ContentAttachmentState(rawValue: state) ?? .failed
    }
}

enum ContentAttachmentState: String, CaseIterable, Codable, Sendable {
    case pending
    case partial
    case failed
    case ready
}

@Model
final class ContentMigrationCheckpoint {
    @Attribute(.unique) var key: String
    var completedAt: Date

    init(key: String, completedAt: Date = Date()) {
        self.key = key
        self.completedAt = completedAt
    }
}
