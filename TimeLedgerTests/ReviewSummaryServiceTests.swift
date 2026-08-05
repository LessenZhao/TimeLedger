import Foundation
import SwiftData
import Testing
@testable import TimeLedger

struct ReviewSummaryServiceTests {
    @Test func draftIsExcludedFromFormalTotalAndReportedAsPending() throws {
        let context = try makeContext()
        insertEntry(context, start: "2026-07-08 09:00", end: "2026-07-08 10:00", status: .confirmed)
        insertEntry(context, start: "2026-07-08 10:00", end: "2026-07-08 10:30", status: .draft)

        let summary = try service(context).summary(
            period: .day,
            anchorDate: date("2026-07-08 12:00"),
            now: date("2026-07-08 12:00")
        )

        #expect(summary.confirmedDuration == 3_600)
        #expect(summary.pendingDuration == 1_800)
        #expect(summary.pendingCount == 1)
    }

    @Test func crossMidnightEntryIsSlicedByNaturalDayAndBucket() throws {
        let context = try makeContext()
        insertEntry(context, start: "2026-07-08 23:30", end: "2026-07-09 00:30", status: .confirmed)

        let first = try service(context).summary(
            period: .day,
            anchorDate: date("2026-07-08 12:00"),
            now: date("2026-07-10 12:00")
        )
        let second = try service(context).summary(
            period: .day,
            anchorDate: date("2026-07-09 12:00"),
            now: date("2026-07-10 12:00")
        )

        #expect(first.confirmedDuration == 1_800)
        #expect(second.confirmedDuration == 1_800)
        #expect(first.timeBuckets.last?.confirmedDuration == 1_800)
        #expect(second.timeBuckets.first?.confirmedDuration == 1_800)
    }

    @Test func projectRenameKeepsProjectIdentityAndUsesCurrentName() throws {
        let context = try makeContext()
        let projectId = UUID()
        let project = Project(id: projectId, name: "新名称", categoryName: "工作")
        context.insert(project)
        insertEntry(
            context,
            projectId: projectId,
            projectName: "旧名称",
            start: "2026-07-08 09:00",
            end: "2026-07-08 10:00",
            status: .confirmed
        )
        insertEntry(
            context,
            projectId: projectId,
            projectName: "更旧名称",
            start: "2026-07-08 10:00",
            end: "2026-07-08 11:00",
            status: .confirmed
        )

        let summary = try service(context).summary(
            period: .day,
            anchorDate: date("2026-07-08 12:00"),
            now: date("2026-07-09 12:00")
        )

        #expect(summary.projectRanking.count == 1)
        #expect(summary.projectRanking.first?.projectId == projectId)
        #expect(summary.projectRanking.first?.displayName == "新名称")
        #expect(summary.projectRanking.first?.confirmedDuration == 7_200)
    }

    @Test func unfinishedMonthComparesOnlySameElapsedLength() throws {
        let context = try makeContext()
        insertEntry(context, start: "2026-06-20 09:00", end: "2026-06-20 10:00", status: .confirmed)
        insertEntry(context, start: "2026-07-10 09:00", end: "2026-07-10 11:00", status: .confirmed)

        let summary = try service(context).summary(
            period: .month,
            anchorDate: date("2026-07-15 12:00"),
            now: date("2026-07-15 12:00")
        )

        #expect(summary.confirmedDuration == 7_200)
        #expect(summary.comparison.previousDuration == 0)
        #expect(summary.comparison.previousRange.upperBound == date("2026-06-15 12:00"))
    }

