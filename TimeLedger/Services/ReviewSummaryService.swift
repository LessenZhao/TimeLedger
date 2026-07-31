import Foundation
import SwiftData

enum ReviewPeriod: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        case .year: "年"
        }
    }

    func range(containing date: Date, calendar: Calendar) -> Range<Date> {
        let start: Date
        let end: Date

        switch self {
        case .day:
            start = calendar.startOfDay(for: date)
            end = calendar.date(byAdding: .day, value: 1, to: start)!
        case .week:
            let dayStart = calendar.startOfDay(for: date)
            let weekday = calendar.component(.weekday, from: dayStart)
            let offset = (weekday - calendar.firstWeekday + 7) % 7
            start = calendar.date(byAdding: .day, value: -offset, to: dayStart)!
            end = calendar.date(byAdding: .day, value: 7, to: start)!
        case .month:
            start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
            end = calendar.date(byAdding: .month, value: 1, to: start)!
        case .year:
            start = calendar.date(from: calendar.dateComponents([.year], from: date))!
            end = calendar.date(byAdding: .year, value: 1, to: start)!
        }

        return start..<end
    }

    func offset(_ date: Date, by value: Int, calendar: Calendar) -> Date {
        let component: Calendar.Component = switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        return calendar.date(byAdding: component, value: value, to: date)!
    }

    func bucketRanges(in range: Range<Date>, calendar: Calendar) -> [Range<Date>] {
        let component: Calendar.Component = switch self {
        case .day: .hour
        case .week, .month: .day
        case .year: .month
        }

        var result: [Range<Date>] = []
        var start = range.lowerBound
        while start < range.upperBound {
            let proposedEnd = calendar.date(byAdding: component, value: 1, to: start)!
            let end = min(proposedEnd, range.upperBound)
            result.append(start..<end)
            start = end
        }
        return result
    }
}

struct ReviewTimeBucket: Identifiable {
    let start: Date
    let end: Date
    let confirmedDuration: TimeInterval

    var id: Date { start }
}

struct ReviewProjectSummary: Identifiable {
    let projectId: UUID
    let displayName: String
    let confirmedDuration: TimeInterval

    var id: UUID { projectId }
}

struct ReviewComparison {
    let currentRange: Range<Date>
    let previousRange: Range<Date>
    let currentDuration: TimeInterval
    let previousDuration: TimeInterval

    var delta: TimeInterval {
        currentDuration - previousDuration
    }

    var percentageChange: Double? {
        guard previousDuration > 0 else { return nil }
        return delta / previousDuration
    }
}

struct ReviewActionFootprint: Identifiable {
    let actionItemId: UUID
    let displayTitle: String
    let completionDates: [Date]
    let currentStreak: Int
    let longestStreak: Int

    var id: UUID { actionItemId }
    var completedDayCount: Int { completionDates.count }
}

struct ReviewEvidenceEntry: Identifiable {
    let entryId: UUID
    let projectId: UUID
    let projectName: String
    let startAt: Date
    let endAt: Date
    let confirmedDurationInPeriod: TimeInterval

    var id: UUID { entryId }
}

struct ReviewSummary {
    let period: ReviewPeriod
    let anchorDate: Date
    let range: Range<Date>
    let effectiveRange: Range<Date>
    let confirmedDuration: TimeInterval
    let pendingDuration: TimeInterval
    let pendingCount: Int
    let timeBuckets: [ReviewTimeBucket]
    let projectRanking: [ReviewProjectSummary]
    let comparison: ReviewComparison
    let actionFootprints: [ReviewActionFootprint]
    let evidenceEntries: [ReviewEvidenceEntry]
}

struct ReviewSummaryService {
    let modelContext: ModelContext
    var calendar: Calendar = .current

