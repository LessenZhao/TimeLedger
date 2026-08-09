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

    @Test func undoAfterSecondRecordTargetsLatestNotFirst() throws {
        /// 探针：验证 undoLastEntry() 总是撤销 createdAt 最新的草稿，
        /// 而非提示条弹出的那条。若 toast 未绑定具体 entry 引用，
        /// 在记录第二条后按撤销会删错记录。
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let start = Date(timeIntervalSince1970: 1_000)
        let mid = Date(timeIntervalSince1970: 1_600)
        let end = Date(timeIntervalSince1970: 2_200)
        let project = Project(name: "测试", categoryName: "工作")

        context.insert(project)
        _ = try service.getOrCreateCursor(now: start)

        let entryA = try service.quickRecord(project: project, now: mid)
        #expect(try service.canUndoLastEntry())

        _ = try service.quickRecord(project: project, now: end)
        #expect(try service.canUndoLastEntry())

        try service.undoLastEntry()

        let remaining = try context.fetch(FetchDescriptor<TimeEntry>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == entryA.id)
        #expect(remaining.first?.status == TimeEntryStatus.draft.rawValue)
        #expect(try service.getOrCreateCursor().cursorAt == mid)
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
            note: "会议后整理",
            now: adjustedEnd
        )

        #expect(entry.projectId == project.id)
        #expect(entry.startAt == adjustedStart)
        #expect(entry.endAt == adjustedEnd)
        let document = try #require(context.fetch(FetchDescriptor<ContentDocument>()).first { $0.ownerID == entry.id })
        #expect(document.body == "会议后整理")
        #expect(entry.note.isEmpty)
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
        let now = Date(timeIntervalSince1970: 2_000)

        context.insert(project)
        _ = try service.getOrCreateCursor(now: originalStart)
        let entry = try service.quickRecord(project: project, now: originalEnd)

        try service.updateEntry(
            entry,
            project: project,
            note: nil,
            startAt: editedStart,
            endAt: editedEnd,
            now: now
        )

        #expect(entry.startAt == editedStart)
        #expect(entry.endAt == editedEnd)
        #expect(entry.note.isEmpty)
        #expect(try service.getOrCreateCursor().cursorAt == editedEnd)
    }

    @Test func updateLatestDraftRejectsEndAfterNow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "写作", categoryName: "工作")
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 1_600)
        let now = Date(timeIntervalSince1970: 1_800)
        let futureEnd = Date(timeIntervalSince1970: 2_200)

        context.insert(project)
        _ = try service.getOrCreateCursor(now: start)
        let entry = try service.quickRecord(project: project, now: end)

        do {
            try service.updateEntry(
                entry,
                project: project,
                note: "",
                startAt: start,
                endAt: futureEnd,
                now: now
            )
            #expect(Bool(false), "end after now should be rejected")
        } catch {
            #expect(error is TimeCursorError)
        }

        #expect(entry.endAt == end)
        #expect(try service.getOrCreateCursor().cursorAt == end)
    }

    @Test func recordSegmentRejectsEndAfterNow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "写材料", categoryName: "工作")
        let cursorStart = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_500)

        context.insert(project)
        _ = try service.getOrCreateCursor(now: cursorStart)

        do {
            _ = try service.recordSegment(
                project: project,
                startAt: cursorStart,
                endAt: Date(timeIntervalSince1970: 1_800),
                now: now
            )
            #expect(Bool(false), "end after now should be rejected")
        } catch {
            #expect(error is TimeCursorError)
        }

        #expect(try context.fetch(FetchDescriptor<TimeEntry>()).isEmpty)
        #expect(try service.getOrCreateCursor().cursorAt == cursorStart)
    }

    @Test func recordSegmentRejectsStartBeforeCursor() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "写材料", categoryName: "工作")
        let cursorStart = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 2_000)

        context.insert(project)
        _ = try service.getOrCreateCursor(now: cursorStart)

        do {
            _ = try service.recordSegment(
                project: project,
                startAt: Date(timeIntervalSince1970: 900),
                endAt: Date(timeIntervalSince1970: 1_500),
                now: now
            )
            #expect(Bool(false), "start before cursor should be rejected")
        } catch {
            #expect(error is TimeCursorError)
        }

        #expect(try context.fetch(FetchDescriptor<TimeEntry>()).isEmpty)
    }

    @Test func deleteMiddleDraftLeavesGapWhenNextIsConfirmed() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "写作", categoryName: "工作")
        let t0 = Date(timeIntervalSince1970: 50_000)
        let t1 = Date(timeIntervalSince1970: 50_000 + 3_600)
        let t2 = Date(timeIntervalSince1970: 50_000 + 7_200)
        let t3 = Date(timeIntervalSince1970: 50_000 + 10_800)

        context.insert(project)
        let middle = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t0,
            endAt: t1,
            status: .draft
        )
        let confirmedNext = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t1,
            endAt: t2,
            status: .confirmed
        )
        let tail = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t2,
            endAt: t3,
            status: .draft
        )
        context.insert(middle)
        context.insert(confirmedNext)
        context.insert(tail)
        _ = try service.getOrCreateCursor(now: t3)
        try context.save()

        try service.deleteDraftEntry(middle)

        #expect(confirmedNext.startAt == t1)
        #expect(confirmedNext.endAt == t2)
        #expect(try context.fetch(FetchDescriptor<TimeEntry>()).count == 2)
        #expect(try service.getOrCreateCursor().cursorAt == t3)
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
            note: nil,
            startAt: Date(timeIntervalSince1970: 3_100),
            endAt: Date(timeIntervalSince1970: 3_900)
        )

        #expect(entry.projectId == project.id)
        #expect(entry.note.isEmpty)
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

    @Test func shrinkingDraftEndPullsNextDraftStart() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "写作", categoryName: "工作")
        let t0 = Date(timeIntervalSince1970: 40_000)
        let t1 = Date(timeIntervalSince1970: 40_000 + 3_600)
        let t2 = Date(timeIntervalSince1970: 40_000 + 7_200)
        let now = Date(timeIntervalSince1970: 40_000 + 10_800)

        context.insert(project)
        let first = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t0,
            endAt: t1
        )
        let second = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t1,
            endAt: t2
        )
        context.insert(first)
        context.insert(second)
        _ = try service.getOrCreateCursor(now: t2)
        try context.save()

        let newEnd = t1.addingTimeInterval(-60)
        try service.updateEntry(
            first,
            project: project,
            note: "",
            startAt: t0,
            endAt: newEnd,
            now: now
        )

        #expect(first.endAt == newEnd)
        #expect(second.startAt == newEnd)
        #expect(second.endAt == t2)
    }

    @Test func lengtheningDraftEndPushesNextDraftStart() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "写作", categoryName: "工作")
        let t0 = Date(timeIntervalSince1970: 50_000)
        let t1 = Date(timeIntervalSince1970: 50_000 + 3_600)
        let t2 = Date(timeIntervalSince1970: 50_000 + 7_200)
        let now = Date(timeIntervalSince1970: 50_000 + 10_800)

        context.insert(project)
        let first = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t0,
            endAt: t1
        )
        let second = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t1,
            endAt: t2
        )
        context.insert(first)
        context.insert(second)
        _ = try service.getOrCreateCursor(now: t2)
        try context.save()

        let newEnd = t1.addingTimeInterval(300)
        try service.updateEntry(
            first,
            project: project,
            note: "",
            startAt: t0,
            endAt: newEnd,
            now: now
        )

        #expect(first.endAt == newEnd)
        #expect(second.startAt == newEnd)
        #expect(second.endAt == t2)
    }

    @Test func lengtheningDraftEndDoesNotMoveConfirmedNext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "写作", categoryName: "工作")
        let t0 = Date(timeIntervalSince1970: 60_000)
        let t1 = Date(timeIntervalSince1970: 60_000 + 3_600)
        let t2 = Date(timeIntervalSince1970: 60_000 + 7_200)
        let now = Date(timeIntervalSince1970: 60_000 + 10_800)

        context.insert(project)
        let first = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t0,
            endAt: t1
        )
        let second = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t1,
            endAt: t2,
            status: .confirmed
        )
        context.insert(first)
        context.insert(second)
        _ = try service.getOrCreateCursor(now: t2)
        try context.save()

        do {
            try service.updateEntry(
                first,
                project: project,
                note: "",
                startAt: t0,
                endAt: t1.addingTimeInterval(300),
                now: now
            )
            #expect(Bool(false), "should not push confirmed next")
        } catch {
            #expect(error is TimeCursorError)
        }

        #expect(first.endAt == t1)
        #expect(second.startAt == t1)
    }

    @Test func lengtheningDraftEndRejectsSqueezingNextDraftAway() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = TimeCursorService(modelContext: context)
        let project = Project(name: "写作", categoryName: "工作")
        let t0 = Date(timeIntervalSince1970: 70_000)
        let t1 = Date(timeIntervalSince1970: 70_000 + 3_600)
        let t2 = Date(timeIntervalSince1970: 70_000 + 7_200)
        let now = Date(timeIntervalSince1970: 70_000 + 10_800)

        context.insert(project)
        let first = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t0,
            endAt: t1
        )
        let second = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: t1,
            endAt: t2
        )
        context.insert(first)
        context.insert(second)
        _ = try service.getOrCreateCursor(now: t2)
        try context.save()

        do {
            try service.updateEntry(
                first,
                project: project,
                note: "",
                startAt: t0,
                endAt: t2,
                now: now
            )
            #expect(Bool(false), "should not squeeze next draft away")
        } catch {
            #expect(error is TimeCursorError)
        }

        #expect(first.endAt == t1)
        #expect(second.startAt == t1)
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

