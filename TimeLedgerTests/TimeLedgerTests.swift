//
//  TimeLedgerTests.swift
//  TimeLedgerTests
//
//  Created by Lessen Zhao on 2026/7/8.
//

import Testing
import Foundation
import SwiftData
@testable import TimeLedger

struct TimeLedgerTests {
    @Test func naturalDayOverlapSplitsCrossDayEntry() throws {
        let calendar = fixedCalendar
        let entryStart = date("2026-07-07 23:58", calendar: calendar)
        let entryEnd = date("2026-07-08 00:10", calendar: calendar)
        let day = date("2026-07-08 12:00", calendar: calendar)
        let range = DateRangeService.naturalDayRange(for: day, calendar: calendar)

        let duration = DateRangeService.overlapDuration(
            entryStart: entryStart,
            entryEnd: entryEnd,
            rangeStart: range.lowerBound,
            rangeEnd: range.upperBound
        )

        #expect(duration == 10 * 60)
    }

    @Test func weekRangeSpansSevenDays() throws {
        let calendar = fixedCalendar
        // 2026-07-08 is a Wednesday; week starts on Sunday with Gregorian default
        let midWeek = date("2026-07-08 12:00", calendar: calendar)
        let range = DateRangeService.weekRange(for: midWeek, calendar: calendar)

        let expectedStart = date("2026-07-05 00:00", calendar: calendar)
        let expectedEnd = date("2026-07-12 00:00", calendar: calendar)

        #expect(range.lowerBound == expectedStart)
        #expect(range.upperBound == expectedEnd)
    }

    @Test func monthRangeSpansFullMonth() throws {
        let calendar = fixedCalendar
        let midMonth = date("2026-07-15 12:00", calendar: calendar)
        let range = DateRangeService.monthRange(for: midMonth, calendar: calendar)

        let expectedStart = date("2026-07-01 00:00", calendar: calendar)
        let expectedEnd = date("2026-08-01 00:00", calendar: calendar)

        #expect(range.lowerBound == expectedStart)
        #expect(range.upperBound == expectedEnd)
    }

    @Test func durationByProjectGroupsByProjectId() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let projectA = Project(name: "写作", categoryName: "工作")
        let projectB = Project(name: "阅读", categoryName: "学习")
        context.insert(projectA)
        context.insert(projectB)
        context.insert(TimeEntry(
            projectId: projectA.id,
            projectNameSnapshot: projectA.name,
            categoryNameSnapshot: projectA.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 09:30", calendar: calendar)
        ))
        context.insert(TimeEntry(
            projectId: projectB.id,
            projectNameSnapshot: projectB.name,
            categoryNameSnapshot: projectB.categoryName,
            startAt: date("2026-07-08 10:00", calendar: calendar),
            endAt: date("2026-07-08 10:45", calendar: calendar)
        ))
        try context.save()

        let service = TimeSummaryService(modelContext: context, calendar: calendar)
        let result = try service.durationByProject(for: date("2026-07-08 12:00", calendar: calendar))