    func summary(
        period: ReviewPeriod,
        anchorDate: Date,
        now: Date = Date()
    ) throws -> ReviewSummary {
        let range = period.range(containing: anchorDate, calendar: calendar)
        let effectiveEnd = effectiveEnd(for: range, now: now)
        let effectiveRange = range.lowerBound..<effectiveEnd
        let currentEntries = try entries(overlapping: range)
        let confirmedEntries = currentEntries.filter {
            $0.status == TimeEntryStatus.confirmed.rawValue
        }
        let draftEntries = currentEntries.filter {
            $0.status == TimeEntryStatus.draft.rawValue
        }

        let confirmedDuration = duration(of: confirmedEntries, in: effectiveRange)
        let pendingDuration = duration(of: draftEntries, in: range)
        let buckets = period.bucketRanges(in: range, calendar: calendar).map { bucketRange in
            ReviewTimeBucket(
                start: bucketRange.lowerBound,
                end: bucketRange.upperBound,
                confirmedDuration: duration(of: confirmedEntries, in: bucketRange)
            )
        }

        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let projectNames = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
        let ranking = projectRanking(
            entries: confirmedEntries,
            range: effectiveRange,
            currentNames: projectNames
        )

        let previousRange = period.range(
            containing: period.offset(anchorDate, by: -1, calendar: calendar),
            calendar: calendar
        )
        let previousEffectiveEnd = comparablePreviousEnd(
            period: period,
            currentRange: range,
            currentEffectiveEnd: effectiveEnd,
            previousRange: previousRange
        )
        let previousEffectiveRange = previousRange.lowerBound..<previousEffectiveEnd
        let previousEntries = try entries(overlapping: previousEffectiveRange).filter {
            $0.status == TimeEntryStatus.confirmed.rawValue
        }
        let previousDuration = duration(of: previousEntries, in: previousEffectiveRange)
        let comparison = ReviewComparison(
            currentRange: effectiveRange,
            previousRange: previousEffectiveRange,
            currentDuration: confirmedDuration,
            previousDuration: previousDuration
        )

        let actionItems = try modelContext.fetch(FetchDescriptor<ActionItem>())
        let actionNames = Dictionary(uniqueKeysWithValues: actionItems.map { ($0.id, $0.title) })
        let allCompletions = try completions(before: effectiveEnd)
        let actionFootprints = makeActionFootprints(
            completions: allCompletions,
            displayRange: range,
            effectiveEnd: effectiveEnd,
            currentNames: actionNames
        )

        let evidence = confirmedEntries
            .compactMap { entry -> ReviewEvidenceEntry? in
                let overlap = DateRangeService.overlapDuration(
                    entryStart: entry.startAt,
                    entryEnd: entry.endAt,
                    rangeStart: effectiveRange.lowerBound,
                    rangeEnd: effectiveRange.upperBound
                )
                guard overlap > 0 else { return nil }
                return ReviewEvidenceEntry(
                    entryId: entry.id,
                    projectId: entry.projectId,
                    projectName: projectNames[entry.projectId] ?? entry.projectNameSnapshot,
                    startAt: entry.startAt,
                    endAt: entry.endAt,
                    confirmedDurationInPeriod: overlap
                )
            }
            .sorted { $0.startAt < $1.startAt }

        return ReviewSummary(
            period: period,
            anchorDate: anchorDate,
            range: range,
            effectiveRange: effectiveRange,
            confirmedDuration: confirmedDuration,
            pendingDuration: pendingDuration,
            pendingCount: draftEntries.count,
            timeBuckets: buckets,
            projectRanking: ranking,
            comparison: comparison,
            actionFootprints: actionFootprints,
            evidenceEntries: evidence
        )
    }