// MARK: - Unified content contract tests

@MainActor
extension TimeLedgerTests {
    @Test func unifiedContentReadOnlyModeLoadsTextAndMediaWithoutEditingState() throws {
        let f = try UnifiedContentFixture(); let entry = f.entry(note: "冻结")
        let doc = ContentDocument(ownerID: entry.id, ownerKind: .timeEntry, body: "已有内容")
        let media = f.moment(); f.context.insert(entry); f.context.insert(doc); f.context.insert(media)
        f.context.insert(ContentAttachment(contentDocumentID: doc.id, mediaMomentID: media.id)); try f.context.save()
        let session = try ContentEditorSession.load(document: doc, modelContext: f.context)
        #expect(session.textDraft == "已有内容")
        #expect(session.workingAttachments.map(\.mediaMomentID) == [media.id])
    }

    @Test func unifiedContentCancelDoesNotPersistTextOrPendingRemoval() throws {
        let f = try UnifiedContentFixture(); let entry = f.entry(note: "冻结")
        let doc = ContentDocument(ownerID: entry.id, ownerKind: .timeEntry, body: "正式")
        let media = f.moment(); f.context.insert(entry); f.context.insert(doc); f.context.insert(media)
        f.context.insert(ContentAttachment(contentDocumentID: doc.id, mediaMomentID: media.id)); try f.context.save()
        let session = try ContentEditorSession.load(document: doc, modelContext: f.context)
        session.updateText("取消"); session.apply(.removeMedia(media.id))
        #expect(doc.body == "正式")
        #expect(try f.context.fetchCount(FetchDescriptor<ContentAttachment>()) == 1)
        #expect(entry.note == "冻结")
    }

