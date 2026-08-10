import Foundation
import SwiftData

enum ValidationError: LocalizedError {
    case invalidTimeRange
    case missingProject
    case overlappingTime
    case unknownProjectNotConfirmable

    var errorDescription: String? {
        switch self {
        case .invalidTimeRange:
            "结束时间必须晚于开始时间。"
        case .missingProject:
            "项目不存在或已归档。"
        case .overlappingTime:
            "时间记录不能重叠。"
        case .unknownProjectNotConfirmable:
            "未知项目不能确认，请先选择具体项目。"
        }
    }
}

struct ValidationService {
    let modelContext: ModelContext

    private var engine: TimeLedgerEngine {
        TimeLedgerEngine(modelContext: modelContext)
    }
    var calendar: Calendar = .current

    func validateEntry(
        projectId: UUID,
        startAt: Date,
        endAt: Date,
        excluding entryId: UUID? = nil
    ) throws {
        try validateEntry(
            projectId: projectId,
            startAt: startAt,
            endAt: endAt,
            excludingEntryIds: entryId.map { [$0] } ?? []
        )
    }

    func validateEntry(
        projectId: UUID,
        startAt: Date,
        endAt: Date,
        excludingEntryIds: Set<UUID>
    ) throws {
        guard endAt > startAt else {
            throw ValidationError.invalidTimeRange
        }

        guard try projectExists(projectId) else {
            throw ValidationError.missingProject
        }

        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
        let hasOverlap = entries.contains { entry in
            !excludingEntryIds.contains(entry.id)
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
        return try confirmDrafts(drafts)
    }

    @discardableResult
    func confirmAllEligibleDrafts() throws -> Int {
        let descriptor = FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startAt)])
        let drafts = try modelContext.fetch(descriptor).filter { entry in
            entry.status == TimeEntryStatus.draft.rawValue
        }
        return try confirmDrafts(drafts)
    }

    private func confirmDrafts(_ drafts: [TimeEntry]) throws -> Int {
        guard !drafts.isEmpty else { return 0 }

        let unknowns = drafts.filter { SystemProject.isUnknownEntry($0) }
        let eligible = drafts.filter { !SystemProject.isUnknownEntry($0) }

        if eligible.isEmpty, !unknowns.isEmpty {
            throw ValidationError.unknownProjectNotConfirmable
        }

        for draft in eligible {
            try validateEntry(
                projectId: draft.projectId,
                startAt: draft.startAt,
                endAt: draft.endAt,
                excluding: draft.id
            )
        }

        let now = Date()
        for draft in eligible {
            draft.status = TimeEntryStatus.confirmed.rawValue
            draft.updatedAt = now
        }

        try engine.save()
        return eligible.count
    }

    private func projectExists(_ projectId: UUID) throws -> Bool {
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        return projects.contains { project in
            project.id == projectId && !project.isArchived
        }
    }
}
