import Foundation
import SwiftData

@Model
final class TimeCursor {
    @Attribute(.unique) var id: UUID
    var cursorAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        cursorAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.cursorAt = cursorAt
        self.updatedAt = updatedAt
    }
}