    @Test func unifiedContentSaveCommitsTextAndNewMediaTogether() throws {
        let f = try UnifiedContentFixture(); let entry = f.entry(note: "冻结")
        let doc = ContentDocument(ownerID: entry.id, ownerKind: .timeEntry, body: "旧")
        let media = f.moment(); f.context.insert(entry); f.context.insert(doc); f.context.insert(media); try f.context.save()
        let session = try ContentEditorSession.load(document: doc, modelContext: f.context)
        session.updateText("新正文"); session.apply(.addMedia(media.id)); try SaveContent(modelContext: f.context).save(session)
        #expect(doc.body == "新正文")
        #expect(try f.context.fetch(FetchDescriptor<ContentAttachment>()).map(\.mediaMomentID) == [media.id])
        #expect(entry.note == "冻结")
    }

    @Test func unifiedContentDefersDraftCleanupUntilOuterSaveFinishes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "UnifiedDraft-\(UUID().uuidString)")
        let store = ContentEditorDraftStore(rootURL: root)
        let session = ContentEditorSession(ownerID: UUID(), contentID: UUID(), baseRevision: 1, workingBody: "工作副本", workingAttachments: [])
        try store.save(session); #expect(try store.load(ownerID: session.ownerID)?.workingBody == "工作副本")
        try store.discard(ownerID: session.ownerID); #expect(try store.load(ownerID: session.ownerID) == nil)
    }

    @Test func unifiedContentConfirmedEntrySaveChangesOnlyContent() throws {
        let f = try UnifiedContentFixture(); let projectID = UUID(); let start = f.now.addingTimeInterval(-3_600); let end = f.now.addingTimeInterval(-1_800)
        let entry = f.entry(note: "冻结", projectID: projectID, startAt: start, endAt: end, status: .confirmed)
        let doc = ContentDocument(ownerID: entry.id, ownerKind: .timeEntry, body: "之前"); f.context.insert(entry); f.context.insert(doc); try f.context.save()
        let session = try ContentEditorSession.load(document: doc, modelContext: f.context); session.updateText("只改内容"); try SaveContent(modelContext: f.context).save(session)
        #expect(doc.body == "只改内容"); #expect(entry.projectId == projectID); #expect(entry.startAt == start); #expect(entry.endAt == end); #expect(entry.status == TimeEntryStatus.confirmed.rawValue)
    }

    @Test func unifiedContentJournalCancelPreservesBodyAndMediaLink() throws {
        let f = try UnifiedContentFixture(); let journal = JournalEntry(capturedAt: f.now)
        let doc = ContentDocument(ownerID: journal.id, ownerKind: .journalEntry, body: "原随记"); let media = f.moment()
        f.context.insert(journal); f.context.insert(doc); f.context.insert(media); f.context.insert(ContentAttachment(contentDocumentID: doc.id, mediaMomentID: media.id)); try f.context.save()
        let session = try ContentEditorSession.load(document: doc, modelContext: f.context); session.updateText("取消"); session.apply(.removeMedia(media.id))
        #expect(doc.body == "原随记"); #expect(try f.context.fetchCount(FetchDescriptor<ContentAttachment>()) == 1); #expect(try f.context.fetchCount(FetchDescriptor<MediaMoment>()) == 1)
    }

    @Test func unifiedContentSaveFailureKeepsOriginalAndRecoverableDraft() throws {
        let f = try UnifiedContentFixture(); let entry = f.entry(note: "冻结")
        let doc = ContentDocument(ownerID: entry.id, ownerKind: .timeEntry, body: "正式"); f.context.insert(entry); f.context.insert(doc); try f.context.save()
        let stale = try ContentEditorSession.load(document: doc, modelContext: f.context); stale.updateText("工作副本"); doc.revision += 1; doc.body = "更新版本"; try f.context.save()
        #expect(throws: SaveContentError.revisionConflict) { try SaveContent(modelContext: f.context).save(stale) }
        #expect(stale.workingBody == "工作副本"); #expect(doc.body == "更新版本")
    }

    @Test func removingEntryMediaDetachesCardButKeepsMediaMoment() throws {
        let f = try UnifiedContentFixture(); let entry = f.entry(note: ""); let doc = ContentDocument(ownerID: entry.id, ownerKind: .timeEntry); let media = f.moment()
        f.context.insert(entry); f.context.insert(doc); f.context.insert(media); f.context.insert(ContentAttachment(contentDocumentID: doc.id, mediaMomentID: media.id)); try f.context.save()
        let session = try ContentEditorSession.load(document: doc, modelContext: f.context); session.apply(.removeMedia(media.id)); try SaveContent(modelContext: f.context).save(session)
        #expect(try f.context.fetchCount(FetchDescriptor<ContentAttachment>()) == 0); #expect(try f.context.fetchCount(FetchDescriptor<MediaMoment>()) == 1)
    }

    @Test func removingJournalMediaDetachesLinkButKeepsMediaMoment() throws {
        let f = try UnifiedContentFixture(); let journal = JournalEntry(capturedAt: f.now); let doc = ContentDocument(ownerID: journal.id, ownerKind: .journalEntry); let media = f.moment()
        f.context.insert(journal); f.context.insert(doc); f.context.insert(media); f.context.insert(ContentAttachment(contentDocumentID: doc.id, mediaMomentID: media.id)); try f.context.save()
        let session = try ContentEditorSession.load(document: doc, modelContext: f.context); session.apply(.removeMedia(media.id)); try SaveContent(modelContext: f.context).save(session)
        #expect(try f.context.fetchCount(FetchDescriptor<ContentAttachment>()) == 0); #expect(try f.context.fetchCount(FetchDescriptor<MediaMoment>()) == 1)
    }

    @Test func newTimeEntryRetryDoesNotCreateDuplicateDocument() throws {
        let f = try UnifiedContentFixture(); let entry = f.entry(note: ""); f.context.insert(entry); try f.context.save()
        let first = ContentEditorSession(ownerID: entry.id, contentID: entry.id, baseRevision: 0, workingBody: "新记录", workingAttachments: [])
        try SaveContent(modelContext: f.context).createTimeEntryDocumentAndSave(first, entry: entry)
        let doc = try #require(try f.context.fetch(FetchDescriptor<ContentDocument>()).first); let retry = try ContentEditorSession.load(document: doc, modelContext: f.context); try SaveContent(modelContext: f.context).save(retry)
        #expect(try f.context.fetchCount(FetchDescriptor<TimeEntry>()) == 1); #expect(try f.context.fetchCount(FetchDescriptor<ContentDocument>()) == 1)
    }

    @Test func newJournalRetryDoesNotCreateDuplicateJournal() throws {
        let f = try UnifiedContentFixture(); let id = UUID(); let first = ContentEditorSession(ownerID: id, contentID: id, baseRevision: 0, workingBody: "新随记", workingAttachments: [])
        let save = SaveContent(modelContext: f.context); try save.createJournalAndSave(first, capturedAt: f.now, anchorAt: f.now, linkedEntryID: nil, linkSource: .none)
        let doc = try #require(try f.context.fetch(FetchDescriptor<ContentDocument>()).first); let retry = try ContentEditorSession.load(document: doc, modelContext: f.context); try save.save(retry)
        #expect(try f.context.fetchCount(FetchDescriptor<JournalEntry>()) == 1); #expect(try f.context.fetchCount(FetchDescriptor<ContentDocument>()) == 1)
    }
}