        #expect(result[projectA.id] == 30.0 * 60)
        #expect(result[projectB.id] == 45.0 * 60)
    }

    @Test func confirmedAndDraftEntriesForDateSeparateByStatus() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "项目", categoryName: "工作")
        context.insert(project)
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 09:30", calendar: calendar),
            status: .confirmed
        ))
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 10:00", calendar: calendar),
            endAt: date("2026-07-08 10:20", calendar: calendar)
        ))
        try context.save()

        let service = TimeSummaryService(modelContext: context, calendar: calendar)
        let confirmed = try service.confirmedEntriesForDate(date("2026-07-08 12:00", calendar: calendar))
        let drafts = try service.draftEntriesForDate(date("2026-07-08 12:00", calendar: calendar))

        #expect(confirmed.count == 1)
        #expect(confirmed.first?.status == TimeEntryStatus.confirmed.rawValue)
        #expect(drafts.count == 1)
        #expect(drafts.first?.status == TimeEntryStatus.draft.rawValue)
    }

    @Test func categorySummaryForDateGroupsByCategoryName() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let projectA = Project(name: "写作", categoryName: "工作")
        let projectB = Project(name: "阅读", categoryName: "学习")
        context.insert(projectA)
        context.insert(projectB)
        context.insert(TimeEntry(
            projectId: projectA.id,
            projectNameSnapshot: projectA.name,
            categoryNameSnapshot: projectA.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 09:30", calendar: calendar)
        ))
        context.insert(TimeEntry(
            projectId: projectB.id,
            projectNameSnapshot: projectB.name,
            categoryNameSnapshot: projectB.categoryName,
            startAt: date("2026-07-08 10:00", calendar: calendar),
            endAt: date("2026-07-08 10:45", calendar: calendar)
        ))
        try context.save()

        let service = TimeSummaryService(modelContext: context, calendar: calendar)
        let summary = try service.categorySummaryForDate(date("2026-07-08 12:00", calendar: calendar))

        #expect(summary["工作"] == 30.0 * 60)
        #expect(summary["学习"] == 45.0 * 60)
    }

    @Test func projectSummaryForDateGroupsByProjectName() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let projectA = Project(name: "写作", categoryName: "工作")
        let projectB = Project(name: "阅读", categoryName: "学习")
        context.insert(projectA)
        context.insert(projectB)
        context.insert(TimeEntry(
            projectId: projectA.id,
            projectNameSnapshot: projectA.name,
            categoryNameSnapshot: projectA.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 09:30", calendar: calendar)
        ))
        context.insert(TimeEntry(
            projectId: projectB.id,
            projectNameSnapshot: projectB.name,
            categoryNameSnapshot: projectB.categoryName,
            startAt: date("2026-07-08 10:00", calendar: calendar),
            endAt: date("2026-07-08 10:15", calendar: calendar)
        ))
        try context.save()

        let service = TimeSummaryService(modelContext: context, calendar: calendar)
        let summary = try service.projectSummaryForDate(date("2026-07-08 12:00", calendar: calendar))

        #expect(summary["写作"] == 30.0 * 60)
        #expect(summary["阅读"] == 15.0 * 60)
    }

    @Test func excludeDraftFiltersOnlyConfirmed() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "项目", categoryName: "工作")
        context.insert(project)
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 09:30", calendar: calendar),
            status: .confirmed
        ))
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 10:00", calendar: calendar),
            endAt: date("2026-07-08 10:20", calendar: calendar)
        ))
        try context.save()

        let service = TimeSummaryService(modelContext: context, calendar: calendar)
        let totalWithDraft = try service.totalDurationForDate(date("2026-07-08 12:00", calendar: calendar))
        let totalConfirmedOnly = try service.totalDurationForDate(date("2026-07-08 12:00", calendar: calendar), includeDraft: false)

        #expect(totalWithDraft == 50 * 60)
        #expect(totalConfirmedOnly == 30 * 60)
    }

    @Test func quickRecordUpdatesCursorAndUndoRestoresIt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 1_600)
        let project = Project(name: "英文文章", categoryName: "阅读")

        context.insert(project)
        _ = try service.getOrCreateCursor(now: start)
        let entry = try service.quickRecord(project: project, now: end)

        #expect(entry.status == TimeEntryStatus.draft.rawValue)
        #expect(try service.getOrCreateCursor().cursorAt == end)
        #expect(try service.canUndoLastEntry())

        try service.undoLastEntry()

        #expect(try service.getOrCreateCursor().cursorAt == start)
        #expect(!(try service.canUndoLastEntry()))
    }

    @Test func timeSummaryCountsProjectDurationForToday() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "AI学习", categoryName: "学习")
        context.insert(project)
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 10:00", calendar: calendar),
            endAt: date("2026-07-08 10:20", calendar: calendar)
        ))
        try context.save()

        let service = TimeSummaryService(modelContext: context, calendar: calendar)
        let total = try service.todayDuration(
            for: project.id,
            now: date("2026-07-08 12:00", calendar: calendar)
        )

        #expect(total == 20 * 60)
    }

    @Test func recordSegmentUsesAdjustedTimesNoteAndMovesCursor() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let cursorStart = Date(timeIntervalSince1970: 1_000)
        let adjustedStart = Date(timeIntervalSince1970: 1_120)
        let adjustedEnd = Date(timeIntervalSince1970: 1_600)
        let project = Project(name: "写材料", categoryName: "工作")

        context.insert(project)
        _ = try service.getOrCreateCursor(now: cursorStart)
        let entry = try service.recordSegment(
            project: project,
            startAt: adjustedStart,
            endAt: adjustedEnd,
            note: "会议后整理"
        )

        #expect(entry.projectId == project.id)
        #expect(entry.startAt == adjustedStart)
        #expect(entry.endAt == adjustedEnd)
        #expect(entry.note == "会议后整理")
        #expect(entry.status == TimeEntryStatus.draft.rawValue)
        #expect(try service.getOrCreateCursor().cursorAt == adjustedEnd)
    }

    @Test func skipSegmentMovesCursorWithoutCreatingEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let cursorStart = Date(timeIntervalSince1970: 2_000)
        let skipEnd = Date(timeIntervalSince1970: 2_900)

        _ = try service.getOrCreateCursor(now: cursorStart)
        try service.skipSegment(to: skipEnd)

        #expect(try service.getOrCreateCursor().cursorAt == skipEnd)

        let entries = try context.fetch(FetchDescriptor<TimeEntry>())
        #expect(entries.isEmpty)
    }

    @Test func totalDurationForDateCountsNaturalDayOverlap() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "研究", categoryName: "学习")
        context.insert(project)
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-07 23:50", calendar: calendar),
            endAt: date("2026-07-08 00:20", calendar: calendar)
        ))
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 09:30", calendar: calendar)
        ))
        try context.save()

        let service = TimeSummaryService(modelContext: context, calendar: calendar)
        let total = try service.totalDurationForDate(date("2026-07-08 12:00", calendar: calendar))

        #expect(total == 50 * 60)
    }

    @Test func updateLatestDraftMovesCursorWhenEndTimeChanges() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "写作", categoryName: "工作")
        let originalStart = Date(timeIntervalSince1970: 1_000)
        let originalEnd = Date(timeIntervalSince1970: 1_600)
        let editedStart = Date(timeIntervalSince1970: 1_060)
        let editedEnd = Date(timeIntervalSince1970: 1_900)

        context.insert(project)
        _ = try service.getOrCreateCursor(now: originalStart)
        let entry = try service.quickRecord(project: project, now: originalEnd)

        try service.updateEntry(
            entry,
            project: project,
            note: "补充说明",
            startAt: editedStart,
            endAt: editedEnd
        )

        #expect(entry.startAt == editedStart)
        #expect(entry.endAt == editedEnd)
        #expect(entry.note == "补充说明")
        #expect(try service.getOrCreateCursor().cursorAt == editedEnd)
    }

    @Test func deleteLatestDraftRestoresCursorToStartTime() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "阅读", categoryName: "学习")
        let start = Date(timeIntervalSince1970: 2_000)
        let end = Date(timeIntervalSince1970: 2_900)

        context.insert(project)
        _ = try service.getOrCreateCursor(now: start)
        let entry = try service.quickRecord(project: project, now: end)

        try service.deleteDraftEntry(entry)

        #expect(try service.getOrCreateCursor().cursorAt == start)
        #expect(try context.fetch(FetchDescriptor<TimeEntry>()).isEmpty)
    }

    @Test func confirmedEntryCannotUpdateTimeInNormalEdit() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "会议", categoryName: "工作")
        let originalStart = Date(timeIntervalSince1970: 3_000)
        let originalEnd = Date(timeIntervalSince1970: 3_600)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: originalStart,
            endAt: originalEnd,
            status: .confirmed
        )

        context.insert(project)
        context.insert(entry)
        try context.save()

        try service.updateEntry(
            entry,
            project: project,
            note: "会议纪要",
            startAt: Date(timeIntervalSince1970: 3_100),
            endAt: Date(timeIntervalSince1970: 3_900)
        )

        #expect(entry.projectId == project.id)
        #expect(entry.note == "会议纪要")
        #expect(entry.startAt == originalStart)
        #expect(entry.endAt == originalEnd)
    }

    @Test func validationRejectsInvalidTimeRange() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "整理", categoryName: "工作")
        let service = ValidationService(modelContext: context)

        context.insert(project)
        try context.save()

        do {
            try service.validateEntry(
                projectId: project.id,
                startAt: Date(timeIntervalSince1970: 5_000),
                endAt: Date(timeIntervalSince1970: 5_000)
            )
            #expect(Bool(false), "endAt <= startAt should be invalid")
        } catch {
            #expect(error is ValidationError)
        }
    }

    @Test func validationRejectsMissingProject() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = ValidationService(modelContext: context)

        do {
            try service.validateEntry(
                projectId: UUID(),
                startAt: Date(timeIntervalSince1970: 5_000),
                endAt: Date(timeIntervalSince1970: 5_600)
            )
            #expect(Bool(false), "missing project should be invalid")
        } catch {
            #expect(error is ValidationError)
        }
    }

    @Test func validationRejectsOverlappingEntriesAndAllowsGaps() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "学习", categoryName: "个人")
        let service = ValidationService(modelContext: context, calendar: calendar)

        context.insert(project)
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 10:00", calendar: calendar),
            endAt: date("2026-07-08 10:30", calendar: calendar)
        ))
        try context.save()

        do {
            try service.validateEntry(
                projectId: project.id,
                startAt: date("2026-07-08 10:20", calendar: calendar),
                endAt: date("2026-07-08 10:50", calendar: calendar)
            )
            #expect(Bool(false), "overlap should be invalid")
        } catch {
            #expect(error is ValidationError)
        }

        try service.validateEntry(
            projectId: project.id,
            startAt: date("2026-07-08 10:30", calendar: calendar),
            endAt: date("2026-07-08 11:00", calendar: calendar)
        )
    }

    @Test func invalidDraftCannotBeConfirmedWithoutPartialChanges() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "项目", categoryName: "工作")
        let service = ValidationService(modelContext: context, calendar: calendar)
        let firstDraft = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 09:40", calendar: calendar)
        )
        let overlappingDraft = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:20", calendar: calendar),
            endAt: date("2026-07-08 10:00", calendar: calendar)
        )

        context.insert(project)
        context.insert(firstDraft)
        context.insert(overlappingDraft)
        try context.save()

        do {
            _ = try service.confirmDraftsForDate(date("2026-07-08 12:00", calendar: calendar))
            #expect(Bool(false), "overlapping drafts should not be confirmed")
        } catch {
            #expect(error is ValidationError)
        }

        #expect(firstDraft.status == TimeEntryStatus.draft.rawValue)
        #expect(overlappingDraft.status == TimeEntryStatus.draft.rawValue)
    }

    @Test func confirmDraftsForDateConfirmsValidDrafts() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "复盘", categoryName: "个人")
        let service = ValidationService(modelContext: context, calendar: calendar)
        let firstDraft = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 09:30", calendar: calendar)
        )
        let secondDraft = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 10:00", calendar: calendar),
            endAt: date("2026-07-08 10:20", calendar: calendar)
        )

        context.insert(project)
        context.insert(firstDraft)
        context.insert(secondDraft)
        try context.save()

        let confirmedCount = try service.confirmDraftsForDate(date("2026-07-08 12:00", calendar: calendar))

        #expect(confirmedCount == 2)
        #expect(firstDraft.status == TimeEntryStatus.confirmed.rawValue)
        #expect(secondDraft.status == TimeEntryStatus.confirmed.rawValue)
    }

    @Test func cancelConfirmationChangesStatusWithoutMovingCursor() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cursorService = TimeCursorService(modelContext: context)
        let project = Project(name: "会议", categoryName: "工作")
        let cursorAt = Date(timeIntervalSince1970: 8_000)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 6_000),
            endAt: Date(timeIntervalSince1970: 6_600),
            status: .confirmed
        )

        context.insert(project)
        context.insert(entry)
        _ = try cursorService.getOrCreateCursor(now: cursorAt)
        try context.save()

        try cursorService.cancelConfirmation(entry)

        #expect(entry.status == TimeEntryStatus.draft.rawValue)
        #expect(try cursorService.getOrCreateCursor().cursorAt == cursorAt)
    }

    @Test func shrinkingDraftStartCreatesUnknownProjectEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "写作", categoryName: "工作")
        let start = Date(timeIntervalSince1970: 10_000)
        let end = Date(timeIntervalSince1970: 10_000 + 3_600)
        let newStart = Date(timeIntervalSince1970: 10_000 + 1_800)

        context.insert(project)
        _ = try service.getOrCreateCursor(now: start)
        let entry = try service.quickRecord(project: project, now: end)

        try service.updateEntry(
            entry,
            project: project,
            note: "",
            startAt: newStart,
            endAt: end
        )

        let entries = try context.fetch(FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startAt)]))
        #expect(entries.count == 2)
        #expect(entries[0].startAt == start)
        #expect(entries[0].endAt == newStart)
        #expect(entries[0].projectNameSnapshot == SystemProject.unknownName)
        #expect(entries[0].status == TimeEntryStatus.draft.rawValue)
        #expect(entries[1].id == entry.id)
        #expect(entries[1].startAt == newStart)
        #expect(entries[1].endAt == end)
    }

    @Test func updateDraftRejectsEarlierStart() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "写作", categoryName: "工作")
        let start = Date(timeIntervalSince1970: 20_000)
        let end = Date(timeIntervalSince1970: 20_000 + 3_600)

        context.insert(project)
        _ = try service.getOrCreateCursor(now: start)
        let entry = try service.quickRecord(project: project, now: end)

        do {
            try service.updateEntry(
                entry,
                project: project,
                note: "",
                startAt: start.addingTimeInterval(-600),
                endAt: end
            )
            #expect(Bool(false), "earlier start should be rejected")
        } catch {
            #expect(error is TimeCursorError)
        }
    }

    @Test func deleteMiddleDraftPullsNextEntryStartForward() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "写作", categoryName: "工作")
        let t0 = Date(timeIntervalSince1970: 30_000)
        let t1 = Date(timeIntervalSince1970: 30_000 + 3_600)
        let t2 = Date(timeIntervalSince1970: 30_000 + 7_200)
        let t3 = Date(timeIntervalSince1970: 30_000 + 10_800)

        context.insert(project)
        try context.save()

        let first = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t0,
            endAt: t1
        )
        let middle = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t1,
            endAt: t2
        )
        let last = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t2,
            endAt: t3
        )
        context.insert(first)
        context.insert(middle)
        context.insert(last)
        _ = try service.getOrCreateCursor(now: t3)
        try context.save()

        try service.deleteDraftEntry(middle)

        #expect(last.startAt == t1)
        #expect(last.endAt == t3)
        #expect(try context.fetch(FetchDescriptor<TimeEntry>()).count == 2)
        #expect(try service.getOrCreateCursor().cursorAt == t3)
    }

    @Test func confirmAllEligibleDraftsSkipsUnknownProject() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = ValidationService(modelContext: context)
        let project = Project(name: "写作", categoryName: "工作")
        let unknown = try SystemProject.getOrCreateUnknown(modelContext: context)
        let realDraft = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 40_000),
            endAt: Date(timeIntervalSince1970: 40_600)
        )
        let unknownDraft = TimeEntry(
            projectId: unknown.id,
            projectNameSnapshot: unknown.name,
            categoryNameSnapshot: unknown.categoryName,
            startAt: Date(timeIntervalSince1970: 40_600),
            endAt: Date(timeIntervalSince1970: 41_200)
        )

        context.insert(project)
        context.insert(realDraft)
        context.insert(unknownDraft)
        try context.save()

        let count = try service.confirmAllEligibleDrafts()
        #expect(count == 1)
        #expect(realDraft.status == TimeEntryStatus.confirmed.rawValue)
        #expect(unknownDraft.status == TimeEntryStatus.draft.rawValue)
    }

    @Test func confirmAllEligibleDraftsFailsWhenOnlyUnknownRemain() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = ValidationService(modelContext: context)
        let unknown = try SystemProject.getOrCreateUnknown(modelContext: context)
        let unknownDraft = TimeEntry(
            projectId: unknown.id,
            projectNameSnapshot: unknown.name,
            categoryNameSnapshot: unknown.categoryName,
            startAt: Date(timeIntervalSince1970: 50_000),
            endAt: Date(timeIntervalSince1970: 50_600)
        )
        context.insert(unknownDraft)
        try context.save()

        do {
            _ = try service.confirmAllEligibleDrafts()
            #expect(Bool(false), "only unknown drafts should not confirm")
        } catch {
            #expect(error is ValidationError)
        }
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String, calendar: Calendar) -> Date {
        var formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(TimeLedgerModels.all)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

// MARK: - ExportService Tests

extension TimeLedgerTests {
    @Test func exportCSVProducesHeaderAndEntryRows() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "写作", categoryName: "工作")
        context.insert(project)
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 09:30", calendar: calendar),
            status: .confirmed
        ))
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 10:00", calendar: calendar),
            endAt: date("2026-07-08 10:20", calendar: calendar),
            status: .draft
        ))
        try context.save()

        let service = ExportService(modelContext: context)

        let csvAll = try service.exportCSV(onlyConfirmed: false)
        let linesAll = csvAll.components(separatedBy: "\n")
        #expect(linesAll.count == 3)
        #expect(linesAll[0].contains("date,startAt,endAt,durationMinutes,projectName,categoryName,note,status"))

        let csvConfirmed = try service.exportCSV(onlyConfirmed: true)
        let linesConfirmed = csvConfirmed.components(separatedBy: "\n")
        #expect(linesConfirmed.count == 2)
    }

    @Test func exportJSONContainsProjectsEntriesAndSettings() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "阅读", categoryName: "学习")
        context.insert(project)
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: Date(timeIntervalSince1970: 1_600),
            status: .confirmed
        ))
        let settings = AppSettings()
        context.insert(settings)
        try context.save()

        let service = ExportService(modelContext: context)
        let json = try service.exportJSON()

        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(parsed["version"] as? Int == 1)
        let projects = parsed["projects"] as? [[String: Any]]
        #expect(projects?.count == 1)
        let entries = parsed["timeEntries"] as? [[String: Any]]
        #expect(entries?.count == 1)
        let settingsDict = parsed["settings"] as? [String: Any]
        #expect(settingsDict?["exportOnlyConfirmed"] as? Bool == true)
    }

    @Test func exportMarkdownDailyReportContainsTotalAndTimeline() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "写作", categoryName: "工作")
        context.insert(project)
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 09:30", calendar: calendar),
            status: .confirmed
        ))
        try context.save()

        let service = ExportService(modelContext: context, calendar: calendar)
        let md = try service.exportMarkdownDailyReport(date: date("2026-07-08 12:00", calendar: calendar), onlyConfirmed: true)

        #expect(md.contains("时间记录日报"))
        #expect(md.contains("总计"))
        #expect(md.contains("分类汇总"))
        #expect(md.contains("项目汇总"))
        #expect(md.contains("时间线"))
        #expect(md.contains("写作"))
    }

    @Test func exportMarkdownCrossDayEntryShowsOverlap() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "研究", categoryName: "学习")
        context.insert(project)
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-07 23:50", calendar: calendar),
            endAt: date("2026-07-08 00:20", calendar: calendar),
            status: .confirmed
        ))
        try context.save()

        let service = ExportService(modelContext: context, calendar: calendar)
        let md = try service.exportMarkdownDailyReport(date: date("2026-07-08 12:00", calendar: calendar), onlyConfirmed: true)

        // The report for 07-08 should show 20 minutes (00:00-00:20 overlap)
        #expect(md.contains("20分钟"))
    }
}

