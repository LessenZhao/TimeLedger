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

enum ReviewLongTermGranularity: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        }
    }
}

struct ReviewTimeBucket: Identifiable, Equatable {
    let start: Date
    let end: Date
    let confirmedDuration: TimeInterval
    let draftDuration: TimeInterval
    let entryCount: Int

    var id: Date { start }

    var totalDuration: TimeInterval {
        confirmedDuration + draftDuration
    }

    init(
        start: Date,
        end: Date,
        confirmedDuration: TimeInterval,
        draftDuration: TimeInterval = 0,
        entryCount: Int = 0
    ) {
        self.start = start
        self.end = end
        self.confirmedDuration = confirmedDuration
        self.draftDuration = draftDuration
        self.entryCount = entryCount
    }
}

struct ReviewProjectSummary: Identifiable {
    let projectId: UUID
    let displayName: String
    let confirmedDuration: TimeInterval

    var id: UUID { projectId }
}

struct ReviewProjectTrend: Identifiable, Equatable {
    let projectId: UUID
    let displayName: String
    let totalDuration: TimeInterval
    let confirmedDuration: TimeInterval
    let draftDuration: TimeInterval
    let entryCount: Int
    let draftCount: Int
    let buckets: [ReviewTimeBucket]

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

struct ReviewEvidenceEntry: Identifiable {
    let entryId: UUID
    let projectId: UUID
    let projectName: String
    let startAt: Date
    let endAt: Date
    let confirmedDurationInPeriod: TimeInterval
    let status: TimeEntryStatus

    var id: UUID { entryId }

    init(
        entryId: UUID,
        projectId: UUID,
        projectName: String,
        startAt: Date,
        endAt: Date,
        confirmedDurationInPeriod: TimeInterval,
        status: TimeEntryStatus = .confirmed
    ) {
        self.entryId = entryId
        self.projectId = projectId
        self.projectName = projectName
        self.startAt = startAt
        self.endAt = endAt
        self.confirmedDurationInPeriod = confirmedDurationInPeriod
        self.status = status
    }
}

enum ReviewObservationKind: String, Equatable {
    case dailyAverageIncrease
    case dailyAverageDecrease
    case fragmentation
    case longTermAnomaly
    case insufficientEvidence
}

struct ReviewObservation: Identifiable, Equatable {
    let id: UUID
    let kind: ReviewObservationKind
    let projectId: UUID?
    let projectName: String?
    let title: String
    let detail: String

    init(
        id: UUID = UUID(),
        kind: ReviewObservationKind,
        projectId: UUID? = nil,
        projectName: String? = nil,
        title: String,
        detail: String
    ) {
        self.id = id
        self.kind = kind
        self.projectId = projectId
        self.projectName = projectName
        self.title = title
        self.detail = detail
    }
}

struct ReviewProjectLongTerm: Equatable {
    let projectId: UUID
    let displayName: String
    let firstEntryAt: Date
    let range: Range<Date>
    let granularity: ReviewLongTermGranularity
    let cumulativeDuration: TimeInterval
    let activeDays: Int
    let medianSessionDuration: TimeInterval
    let longestConsecutiveDays: Int
    /// weekday index 0=calendar.firstWeekday … 6; block 0=00-06,1=06-12,2=12-18,3=18-24
    let rhythmMatrix: [[TimeInterval]]
    let buckets: [ReviewTimeBucket]
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
    let projectTrends: [ReviewProjectTrend]
    let observations: [ReviewObservation]
    let comparison: ReviewComparison
    let evidenceEntries: [ReviewEvidenceEntry]
}

struct ReviewSummaryService {
    let modelContext: ModelContext
    var calendar: Calendar = .current

    private static let anomalyHistoryDays = 28
    private static let anomalyMinHistoryDays = 14
    private static let anomalyMinActiveDays = 7
    private static let anomalyIQRMultiplier = 1.5
    private static let anomalyMinDeviation: TimeInterval = 30 * 60
    private static let maxObservations = 4