@MainActor
private struct UnifiedContentFixture {
    let context: ModelContext
    let rootURL: URL
    let draftStore: ThoughtComposerDraftStore
    let mediaFileStore: MediaFileStore
    let photoLibrary: UnifiedContentPhotoLibraryStub
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init(photoResults: [Result<String, Error>] = [.success("unified-photo")]) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "UnifiedContentTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let schema = Schema(TimeLedgerModels.all)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        context = ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
        draftStore = ThoughtComposerDraftStore(rootURL: rootURL.appending(path: "Draft", directoryHint: .isDirectory))
        mediaFileStore = MediaFileStore(rootURL: rootURL.appending(path: "Media", directoryHint: .isDirectory))
        photoLibrary = UnifiedContentPhotoLibraryStub(results: photoResults)
    }

    func entry(
        note: String,
        projectID: UUID = UUID(),
        startAt: Date? = nil,
        endAt: Date? = nil,
        status: TimeEntryStatus = .draft
    ) -> TimeEntry {
        TimeEntry(
            projectId: projectID,
            projectNameSnapshot: "统一内容项目",
            categoryNameSnapshot: "测试",
            startAt: startAt ?? now.addingTimeInterval(-3_600),
            endAt: endAt ?? now.addingTimeInterval(-1_800),
            note: note,
            status: status
        )
    }

    func moment(linkedTo entry: TimeEntry? = nil) -> MediaMoment {
        MediaMoment(
            kind: .photo,
            capturedAt: now,
            linkedEntryId: entry?.id,
            linkSource: entry == nil ? .none : .manual,
            requestedStorage: .app,
            storedLocation: .app,
            appRelativePath: "Originals/unified.jpg",
            thumbnailData: Data([1]),
            status: .saved,
            originalAvailability: .available
        )
    }

    func cameraCapture(named name: String) throws -> CameraCapture {
        let sourceURL = rootURL.appending(path: "\(name).jpg")
        try Data("original-\(name)".utf8).write(to: sourceURL, options: .atomic)
        return CameraCapture(
            sourceURL: sourceURL,
            kind: .photo,
            capturedAt: now,
            thumbnailData: Data("thumbnail-\(name)".utf8),
            durationSeconds: 0
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

@MainActor
private final class UnifiedContentPhotoLibraryStub: MediaPhotoLibraryWriting {
    var results: [Result<String, Error>]

    init(results: [Result<String, Error>]) {
        self.results = results
    }

    func saveOriginal(at fileURL: URL, kind: MediaKind) async throws -> String {
        if results.isEmpty {
            return "unified-photo"
        }
        return try results.removeFirst().get()
    }

    func assetExists(identifier: String) async -> Bool {
        false
    }
}

private enum UnifiedContentFixtureError: LocalizedError {
    case photoWrite

    var errorDescription: String? {
        "统一内容测试照片写入失败"
    }
}

// MARK: - ExportService Tests

extension TimeLedgerTests {
    @Test func exportJSONUsesDateRangeAndConfirmedFilter() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "阅读", categoryName: "学习")
        context.insert(project)
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-07 23:50", calendar: calendar),
            endAt: date("2026-07-08 00:20", calendar: calendar),
            status: .confirmed
        ))
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 09:30", calendar: calendar),
            status: .draft
        ))
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-09 09:00", calendar: calendar),
            endAt: date("2026-07-09 09:30", calendar: calendar),
            status: .confirmed
        ))
        try context.save()

        let service = JSONExportService(modelContext: context)
        let prepared = try service.prepareJSON(
            range: ExportDateRange(
                start: date("2026-07-08 00:00", calendar: calendar),
                endExclusive: date("2026-07-09 00:00", calendar: calendar)
            ),
            onlyConfirmed: true
        )

        let parsed = try JSONSerialization.jsonObject(with: prepared.data) as! [String: Any]

        #expect(parsed["schemaVersion"] as? Int == 2)
        #expect(parsed["mediaIncluded"] as? Bool == false)
        let projects = parsed["projects"] as? [[String: Any]]
        #expect(projects?.count == 1)
        let entries = parsed["timeEntries"] as? [[String: Any]]
        #expect(entries?.count == 1)
        #expect(prepared.entryCount == 1)
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

    @Test func updateNoteUpdatesOnlyNoteAndTimestampForDraftAndConfirmed() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "备注项目", categoryName: "测试")
        context.insert(project)
        let start = Date(timeIntervalSince1970: 1_800_010_000)
        let end = start.addingTimeInterval(1800)
        let draft = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: start,
            endAt: end,
            note: "旧草稿备注",
            status: .draft
        )
        let confirmed = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: end.addingTimeInterval(60),
            endAt: end.addingTimeInterval(1860),
            note: "旧确认备注",
            status: .confirmed
        )
        context.insert(draft)
        context.insert(confirmed)
        try context.save()

        let service = TimeCursorService(modelContext: context)
        let draftBefore = (
            draft.projectId,
            draft.projectNameSnapshot,
            draft.startAt,
            draft.endAt,
            draft.status,
            draft.createdAt
        )
        let confirmedBefore = (
            confirmed.projectId,
            confirmed.projectNameSnapshot,
            confirmed.startAt,
            confirmed.endAt,
            confirmed.status,
            confirmed.createdAt
        )
        let stamp = Date(timeIntervalSince1970: 1_800_020_000)

        try service.updateNote(draft, note: "新草稿备注", now: stamp)
        try service.updateNote(confirmed, note: "新确认备注", now: stamp)

        let documents = try context.fetch(FetchDescriptor<ContentDocument>())
        #expect(documents.first { $0.ownerID == draft.id }?.body == "新草稿备注")
        #expect(documents.first { $0.ownerID == confirmed.id }?.body == "新确认备注")
        #expect(draft.note == "旧草稿备注")
        #expect(confirmed.note == "旧确认备注")
        #expect(draft.updatedAt == stamp)
        #expect(confirmed.updatedAt == stamp)
        #expect(draft.projectId == draftBefore.0)
        #expect(draft.projectNameSnapshot == draftBefore.1)
        #expect(draft.startAt == draftBefore.2)
        #expect(draft.endAt == draftBefore.3)
        #expect(draft.status == draftBefore.4)
        #expect(draft.createdAt == draftBefore.5)
        #expect(confirmed.projectId == confirmedBefore.0)
        #expect(confirmed.projectNameSnapshot == confirmedBefore.1)
        #expect(confirmed.startAt == confirmedBefore.2)
        #expect(confirmed.endAt == confirmedBefore.3)
        #expect(confirmed.status == confirmedBefore.4)
        #expect(confirmed.createdAt == confirmedBefore.5)
    }

    @Test func failedEntryUpdateLeavesEntryUnchanged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let originalProject = Project(name: "原项目", categoryName: "测试")
        let replacementProject = Project(name: "新项目", categoryName: "测试")
        context.insert(originalProject)
        context.insert(replacementProject)
        let start = Date(timeIntervalSince1970: 1_800_030_000)
        let entry = TimeEntry(
            projectId: originalProject.id,
            projectNameSnapshot: originalProject.name,
            categoryNameSnapshot: originalProject.categoryName,
            startAt: start,
            endAt: start.addingTimeInterval(600),
            note: "原备注",
            status: .draft
        )
        let next = TimeEntry(
            projectId: originalProject.id,
            projectNameSnapshot: originalProject.name,
            categoryNameSnapshot: originalProject.categoryName,
            startAt: start.addingTimeInterval(700),
            endAt: start.addingTimeInterval(1_300),
            status: .confirmed
        )
        context.insert(entry)
        context.insert(next)
        try context.save()

        do {
            try TimeCursorService(modelContext: context).updateEntry(
                entry,
                project: replacementProject,
                note: "不应残留",
                startAt: start.addingTimeInterval(60),
                endAt: start.addingTimeInterval(800),
                now: start.addingTimeInterval(2_000)
            )
            #expect(Bool(false), "与后一段重叠时必须拒绝更新")
        } catch {
            // Expected.
        }

        #expect(entry.projectId == originalProject.id)
        #expect(entry.projectNameSnapshot == originalProject.name)
        #expect(entry.note == "原备注")
        #expect(entry.startAt == start)
        #expect(entry.endAt == start.addingTimeInterval(600))
    }
}
