import Foundation
import SwiftData

enum TimeEntryStatus: String, CaseIterable {
    case draft
    case confirmed
}

@Model
final class TimeEntry {
    @Attribute(.unique) var id: UUID
    var projectId: UUID
    var projectNameSnapshot: String
    var categoryNameSnapshot: String
    var startAt: Date
    var endAt: Date
    var note: String
    var status: String
    var createdAt: Date
    var updatedAt: Date

    var durationSeconds: TimeInterval {
        max(0, endAt.timeIntervalSince(startAt))
    }

    var durationMinutesRounded: Int {
        Int((durationSeconds / 60).rounded())
    }

    var entryStatus: TimeEntryStatus {
        TimeEntryStatus(rawValue: status) ?? .draft
    }

    init(
        id: UUID = UUID(),
        projectId: UUID,
        projectNameSnapshot: String,
        categoryNameSnapshot: String,
        startAt: Date,
        endAt: Date,
        note: String = "",
        status: TimeEntryStatus = .draft,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.projectNameSnapshot = projectNameSnapshot
        self.categoryNameSnapshot = categoryNameSnapshot
        self.startAt = startAt
        self.endAt = endAt
        self.note = note
        self.status = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