    func summary(
        period: ReviewPeriod,
        anchorDate: Date,
        now: Date = Date()
    ) throws -> ReviewSummary {
        let range = period.range(containing: anchorDate, calendar: calendar)
        let effectiveEnd = effectiveEnd(for: range, now: now)
        let effectiveRange = range.lowerBound..<effectiveEnd
        let bucketRanges = period.bucketRanges(in: range, calendar: calendar)

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

        let historyStart = calendar.date(
            byAdding: .day,
            value: -(Self.anomalyHistoryDays + 1),
            to: calendar.startOfDay(for: range.lowerBound)
        )!
        let fetchRange = min(historyStart, previousRange.lowerBound)..<max(range.upperBound, previousRange.upperBound)
        let allEntries = try entries(overlapping: fetchRange)

        let currentEntries = allEntries.filter {
            $0.startAt < range.upperBound && $0.endAt > range.lowerBound
        }
        let confirmedEntries = currentEntries.filter {
            $0.status == TimeEntryStatus.confirmed.rawValue
        }
        let draftEntries = currentEntries.filter {
            $0.status == TimeEntryStatus.draft.rawValue
        }

        let confirmedDuration = duration(of: confirmedEntries, in: effectiveRange)
        let pendingDuration = duration(of: draftEntries, in: range)

        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let projectNames = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })

        let timeBuckets = makeBuckets(
            entries: currentEntries,
            bucketRanges: bucketRanges,
            statsRange: effectiveRange
        )

        let ranking = projectRanking(
            entries: confirmedEntries,
            range: effectiveRange,
            currentNames: projectNames
        )

        let projectTrends = makeProjectTrends(
            entries: currentEntries,
            bucketRanges: bucketRanges,
            statsRange: effectiveRange,
            currentNames: projectNames
        )

        let previousDuration = duration(
            of: allEntries.filter {
                $0.status == TimeEntryStatus.confirmed.rawValue
                    && $0.startAt < previousEffectiveRange.upperBound
                    && $0.endAt > previousEffectiveRange.lowerBound
            },
            in: previousEffectiveRange
        )
        let comparison = ReviewComparison(
            currentRange: effectiveRange,
            previousRange: previousEffectiveRange,
            currentDuration: confirmedDuration,
            previousDuration: previousDuration
        )

        let evidence = currentEntries
            .compactMap { entry -> ReviewEvidenceEntry? in
                let overlap = DateRangeService.overlapDuration(
                    entryStart: entry.startAt,
                    entryEnd: entry.endAt,
                    rangeStart: effectiveRange.lowerBound,
                    rangeEnd: effectiveRange.upperBound
                )
                guard overlap > 0 else { return nil }
                let status = TimeEntryStatus(rawValue: entry.status) ?? .draft
                return ReviewEvidenceEntry(
                    entryId: entry.id,
                    projectId: entry.projectId,
                    projectName: projectNames[entry.projectId] ?? entry.projectNameSnapshot,
                    startAt: entry.startAt,
                    endAt: entry.endAt,
                    confirmedDurationInPeriod: overlap,
                    status: status
                )
            }
            .sorted { $0.startAt < $1.startAt }

        let observations = makeObservations(
            period: period,
            range: range,
            effectiveRange: effectiveRange,
            previousEffectiveRange: previousEffectiveRange,
            allEntries: allEntries,
            projectNames: projectNames,
            now: now
        )

