import Foundation
import SwiftData

@Model
final class ThoughtMediaLink {
    @Attribute(.unique) var id: UUID
    var thoughtId: UUID
    @Attribute(.unique) var mediaMomentId: UUID
    var sortOrder: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        thoughtId: UUID,
        mediaMomentId: UUID,
        sortOrder: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.thoughtId = thoughtId
        self.mediaMomentId = mediaMomentId
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
