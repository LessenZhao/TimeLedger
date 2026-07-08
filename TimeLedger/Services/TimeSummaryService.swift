import Foundation
import SwiftData

struct TimeSummaryService {
    let modelContext: ModelContext
    var calendar: Calendar = .current

    func todayDuration(for projectId: UUID, includeDraft: Bool = true, now: Date = Date()) throws -> TimeInterval {
        try durationForProject(projectId: projectId, date: now, includeDraft: includeDraft)
    }

    func durationForProject(projectId: UUID, date: Date, includeDraft: Bool = true) throws -> TimeInterval {
        let range = DateRangeService.naturalDayRange(for: date, calendar: calendar)
        let entries = try entriesForDate(date: date).filter { entry in
            entry.projectId == projectId && (includeDraft || entry.status == TimeEntryStatus.confirmed.rawValue)
        }

        return entries.reduce(0) { total, entry in
            total + DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                rangeStart: range.lowerBound,
                rangeEnd: range.upperBound
            )
        }
    }

    func todayDurationByProject(includeDraft: Bool = true, now: Date = Date()) throws -> [UUID: TimeInterval] {
        try durationByProject(for: now, includeDraft: includeDraft)
    }

    func durationByProject(for date: Date, includeDraft: Bool = true) throws -> [UUID: TimeInterval] {
        let entries = try entriesForDate(date: date).filter { entry in
            includeDraft || entry.status == TimeEntryStatus.confirmed.rawValue
        }
        let range = DateRangeService.naturalDayRange(for: date, calendar: calendar)

        return entries.reduce(into: [UUID: TimeInterval]()) { result, entry in
            let overlap = DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                rangeStart: range.lowerBound,
                rangeEnd: range.upperBound
            )
            result[entry.projectId, default: 0] += overlap
        }
    }

    func entriesForDate(date: Date) throws -> [TimeEntry] {
        let range = DateRangeService.naturalDayRange(for: date, calendar: calendar)
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { entry in
                entry.startAt < range.upperBound && entry.endAt > range.lowerBound
            },
            sortBy: [SortDescriptor(\.startAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    func confirmedEntriesForDate(_ date: Date) throws -> [TimeEntry] {
        try entriesForDate(date: date).filter { entry in
            entry.status == TimeEntryStatus.confirmed.rawValue
        }
    }

    func draftEntriesForDate(_ date: Date) throws -> [TimeEntry] {
        try entriesForDate(date: date).filter { entry in
            entry.status == TimeEntryStatus.draft.rawValue
        }
    }

    func totalDurationForDate(_ date: Date, includeDraft: Bool = true) throws -> TimeInterval {
        let range = DateRangeService.naturalDayRange(for: date, calendar: calendar)
        let entries = try entriesForDate(date: date).filter { entry in
            includeDraft || entry.status == TimeEntryStatus.confirmed.rawValue
        }

        return entries.reduce(0) { total, entry in
            total + DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                rangeStart: range.lowerBound,
                rangeEnd: range.upperBound
            )
        }
    }

    func categorySummaryForDate(_ date: Date, includeDraft: Bool = true) throws -> [String: TimeInterval] {
        let entries = try entriesForDate(date: date).filter { entry in
            includeDraft || entry.status == TimeEntryStatus.confirmed.rawValue
        }
        let range = DateRangeService.naturalDayRange(for: date, calendar: calendar)

        return entries.reduce(into: [String: TimeInterval]()) { result, entry in
            let overlap = DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                rangeStart: range.lowerBound,
                rangeEnd: range.upperBound
            )
            result[entry.categoryNameSnapshot, default: 0] += overlap
        }
    }

    func projectSummaryForDate(_ date: Date, includeDraft: Bool = true) throws -> [String: TimeInterval] {
        let entries = try entriesForDate(date: date).filter { entry in
            includeDraft || entry.status == TimeEntryStatus.confirmed.rawValue
        }
        let range = DateRangeService.naturalDayRange(for: date, calendar: calendar)

        return entries.reduce(into: [String: TimeInterval]()) { result, entry in
            let overlap = DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                rangeStart: range.lowerBound,
                rangeEnd: range.upperBound
            )
            result[entry.projectNameSnapshot, default: 0] += overlap
        }
    }
}