    @Test func summaryDoesNotRequireActionModels() throws {
        let schema = Schema([Project.self, TimeEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
        let projectId = UUID()
        context.insert(Project(id: projectId, name: "时间项目", categoryName: "工作"))
        insertEntry(
            context,
            projectId: projectId,
            projectName: "时间项目",
            start: "2026-07-08 08:00",
            end: "2026-07-08 09:00",
            status: .confirmed
        )

        let summary = try service(context).summary(
            period: .day,
            anchorDate: date("2026-07-08 12:00"),
            now: date("2026-07-09 00:00")
        )

        #expect(summary.projectTrends.count == 1)
        #expect(summary.projectTrends.first?.projectId == projectId)
    }

    @Test func currentIncompleteDayIsExcludedFromLongTermAnomaly() throws {
        let context = try makeContext()
        let projectId = UUID()
        context.insert(Project(id: projectId, name: "睡觉", categoryName: "生活"))
        let currentDay = date("2026-07-08 00:00")
        for offset in 1...28 {
            let start = calendar.date(byAdding: .day, value: -offset, to: currentDay)!
            context.insert(TimeEntry(
                projectId: projectId,
                projectNameSnapshot: "睡觉",
                categoryNameSnapshot: "生活",
                startAt: start,
                endAt: calendar.date(byAdding: .hour, value: 8, to: start)!,
                status: .confirmed
            ))
        }
        insertEntry(
            context,
            projectId: projectId,
            projectName: "睡觉",
            start: "2026-07-08 00:00",
            end: "2026-07-08 01:00",
            status: .confirmed
        )

        let summary = try service(context).summary(
            period: .day,
            anchorDate: date("2026-07-08 12:00"),
            now: date("2026-07-08 01:00")
        )

        #expect(summary.observations.allSatisfy { $0.kind != .longTermAnomaly })
    }

    @Test func leapYearBuilds366DailyBucketsAndTwelveMonthlyBuckets() throws {
        let context = try makeContext()

        let year = try service(context).summary(
            period: .year,
            anchorDate: date("2024-02-29 12:00"),
            now: date("2025-01-01 00:00")
        )
        let february = try service(context).summary(
            period: .month,
            anchorDate: date("2024-02-29 12:00"),
            now: date("2025-01-01 00:00")
        )

        #expect(year.timeBuckets.count == 12)
        #expect(february.timeBuckets.count == 29)
        #expect(year.range.upperBound.timeIntervalSince(year.range.lowerBound) == 366 * 86_400)
    }

    @Test func emptyDataReturnsCompleteZeroBucketsAndNoRanking() throws {
        let context = try makeContext()

        let summary = try service(context).summary(
            period: .week,
            anchorDate: date("2026-07-08 12:00"),
            now: date("2026-07-09 12:00")
        )

        #expect(summary.confirmedDuration == 0)
        #expect(summary.pendingDuration == 0)
        #expect(summary.pendingCount == 0)
        #expect(summary.timeBuckets.count == 7)
        #expect(summary.timeBuckets.allSatisfy { $0.confirmedDuration == 0 })
        #expect(summary.projectRanking.isEmpty)
        #expect(summary.projectTrends.isEmpty)
        #expect(summary.evidenceEntries.isEmpty)
        #expect(summary.observations.count == 4)
        #expect(summary.observations.allSatisfy { $0.kind == .insufficientEvidence })
    }

    // MARK: - Project trends

    @Test func projectTrendsIncludeDraftAndConfirmedWithSeparateBuckets() throws {
        let context = try makeContext()
        let alpha = UUID()
        let beta = UUID()
        context.insert(Project(id: alpha, name: "Alpha", categoryName: "工作"))
        context.insert(Project(id: beta, name: "Beta", categoryName: "工作"))

        insertEntry(context, projectId: alpha, projectName: "Alpha", start: "2026-07-08 09:00", end: "2026-07-08 11:00", status: .confirmed)
        insertEntry(context, projectId: alpha, projectName: "Alpha", start: "2026-07-08 14:00", end: "2026-07-08 14:30", status: .draft)
        insertEntry(context, projectId: beta, projectName: "Beta", start: "2026-07-08 10:00", end: "2026-07-08 10:20", status: .confirmed)

        let summary = try service(context).summary(
            period: .day,
            anchorDate: date("2026-07-08 18:00"),
            now: date("2026-07-08 18:00")
        )

        #expect(summary.projectTrends.count == 2)
        #expect(summary.projectTrends[0].projectId == alpha)
        #expect(summary.projectTrends[0].totalDuration == 9_000)
        #expect(summary.projectTrends[0].confirmedDuration == 7_200)
        #expect(summary.projectTrends[0].draftDuration == 1_800)
        #expect(summary.projectTrends[0].entryCount == 2)
        #expect(summary.projectTrends[0].draftCount == 1)
        #expect(summary.projectTrends[0].buckets.count == 24)

        let hour9 = summary.projectTrends[0].buckets.first { calendar.component(.hour, from: $0.start) == 9 }
        let hour14 = summary.projectTrends[0].buckets.first { calendar.component(.hour, from: $0.start) == 14 }
        #expect(hour9?.confirmedDuration == 3_600)
        #expect(hour9?.draftDuration == 0)
        #expect(hour14?.confirmedDuration == 0)
        #expect(hour14?.draftDuration == 1_800)
        #expect(summary.projectTrends[1].projectId == beta)
        #expect(summary.projectTrends[1].totalDuration == 1_200)
    }

    @Test func crossMidnightDedupesEntryCountInPeriodAndCountsPerBucket() throws {
        let context = try makeContext()
        let projectId = UUID()
        context.insert(Project(id: projectId, name: "跨夜", categoryName: "工作"))
        insertEntry(
            context,
            projectId: projectId,
            projectName: "跨夜",
            start: "2026-07-08 23:00",
            end: "2026-07-09 01:00",
            status: .confirmed
        )
        insertEntry(
            context,
            projectId: projectId,
            projectName: "跨夜",
            start: "2026-07-09 10:00",
            end: "2026-07-09 11:00",
            status: .confirmed
        )

        let day = try service(context).summary(
            period: .day,
            anchorDate: date("2026-07-09 12:00"),
            now: date("2026-07-10 12:00")
        )
        let week = try service(context).summary(
            period: .week,
            anchorDate: date("2026-07-09 12:00"),
            now: date("2026-07-10 12:00")
        )

        #expect(day.projectTrends.first?.entryCount == 2)
        #expect(day.projectTrends.first?.confirmedDuration == 7_200)
        let hour0 = day.projectTrends.first?.buckets.first { calendar.component(.hour, from: $0.start) == 0 }
        #expect(hour0?.entryCount == 1)
        #expect(hour0?.confirmedDuration == 3_600)

        #expect(week.projectTrends.first?.entryCount == 2)
        let wed = week.projectTrends.first?.buckets.first {
            calendar.component(.day, from: $0.start) == 8
        }
        let thu = week.projectTrends.first?.buckets.first {
            calendar.component(.day, from: $0.start) == 9
        }
        #expect(wed?.entryCount == 1)
        #expect(thu?.entryCount == 2)
    }

    @Test func unfinishedPeriodKeepsFutureZeroBuckets() throws {
        let context = try makeContext()
        let projectId = UUID()
        context.insert(Project(id: projectId, name: "进行中", categoryName: "工作"))
        insertEntry(
            context,
            projectId: projectId,
            projectName: "进行中",
            start: "2026-07-06 09:00",
            end: "2026-07-06 10:00",
            status: .confirmed
        )

        let summary = try service(context).summary(
            period: .week,
            anchorDate: date("2026-07-08 12:00"),
            now: date("2026-07-08 12:00")
        )

        #expect(summary.projectTrends.first?.buckets.count == 7)
        let future = summary.projectTrends.first?.buckets.filter { $0.start >= date("2026-07-09 00:00") }
        #expect(future?.count == 4)
        #expect(future?.allSatisfy { $0.totalDuration == 0 && $0.entryCount == 0 } == true)
        #expect(summary.projectTrends.first?.confirmedDuration == 3_600)
    }

    @Test func projectRenameMergesTrendsByProjectId() throws {
        let context = try makeContext()
        let projectId = UUID()
        context.insert(Project(id: projectId, name: "现名", categoryName: "工作"))
        insertEntry(context, projectId: projectId, projectName: "旧A", start: "2026-07-08 09:00", end: "2026-07-08 10:00", status: .confirmed)
        insertEntry(context, projectId: projectId, projectName: "旧B", start: "2026-07-08 11:00", end: "2026-07-08 12:00", status: .draft)

        let summary = try service(context).summary(
            period: .day,
            anchorDate: date("2026-07-08 18:00"),
            now: date("2026-07-08 18:00")
        )

        #expect(summary.projectTrends.count == 1)
        #expect(summary.projectTrends.first?.displayName == "现名")
        #expect(summary.projectTrends.first?.totalDuration == 7_200)
        #expect(summary.projectTrends.first?.entryCount == 2)
    }

    // MARK: - Observations

    @Test func observationsReportLargestDailyAverageIncreaseAndDecrease() throws {
        let context = try makeContext()
        let up = UUID()
        let down = UUID()
        context.insert(Project(id: up, name: "上升项", categoryName: "工作"))
        context.insert(Project(id: down, name: "下降项", categoryName: "工作"))

        // Previous week Mon 2026-06-29 .. Sun 2026-07-05
        insertEntry(context, projectId: up, projectName: "上升项", start: "2026-06-30 09:00", end: "2026-06-30 10:00", status: .confirmed)
        insertEntry(context, projectId: down, projectName: "下降项", start: "2026-06-30 09:00", end: "2026-06-30 13:00", status: .confirmed)
        // Current week Mon 2026-07-06 ...
        insertEntry(context, projectId: up, projectName: "上升项", start: "2026-07-07 09:00", end: "2026-07-07 12:00", status: .confirmed)
        insertEntry(context, projectId: down, projectName: "下降项", start: "2026-07-07 09:00", end: "2026-07-07 09:30", status: .confirmed)

        let summary = try service(context).summary(
            period: .week,
            anchorDate: date("2026-07-08 12:00"),
            now: date("2026-07-08 12:00")
        )

        let increase = summary.observations.first { $0.kind == .dailyAverageIncrease }
        let decrease = summary.observations.first { $0.kind == .dailyAverageDecrease }
        #expect(increase?.projectId == up)
        #expect(decrease?.projectId == down)
        #expect(summary.observations.count <= 4)
    }

    @Test func observationsDetectFragmentationWhenCountUpMedianDown() throws {
        let context = try makeContext()
        let frag = UUID()
        let stable = UUID()
        context.insert(Project(id: frag, name: "碎片", categoryName: "工作"))
        context.insert(Project(id: stable, name: "稳定", categoryName: "工作"))

        // Previous week: 1 long session
        insertEntry(context, projectId: frag, projectName: "碎片", start: "2026-06-30 09:00", end: "2026-06-30 12:00", status: .confirmed)
        insertEntry(context, projectId: stable, projectName: "稳定", start: "2026-06-30 09:00", end: "2026-06-30 10:00", status: .confirmed)
        // Current: 3 short sessions
        insertEntry(context, projectId: frag, projectName: "碎片", start: "2026-07-07 09:00", end: "2026-07-07 09:30", status: .confirmed)
        insertEntry(context, projectId: frag, projectName: "碎片", start: "2026-07-07 11:00", end: "2026-07-07 11:20", status: .confirmed)
        insertEntry(context, projectId: frag, projectName: "碎片", start: "2026-07-07 14:00", end: "2026-07-07 14:15", status: .confirmed)
        insertEntry(context, projectId: stable, projectName: "稳定", start: "2026-07-07 09:00", end: "2026-07-07 10:00", status: .confirmed)

        let summary = try service(context).summary(
            period: .week,
            anchorDate: date("2026-07-08 12:00"),
            now: date("2026-07-08 12:00")
        )

        let observation = summary.observations.first { $0.kind == .fragmentation }
        #expect(observation?.projectId == frag)
    }

    @Test func observationsMarkInsufficientWhenNoFragmentationPattern() throws {
        let context = try makeContext()
        let projectId = UUID()
        context.insert(Project(id: projectId, name: "无碎片", categoryName: "工作"))
        insertEntry(context, projectId: projectId, projectName: "无碎片", start: "2026-07-07 09:00", end: "2026-07-07 10:00", status: .confirmed)

        let summary = try service(context).summary(
            period: .week,
            anchorDate: date("2026-07-08 12:00"),
            now: date("2026-07-08 12:00")
        )

        let frag = summary.observations.first { $0.title.contains("碎片化") }
        #expect(frag?.kind == .insufficientEvidence)
    }

    @Test func longTermAnomalyRequiresHistoryAndFlagsOutlierDay() throws {
        let context = try makeContext()
        let projectId = UUID()
        context.insert(Project(id: projectId, name: "异常项", categoryName: "工作"))

        // 20 active days in June with ~1h each (2026-06-01 .. 06-20)
        for day in 1...20 {
            let d = String(format: "%02d", day)
            insertEntry(
                context,
                projectId: projectId,
                projectName: "异常项",
                start: "2026-06-\(d) 09:00",
                end: "2026-06-\(d) 10:00",
                status: .confirmed
            )
        }
        // Outlier on July 8: 5 hours
        insertEntry(
            context,
            projectId: projectId,
            projectName: "异常项",
            start: "2026-07-08 09:00",
            end: "2026-07-08 14:00",
            status: .confirmed
        )

        let summary = try service(context).summary(
            period: .day,
            anchorDate: date("2026-07-08 18:00"),
            now: date("2026-07-09 00:00")
        )

        let anomaly = summary.observations.first { $0.kind == .longTermAnomaly }
        #expect(anomaly?.projectId == projectId)
    }

    @Test func longTermAnomalyInsufficientWithoutEnoughHistory() throws {
        let context = try makeContext()
        let projectId = UUID()
        context.insert(Project(id: projectId, name: "短史", categoryName: "工作"))
        insertEntry(context, projectId: projectId, projectName: "短史", start: "2026-07-08 09:00", end: "2026-07-08 14:00", status: .confirmed)

        let summary = try service(context).summary(
            period: .day,
            anchorDate: date("2026-07-08 18:00"),
            now: date("2026-07-08 18:00")
        )

        let anomaly = summary.observations.first { $0.title.contains("长期异常") }
        #expect(anomaly?.kind == .insufficientEvidence)
    }

    // MARK: - Long-term detail

    @Test func longTermDetailCoversFirstEntryToNowWithRhythmAndMedian() throws {
        let context = try makeContext()
        let projectId = UUID()
        context.insert(Project(id: projectId, name: "长期", categoryName: "工作"))

        insertEntry(context, projectId: projectId, projectName: "长期", start: "2026-06-01 09:00", end: "2026-06-01 11:00", status: .confirmed)
        insertEntry(context, projectId: projectId, projectName: "长期", start: "2026-06-02 09:00", end: "2026-06-02 10:00", status: .confirmed)
        insertEntry(context, projectId: projectId, projectName: "长期", start: "2026-06-03 09:00", end: "2026-06-03 10:00", status: .confirmed)
        insertEntry(context, projectId: projectId, projectName: "长期", start: "2026-06-10 14:00", end: "2026-06-10 15:00", status: .confirmed)
        insertEntry(context, projectId: projectId, projectName: "长期", start: "2026-07-08 20:00", end: "2026-07-08 21:00", status: .draft)

        let detail = try service(context).longTermDetail(
            projectId: projectId,
            granularity: .month,
            now: date("2026-07-08 22:00")
        )

        #expect(detail != nil)
        #expect(detail?.displayName == "长期")
        #expect(detail?.firstEntryAt == date("2026-06-01 09:00"))
        #expect(detail?.cumulativeDuration == TimeInterval(6 * 3_600))
        #expect(detail?.activeDays == 5)
        #expect(detail?.medianSessionDuration == TimeInterval(3_600))
        #expect(detail?.longestConsecutiveDays == 3)
        #expect(detail?.buckets.isEmpty == false)
        #expect(detail?.rhythmMatrix.count == 7)
        #expect(detail?.rhythmMatrix.allSatisfy { $0.count == 4 } == true)

        // 2026-06-01 is Monday with firstWeekday=2 → index 0, block 1 (06-12)
        #expect((detail?.rhythmMatrix[0][1] ?? 0) >= 7_200)
        // 2026-07-08 evening block 3
        let july8Weekday = calendar.component(.weekday, from: date("2026-07-08 00:00"))
        let july8Index = (july8Weekday - calendar.firstWeekday + 7) % 7
        #expect((detail?.rhythmMatrix[july8Index][3] ?? 0) == TimeInterval(3_600))
    }

    @Test func longTermDetailSupportsDayWeekMonthGranularity() throws {
        let context = try makeContext()
        let projectId = UUID()
        context.insert(Project(id: projectId, name: "粒度", categoryName: "工作"))
        insertEntry(context, projectId: projectId, projectName: "粒度", start: "2026-06-01 09:00", end: "2026-06-01 10:00", status: .confirmed)
        insertEntry(context, projectId: projectId, projectName: "粒度", start: "2026-07-08 09:00", end: "2026-07-08 10:00", status: .confirmed)

        let day = try service(context).longTermDetail(projectId: projectId, granularity: .day, now: date("2026-07-08 18:00"))
        let week = try service(context).longTermDetail(projectId: projectId, granularity: .week, now: date("2026-07-08 18:00"))
        let month = try service(context).longTermDetail(projectId: projectId, granularity: .month, now: date("2026-07-08 18:00"))

        #expect((day?.buckets.count ?? 0) >= 38)
        #expect((week?.buckets.count ?? 0) >= 5)
        #expect((month?.buckets.count ?? 0) == 2)
    }

    @Test func longTermDetailReturnsNilForUnknownProject() throws {
        let context = try makeContext()
        let detail = try service(context).longTermDetail(projectId: UUID(), now: date("2026-07-08 12:00"))
        #expect(detail == nil)
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let schema = Schema(TimeLedgerModels.all)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private func service(_ context: ModelContext) -> ReviewSummaryService {
        ReviewSummaryService(modelContext: context, calendar: calendar)
    }

    @discardableResult
    private func insertEntry(
        _ context: ModelContext,
        projectId: UUID = UUID(),
        projectName: String = "项目",
        start: String,
        end: String,
        status: TimeEntryStatus
    ) -> TimeEntry {
        let entry = TimeEntry(
            projectId: projectId,
            projectNameSnapshot: projectName,
            categoryNameSnapshot: "分类",
            startAt: date(start),
            endAt: date(end),
            status: status
        )
        context.insert(entry)
        return entry
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.locale = Locale(identifier: "en_US_POSIX")
        value.firstWeekday = 2
        return value
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}
