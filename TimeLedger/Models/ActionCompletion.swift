import Foundation
import SwiftData

@Model
final class ActionCompletion {
    @Attribute(.unique) var id: UUID
    var actionItemId: UUID
    var actionTitleSnapshot: String
    var completedAt: Date
    var dayStart: Date
    var linkedEntryId: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        actionItemId: UUID,
        actionTitleSnapshot: String,
        completedAt: Date,
        dayStart: Date,
        linkedEntryId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.actionItemId = actionItemId
        self.actionTitleSnapshot = actionTitleSnapshot
        self.completedAt = completedAt
        self.dayStart = dayStart
        self.linkedEntryId = linkedEntryId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