    private func entries(overlapping range: Range<Date>) throws -> [TimeEntry] {
        guard range.lowerBound < range.upperBound else { return [] }
        let start = range.lowerBound
        let end = range.upperBound
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { entry in
                entry.startAt < end && entry.endAt > start
            },
            sortBy: [SortDescriptor(\.startAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func completions(before end: Date) throws -> [ActionCompletion] {
        let descriptor = FetchDescriptor<ActionCompletion>(
            predicate: #Predicate { completion in
                completion.dayStart < end
            },
            sortBy: [SortDescriptor(\.dayStart)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func effectiveEnd(for range: Range<Date>, now: Date) -> Date {
        min(max(now, range.lowerBound), range.upperBound)
    }

    private func comparablePreviousEnd(
        period: ReviewPeriod,
        currentRange: Range<Date>,
        currentEffectiveEnd: Date,
        previousRange: Range<Date>
    ) -> Date {
        guard currentEffectiveEnd < currentRange.upperBound else {
            return previousRange.upperBound
        }
        let shifted = period.offset(currentEffectiveEnd, by: -1, calendar: calendar)
        return min(max(shifted, previousRange.lowerBound), previousRange.upperBound)
    }

    private func duration(of entries: [TimeEntry], in range: Range<Date>) -> TimeInterval {
        guard range.lowerBound < range.upperBound else { return 0 }
        return entries.reduce(0) { total, entry in
            total + DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                rangeStart: range.lowerBound,
                rangeEnd: range.upperBound
            )
        }
    }

    private func projectRanking(
        entries: [TimeEntry],
        range: Range<Date>,
        currentNames: [UUID: String]
    ) -> [ReviewProjectSummary] {
        var durations: [UUID: TimeInterval] = [:]
        var snapshotNames: [UUID: String] = [:]

        for entry in entries {
            let overlap = DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                rangeStart: range.lowerBound,
                rangeEnd: range.upperBound
            )
            guard overlap > 0 else { continue }
            durations[entry.projectId, default: 0] += overlap
            snapshotNames[entry.projectId] = entry.projectNameSnapshot
        }

        return durations.map { projectId, duration in
            ReviewProjectSummary(
                projectId: projectId,
                displayName: currentNames[projectId] ?? snapshotNames[projectId] ?? "未知项目",
                confirmedDuration: duration
            )
        }
        .sorted {
            if $0.confirmedDuration == $1.confirmedDuration {
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            return $0.confirmedDuration > $1.confirmedDuration
        }
    }

    private func makeActionFootprints(
        completions: [ActionCompletion],
        displayRange: Range<Date>,
        effectiveEnd: Date,
        currentNames: [UUID: String]
    ) -> [ReviewActionFootprint] {
        let grouped = Dictionary(grouping: completions, by: \.actionItemId)

        return grouped.compactMap { actionItemId, itemCompletions in
            let allDays = Array(Set(itemCompletions.map {
                calendar.startOfDay(for: $0.dayStart)
            })).sorted()
            let displayDays = allDays.filter {
                $0 >= displayRange.lowerBound && $0 < displayRange.upperBound
            }
            guard !displayDays.isEmpty else { return nil }
            let latestSnapshot = itemCompletions.max(by: { $0.completedAt < $1.completedAt })?
                .actionTitleSnapshot

            return ReviewActionFootprint(
                actionItemId: actionItemId,
                displayTitle: currentNames[actionItemId] ?? latestSnapshot ?? "未知事项",
                completionDates: displayDays,
                currentStreak: currentStreak(days: allDays, effectiveEnd: effectiveEnd),
                longestStreak: longestStreak(days: allDays)
            )
        }
        .sorted {
            if $0.completionDates.last == $1.completionDates.last {
                return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
            return ($0.completionDates.last ?? .distantPast) > ($1.completionDates.last ?? .distantPast)
        }
    }

    private func currentStreak(days: [Date], effectiveEnd: Date) -> Int {
        guard !days.isEmpty else { return 0 }
        let reference = calendar.startOfDay(
            for: effectiveEnd.addingTimeInterval(-0.001)
        )
        let daySet = Set(days)
        var cursor = reference
        var count = 0

        while daySet.contains(cursor) {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count
    }

    private func longestStreak(days: [Date]) -> Int {
        guard !days.isEmpty else { return 0 }
        var longest = 1
        var current = 1

        for index in 1..<days.count {
            let expected = calendar.date(byAdding: .day, value: 1, to: days[index - 1])!
            if days[index] == expected {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }
}
