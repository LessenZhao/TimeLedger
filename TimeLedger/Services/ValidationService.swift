import Foundation
import SwiftData

enum ValidationError: LocalizedError {
    case invalidTimeRange
    case missingProject
    case overlappingTime

    var errorDescription: String? {
        switch self {
        case .invalidTimeRange:
            "结束时间必须晚于开始时间。"
        case .missingProject:
            "项目不存在或已归档。"
        case .overlappingTime:
            "时间记录不能重叠。"
        }
    }
}

struct ValidationService {
    let modelContext: ModelContext
    var calendar: Calendar = .current

    func validateEntry(
        projectId: UUID,
        startAt: Date,
        endAt: Date,
        excluding entryId: UUID? = nil
    ) throws {
        guard endAt > startAt else {
            throw ValidationError.invalidTimeRange
        }

        guard try projectExists(projectId) else {
            throw ValidationError.missingProject
        }

        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
        let hasOverlap = entries.contains { entry in
            entry.id != entryId
            && DateRangeService.hasOverlap(
                entryStart: startAt,
                entryEnd: endAt,
                otherStart: entry.startAt,
                otherEnd: entry.endAt
            )
        }

        if hasOverlap {
            throw ValidationError.overlappingTime
        }
    }

    @discardableResult
    func confirmDraftsForDate(_ date: Date) throws -> Int {
        let range = DateRangeService.naturalDayRange(for: date, calendar: calendar)
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { entry in
                entry.startAt < range.upperBound && entry.endAt > range.lowerBound
            },
            sortBy: [SortDescriptor(\.startAt)]
        )
        let drafts = try modelContext.fetch(descriptor).filter { entry in
            entry.status == TimeEntryStatus.draft.rawValue
        }

        for draft in drafts {
            try validateEntry(
                projectId: draft.projectId,
                startAt: draft.startAt,
                endAt: draft.endAt,
                excluding: draft.id
            )
        }

        let now = Date()
        for draft in drafts {
            draft.status = TimeEntryStatus.confirmed.rawValue
            draft.updatedAt = now
        }

        try modelContext.save()
        return drafts.count
    }

    private func projectExists(_ projectId: UUID) throws -> Bool {
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        return projects.contains { project in
            project.id == projectId && !project.isArchived
        }
    }
}
