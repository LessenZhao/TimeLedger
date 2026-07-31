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

    @Test func archivedActionStillAppearsThroughCompletionSnapshot() throws {
        let context = try makeContext()
        let itemId = UUID()
        context.insert(ActionItem(id: itemId, title: "当前名称", isArchived: true))
        context.insert(ActionCompletion(
            actionItemId: itemId,
            actionTitleSnapshot: "历史名称",
            completedAt: date("2026-07-08 08:00"),
            dayStart: date("2026-07-08 00:00")
        ))

        let summary = try service(context).summary(
            period: .week,
            anchorDate: date("2026-07-08 12:00"),
            now: date("2026-07-12 23:00")
        )

        #expect(summary.actionFootprints.count == 1)
        #expect(summary.actionFootprints.first?.displayTitle == "当前名称")
        #expect(summary.actionFootprints.first?.completionDates == [date("2026-07-08 00:00")])
    }

    @Test func missingActionUsesSnapshotAndCalculatesStreaks() throws {
        let context = try makeContext()
        let itemId = UUID()
        for day in [1, 2, 4, 5, 6] {
            context.insert(ActionCompletion(
                actionItemId: itemId,
                actionTitleSnapshot: "已删除事项",
                completedAt: date("2026-07-\(String(format: "%02d", day)) 08:00"),
                dayStart: date("2026-07-\(String(format: "%02d", day)) 00:00")
            ))
        }

        let summary = try service(context).summary(
            period: .month,
            anchorDate: date("2026-07-06 12:00"),
            now: date("2026-07-06 23:00")
        )

        #expect(summary.actionFootprints.first?.displayTitle == "已删除事项")
        #expect(summary.actionFootprints.first?.completedDayCount == 5)
        #expect(summary.actionFootprints.first?.currentStreak == 3)
        #expect(summary.actionFootprints.first?.longestStreak == 3)
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
        #expect(summary.actionFootprints.isEmpty)
        #expect(summary.evidenceEntries.isEmpty)
    }

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
