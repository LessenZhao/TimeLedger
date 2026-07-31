import Foundation
import SwiftData

@Model
final class ActionItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var sortOrder: Int
    var isArchived: Bool
    var activeCycleStartedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        activeCycleStartedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.activeCycleStartedAt = activeCycleStartedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