        return ReviewSummary(
            period: period,
            anchorDate: anchorDate,
            range: range,
            effectiveRange: effectiveRange,
            confirmedDuration: confirmedDuration,
            pendingDuration: pendingDuration,
            pendingCount: draftEntries.count,
            timeBuckets: timeBuckets,
            projectRanking: ranking,
            projectTrends: projectTrends,
            observations: observations,
            comparison: comparison,
            evidenceEntries: evidence
        )
    }

    func longTermDetail(
        projectId: UUID,
        granularity: ReviewLongTermGranularity = .month,
        now: Date = Date()
    ) throws -> ReviewProjectLongTerm? {
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let projectNames = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })

        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { entry in
                entry.projectId == projectId
            },
            sortBy: [SortDescriptor(\.startAt)]
        )
        let entries = try modelContext.fetch(descriptor)
        guard let first = entries.first else { return nil }

        let firstDay = calendar.startOfDay(for: first.startAt)
        let endDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        )!
        let range = firstDay..<max(endDay, calendar.date(byAdding: .day, value: 1, to: firstDay)!)
        let statsRange = firstDay..<min(now, range.upperBound)

        let displayName = projectNames[projectId]
            ?? entries.last?.projectNameSnapshot
            ?? "未知项目"

        let buckets = makeLongTermBuckets(
            entries: entries,
            range: range,
            statsRange: statsRange,
            granularity: granularity
        )

        var activeDaySet = Set<Date>()
        var sessionDurations: [TimeInterval] = []
        var rhythm = Array(repeating: Array(repeating: TimeInterval(0), count: 4), count: 7)

        for entry in entries {
            let overlapTotal = DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                rangeStart: statsRange.lowerBound,
                rangeEnd: statsRange.upperBound
            )
            guard overlapTotal > 0 else { continue }
            sessionDurations.append(entry.durationSeconds)

            var cursor = max(entry.startAt, statsRange.lowerBound)
            let entryEnd = min(entry.endAt, statsRange.upperBound)
            while cursor < entryEnd {
                let dayStart = calendar.startOfDay(for: cursor)
                let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                let sliceEnd = min(entryEnd, nextDay)
                let sliceDuration = sliceEnd.timeIntervalSince(cursor)
                if sliceDuration > 0 {
                    activeDaySet.insert(dayStart)
                    let weekday = calendar.component(.weekday, from: dayStart)
                    let weekdayIndex = (weekday - calendar.firstWeekday + 7) % 7
                    accumulateRhythm(
                        matrix: &rhythm,
                        weekdayIndex: weekdayIndex,
                        start: cursor,
                        end: sliceEnd
                    )
                }
                cursor = sliceEnd
            }
        }

        let cumulative = sessionDurations.isEmpty
            ? 0
            : entries.reduce(0.0) { total, entry in
                total + DateRangeService.overlapDuration(
                    entryStart: entry.startAt,
                    entryEnd: entry.endAt,
                    rangeStart: statsRange.lowerBound,
                    rangeEnd: statsRange.upperBound
                )
            }

        return ReviewProjectLongTerm(
            projectId: projectId,
            displayName: displayName,
            firstEntryAt: first.startAt,
            range: range,
            granularity: granularity,
            cumulativeDuration: cumulative,
            activeDays: activeDaySet.count,
            medianSessionDuration: Self.median(sessionDurations),
            longestConsecutiveDays: longestConsecutiveDays(in: activeDaySet),
            rhythmMatrix: rhythm,
            buckets: buckets
        )
    }

    // MARK: - Fetch

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

    // MARK: - Buckets & aggregation

    private func makeBuckets(
        entries: [TimeEntry],
        bucketRanges: [Range<Date>],
        statsRange: Range<Date>
    ) -> [ReviewTimeBucket] {
        bucketRanges.map { bucketRange in
            let clipped = clip(bucketRange, to: statsRange)
            var confirmed: TimeInterval = 0
            var draft: TimeInterval = 0
            var count = 0
            if let clipped {
                for entry in entries {
                    let overlap = DateRangeService.overlapDuration(
                        entryStart: entry.startAt,
                        entryEnd: entry.endAt,
                        rangeStart: clipped.lowerBound,
                        rangeEnd: clipped.upperBound
                    )
                    guard overlap > 0 else { continue }
                    count += 1
                    if entry.status == TimeEntryStatus.confirmed.rawValue {
                        confirmed += overlap
                    } else if entry.status == TimeEntryStatus.draft.rawValue {
                        draft += overlap
                    }
                }
            }
            return ReviewTimeBucket(
                start: bucketRange.lowerBound,
                end: bucketRange.upperBound,
                confirmedDuration: confirmed,
                draftDuration: draft,
                entryCount: count
            )
        }
    }

    private func makeProjectTrends(
        entries: [TimeEntry],
        bucketRanges: [Range<Date>],
        statsRange: Range<Date>,
        currentNames: [UUID: String]
    ) -> [ReviewProjectTrend] {
        var byProject: [UUID: [TimeEntry]] = [:]
        var snapshotNames: [UUID: String] = [:]
        for entry in entries {
            let overlap = DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                rangeStart: statsRange.lowerBound,
                rangeEnd: statsRange.upperBound
            )
            guard overlap > 0 else { continue }
            byProject[entry.projectId, default: []].append(entry)
            snapshotNames[entry.projectId] = entry.projectNameSnapshot
        }

        return byProject.map { projectId, projectEntries in
            let uniqueIDs = Set(projectEntries.map(\.id))
            var confirmed: TimeInterval = 0
            var draft: TimeInterval = 0
            var draftIDs = Set<UUID>()
            for entry in projectEntries {
                let overlap = DateRangeService.overlapDuration(
                    entryStart: entry.startAt,
                    entryEnd: entry.endAt,
                    rangeStart: statsRange.lowerBound,
                    rangeEnd: statsRange.upperBound
                )
                guard overlap > 0 else { continue }
                if entry.status == TimeEntryStatus.confirmed.rawValue {
                    confirmed += overlap
                } else if entry.status == TimeEntryStatus.draft.rawValue {
                    draft += overlap
                    draftIDs.insert(entry.id)
                }
            }
            return ReviewProjectTrend(
                projectId: projectId,
                displayName: currentNames[projectId] ?? snapshotNames[projectId] ?? "未知项目",
                totalDuration: confirmed + draft,
                confirmedDuration: confirmed,
                draftDuration: draft,
                entryCount: uniqueIDs.count,
                draftCount: draftIDs.count,
                buckets: makeBuckets(
                    entries: projectEntries,
                    bucketRanges: bucketRanges,
                    statsRange: statsRange
                )
            )
        }
        .sorted {
            if $0.totalDuration == $1.totalDuration {
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            return $0.totalDuration > $1.totalDuration
        }
    }

    private func makeLongTermBuckets(
        entries: [TimeEntry],
        range: Range<Date>,
        statsRange: Range<Date>,
        granularity: ReviewLongTermGranularity
    ) -> [ReviewTimeBucket] {
        let component: Calendar.Component = switch granularity {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }

        var bucketRanges: [Range<Date>] = []
        var start = range.lowerBound
        if granularity == .week {
            let weekday = calendar.component(.weekday, from: start)
            let offset = (weekday - calendar.firstWeekday + 7) % 7
            start = calendar.date(byAdding: .day, value: -offset, to: start)!
        } else if granularity == .month {
            start = calendar.date(from: calendar.dateComponents([.year, .month], from: start))!
        }

        while start < range.upperBound {
            let proposedEnd = calendar.date(byAdding: component, value: 1, to: start)!
            let end = min(proposedEnd, range.upperBound)
            if end > range.lowerBound {
                let bucketStart = max(start, range.lowerBound)
                bucketRanges.append(bucketStart..<end)
            }
            start = proposedEnd
        }

        return makeBuckets(entries: entries, bucketRanges: bucketRanges, statsRange: statsRange)
    }

    private func accumulateRhythm(
        matrix: inout [[TimeInterval]],
        weekdayIndex: Int,
        start: Date,
        end: Date
    ) {
        var cursor = start
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            let hour = calendar.component(.hour, from: cursor)
            let block = min(3, hour / 6)
            let blockStartHour = block * 6
            let nextBlock = calendar.date(
                byAdding: .hour,
                value: blockStartHour + 6,
                to: dayStart
            )!
            let sliceEnd = min(end, nextBlock)
            matrix[weekdayIndex][block] += sliceEnd.timeIntervalSince(cursor)
            cursor = sliceEnd
        }
    }

    // MARK: - Observations

    private func makeObservations(
        period: ReviewPeriod,
        range: Range<Date>,
        effectiveRange: Range<Date>,
        previousEffectiveRange: Range<Date>,
        allEntries: [TimeEntry],
        projectNames: [UUID: String],
        now: Date
    ) -> [ReviewObservation] {
        var results: [ReviewObservation] = []

        let currentStats = projectPeriodStats(
            entries: allEntries,
            range: effectiveRange
        )
        let previousStats = projectPeriodStats(
            entries: allEntries,
            range: previousEffectiveRange
        )

        let currentDays = max(elapsedDays(in: effectiveRange), 1)
        let previousDays = max(elapsedDays(in: previousEffectiveRange), 1)

        let allProjectIDs = Set(currentStats.keys).union(previousStats.keys)
        var bestIncrease: (UUID, TimeInterval)?
        var bestDecrease: (UUID, TimeInterval)?

        for projectId in allProjectIDs {
            let currentAvg = (currentStats[projectId]?.totalDuration ?? 0) / Double(currentDays)
            let previousAvg = (previousStats[projectId]?.totalDuration ?? 0) / Double(previousDays)
            let delta = currentAvg - previousAvg
            if delta > 0 {
                if bestIncrease == nil || delta > bestIncrease!.1 {
                    bestIncrease = (projectId, delta)
                }
            } else if delta < 0 {
                if bestDecrease == nil || delta < bestDecrease!.1 {
                    bestDecrease = (projectId, delta)
                }
            }
        }

        if let bestIncrease, bestIncrease.1 > 0 {
            let name = name(for: bestIncrease.0, projectNames: projectNames, entries: allEntries)
            results.append(ReviewObservation(
                kind: .dailyAverageIncrease,
                projectId: bestIncrease.0,
                projectName: name,
                title: "日均增加最多：\(name)",
                detail: "较上一可比周期日均增加 \(DurationFormatter.compact(bestIncrease.1))"
            ))
        } else {
            results.append(ReviewObservation(
                kind: .insufficientEvidence,
                title: "日均增加：证据不足",
                detail: "本期与上一可比周期均无足够可比较的日均增幅项目。"
            ))
        }

        if let bestDecrease, bestDecrease.1 < 0 {
            let name = name(for: bestDecrease.0, projectNames: projectNames, entries: allEntries)
            results.append(ReviewObservation(
                kind: .dailyAverageDecrease,
                projectId: bestDecrease.0,
                projectName: name,
                title: "日均减少最多：\(name)",
                detail: "较上一可比周期日均减少 \(DurationFormatter.compact(abs(bestDecrease.1)))"
            ))
        } else {
            results.append(ReviewObservation(
                kind: .insufficientEvidence,
                title: "日均减少：证据不足",
                detail: "本期与上一可比周期均无足够可比较的日均降幅项目。"
            ))
        }

        var bestFragment: (UUID, Int, TimeInterval)?
        for projectId in allProjectIDs {
            let current = currentStats[projectId]
            let previous = previousStats[projectId]
            guard let current, let previous else { continue }
            guard current.entryCount > previous.entryCount else { continue }
            guard current.medianSession > 0 || previous.medianSession > 0 else { continue }
            guard current.medianSession < previous.medianSession else { continue }
            let countDelta = current.entryCount - previous.entryCount
            let medianDrop = previous.medianSession - current.medianSession
            if bestFragment == nil
                || countDelta > bestFragment!.1
                || (countDelta == bestFragment!.1 && medianDrop > bestFragment!.2)
            {
                bestFragment = (projectId, countDelta, medianDrop)
            }
        }

        if let bestFragment {
            let name = name(for: bestFragment.0, projectNames: projectNames, entries: allEntries)
            results.append(ReviewObservation(
                kind: .fragmentation,
                projectId: bestFragment.0,
                projectName: name,
                title: "碎片化变化最大：\(name)",
                detail: "次数 +\(bestFragment.1)，单次时长中位数下降 \(DurationFormatter.compact(bestFragment.2))"
            ))
        } else {
            results.append(ReviewObservation(
                kind: .insufficientEvidence,
                title: "碎片化：证据不足",
                detail: "没有项目同时满足次数上升且单次时长中位数下降。"
            ))
        }

        if let anomaly = detectLongTermAnomaly(
            entries: allEntries,
            effectiveRange: effectiveRange,
            projectNames: projectNames,
            now: now
        ) {
            results.append(anomaly)
        } else {
            results.append(ReviewObservation(
                kind: .insufficientEvidence,
                title: "长期异常：证据不足",
                detail: "需要至少14天历史、项目活跃≥7天，且偏离中位数≥30分钟并超出1.5×IQR。"
            ))
        }

        return Array(results.prefix(Self.maxObservations))
    }

    private struct ProjectPeriodStats {
        var totalDuration: TimeInterval = 0
        var entryIDs = Set<UUID>()
        var sessionDurations: [TimeInterval] = []

        var entryCount: Int { entryIDs.count }
        var medianSession: TimeInterval { ReviewSummaryService.median(sessionDurations) }
    }

    private func projectPeriodStats(
        entries: [TimeEntry],
        range: Range<Date>
    ) -> [UUID: ProjectPeriodStats] {
        guard range.lowerBound < range.upperBound else { return [:] }
        var result: [UUID: ProjectPeriodStats] = [:]
        for entry in entries {
            let overlap = DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                rangeStart: range.lowerBound,
                rangeEnd: range.upperBound
            )
            guard overlap > 0 else { continue }
            var stats = result[entry.projectId] ?? ProjectPeriodStats()
            stats.totalDuration += overlap
            if !stats.entryIDs.contains(entry.id) {
                stats.entryIDs.insert(entry.id)
                stats.sessionDurations.append(entry.durationSeconds)
            }
            result[entry.projectId] = stats
        }
        return result
    }

    private func detectLongTermAnomaly(
        entries: [TimeEntry],
        effectiveRange: Range<Date>,
        projectNames: [UUID: String],
        now: Date
    ) -> ReviewObservation? {
        let dayStarts = dayStarts(in: effectiveRange, now: now)
        guard let targetDay = dayStarts.last else { return nil }

        let projectIDs = Set(entries.map(\.projectId))
        var best: (UUID, Date, TimeInterval, TimeInterval)?

        for projectId in projectIDs {
            let projectEntries = entries.filter { $0.projectId == projectId }
            for day in dayStarts {
                let history = dailyTotals(
                    for: projectId,
                    entries: projectEntries,
                    before: day,
                    count: Self.anomalyHistoryDays
                )
                let nonFutureHistory = history
                let historyDaysWithData = nonFutureHistory.filter { $0 > 0 }.count
                guard nonFutureHistory.count >= Self.anomalyMinHistoryDays else { continue }
                guard historyDaysWithData >= Self.anomalyMinActiveDays else { continue }

                let med = Self.median(nonFutureHistory)
                let q1 = Self.percentile(nonFutureHistory, 0.25)
                let q3 = Self.percentile(nonFutureHistory, 0.75)
                let iqr = q3 - q1
                let upper = q3 + Self.anomalyIQRMultiplier * iqr
                let lower = q1 - Self.anomalyIQRMultiplier * iqr

                let dayTotal = duration(
                    of: projectEntries,
                    in: day..<(calendar.date(byAdding: .day, value: 1, to: day)!)
                )
                let deviation = abs(dayTotal - med)
                guard deviation >= Self.anomalyMinDeviation else { continue }
                guard dayTotal > upper || dayTotal < lower else { continue }

                if best == nil || deviation > abs(best!.2 - best!.3) {
                    best = (projectId, day, dayTotal, med)
                }
            }
            // Prefer most recent day if equal - already handled by scanning
            _ = targetDay
        }

        guard let best else { return nil }
        let name = name(for: best.0, projectNames: projectNames, entries: entries)
        let dayText = best.1.formatted(.dateTime.year().month().day())
        let direction = best.2 >= best.3 ? "偏高" : "偏低"
        return ReviewObservation(
            kind: .longTermAnomaly,
            projectId: best.0,
            projectName: name,
            title: "长期日桶异常：\(name)",
            detail: "\(dayText) 当日 \(DurationFormatter.compact(best.2))，相对前28日中位数 \(DurationFormatter.compact(best.3)) \(direction)"
        )
    }

    private func dailyTotals(
        for projectId: UUID,
        entries: [TimeEntry],
        before day: Date,
        count: Int
    ) -> [TimeInterval] {
        var result: [TimeInterval] = []
        result.reserveCapacity(count)
        for offset in (1...count).reversed() {
            let start = calendar.date(byAdding: .day, value: -offset, to: day)!
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let total = duration(
                of: entries.filter { $0.projectId == projectId },
                in: start..<end
            )
            result.append(total)
        }
        return result
    }

    private func dayStarts(in range: Range<Date>, now: Date) -> [Date] {
        let completedEnd = min(calendar.startOfDay(for: now), range.upperBound)
        guard range.lowerBound < completedEnd else { return [] }
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: range.lowerBound)
        while cursor < completedEnd {
            result.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        return result
    }

    // MARK: - Helpers (legacy + shared)

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

    private func longestConsecutiveDays(in days: Set<Date>) -> Int {
        guard !days.isEmpty else { return 0 }
        let sorted = days.sorted()
        var longest = 1
        var current = 1
        for index in 1..<sorted.count {
            let expected = calendar.date(byAdding: .day, value: 1, to: sorted[index - 1])!
            if sorted[index] == expected {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    private func elapsedDays(in range: Range<Date>) -> Int {
        guard range.lowerBound < range.upperBound else { return 0 }
        let start = calendar.startOfDay(for: range.lowerBound)
        let end = calendar.startOfDay(for: range.upperBound.addingTimeInterval(-0.001))
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, days + 1)
    }

    private func clip(_ range: Range<Date>, to limit: Range<Date>) -> Range<Date>? {
        let start = max(range.lowerBound, limit.lowerBound)
        let end = min(range.upperBound, limit.upperBound)
        guard start < end else { return nil }
        return start..<end
    }

    private func name(
        for projectId: UUID,
        projectNames: [UUID: String],
        entries: [TimeEntry]
    ) -> String {
        if let name = projectNames[projectId] { return name }
        return entries.last(where: { $0.projectId == projectId })?.projectNameSnapshot ?? "未知项目"
    }

    static func median(_ values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    static func percentile(_ values: [TimeInterval], _ p: Double) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if sorted.count == 1 { return sorted[0] }
        let clamped = min(1, max(0, p))
        let index = clamped * Double(sorted.count - 1)
        let lower = Int(index.rounded(.down))
        let upper = Int(index.rounded(.up))
        if lower == upper { return sorted[lower] }
        let weight = index - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}