// MARK: - Project Management Tests

extension TimeLedgerTests {
    @Test func archivedProjectExcludedFromActiveQuery() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let active = Project(name: "写作", categoryName: "工作")
        let archived = Project(name: "旧项目", categoryName: "工作", isArchived: true)
        context.insert(active)
        context.insert(archived)
        try context.save()

        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { !$0.isArchived })
        let activeProjects = try context.fetch(descriptor)

        #expect(activeProjects.count == 1)
        #expect(activeProjects.first?.name == "写作")
    }

    @Test func deletingProjectPreservesEntrySnapshot() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "临时项目", categoryName: "工作")
        context.insert(project)
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: Date(timeIntervalSince1970: 1_600),
            status: .confirmed
        ))
        try context.save()

        let entry = try context.fetch(FetchDescriptor<TimeEntry>()).first!
        context.delete(project)
        try context.save()

        // Entry still exists with snapshot
        let entries = try context.fetch(FetchDescriptor<TimeEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.projectNameSnapshot == "临时项目")
        #expect(entries.first?.categoryNameSnapshot == "工作")
    }

    @Test func projectValidationRejectsArchivedProject() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let archived = Project(name: "已归档", categoryName: "工作", isArchived: true)
        context.insert(archived)
        try context.save()

        let service = ValidationService(modelContext: context)

        do {
            try service.validateEntry(
                projectId: archived.id,
                startAt: Date(timeIntervalSince1970: 5_000),
                endAt: Date(timeIntervalSince1970: 5_600)
            )
            #expect(Bool(false), "archived project should be invalid")
        } catch {
            #expect(error is ValidationError)
        }
    }
}
