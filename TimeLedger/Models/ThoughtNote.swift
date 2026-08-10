import Foundation
import SwiftData


@Model
final class ThoughtNote {
    @Attribute(.unique) var id: UUID
    var body: String
    var capturedAt: Date
    var anchorAt: Date
    var linkedEntryId: UUID?
    var linkSource: String
    var createdAt: Date
    var updatedAt: Date

    var linkSourceEnum: ThoughtLinkSource {
        ThoughtLinkSource(rawValue: linkSource) ?? .none
    }

    init(
        id: UUID = UUID(),
        body: String,
        capturedAt: Date = Date(),
        anchorAt: Date? = nil,
        linkedEntryId: UUID? = nil,
        linkSource: ThoughtLinkSource = .none,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.body = body
        self.capturedAt = capturedAt
        self.anchorAt = anchorAt ?? capturedAt
        self.linkedEntryId = linkedEntryId
        self.linkSource = linkSource.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
