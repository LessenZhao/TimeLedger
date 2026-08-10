import Testing
import Foundation
import SwiftData
@testable import TimeLedger

struct ThoughtLinkingServiceTests {
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
        let schema = Schema(LegacyThoughtTestModels.all)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // 1. quickCaptureThought creates ThoughtNote with capturedAt = anchorAt = now
    @Test func quickCaptureCreatesThoughtWithDefaults() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = ThoughtLinkingService(modelContext: context)
        let now = date("2026-07-08 09:35", calendar: calendar)

        let thought = try service.quickCaptureThought(body: "这家店不好吃", now: now)

        #expect(thought.body == "这家店不好吃")
        #expect(thought.capturedAt == now)
        #expect(thought.anchorAt == now)
        #expect(thought.linkedEntryId == nil)
        #expect(thought.linkSource == ThoughtLinkSource.none.rawValue)
    }

    // 2. Auto-links when a TimeEntry covers anchorAt
    @Test func autoLinksWhenEntryCoversAnchor() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "在外面吃饭", categoryName: "日常")
        context.insert(project)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 10:00", calendar: calendar)
        )
        context.insert(entry)
        try context.save()

        let service = ThoughtLinkingService(modelContext: context)
        let thought = try service.quickCaptureThought(body: "不好吃", now: date("2026-07-08 09:35", calendar: calendar))

        #expect(thought.linkedEntryId == entry.id)
        #expect(thought.linkSource == ThoughtLinkSource.auto.rawValue)
    }

    // 3. Stays unlinked when no TimeEntry covers anchorAt
    @Test func staysUnlinkedWhenNoEntryCovers() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "在外面吃饭", categoryName: "日常")
        context.insert(project)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 10:00", calendar: calendar),
            endAt: date("2026-07-08 11:00", calendar: calendar)
        )
        context.insert(entry)
        try context.save()

        let service = ThoughtLinkingService(modelContext: context)
        let thought = try service.quickCaptureThought(body: "想法", now: date("2026-07-08 09:35", calendar: calendar))

        #expect(thought.linkedEntryId == nil)
        #expect(thought.linkSource == ThoughtLinkSource.none.rawValue)
    }

    // 4. linkThoughtsForEntry attaches existing unlinked thoughts when new entry created
    @Test func linkThoughtsForEntryAttachesExistingThoughts() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)

        let thoughtService = ThoughtLinkingService(modelContext: context)
        // Capture thought at 09:35 (no entry yet)
        let thought = try thoughtService.quickCaptureThought(body: "不好吃", now: date("2026-07-08 09:35", calendar: calendar))
        #expect(thought.linkedEntryId == nil)

        // Now create entry 09:00 - 10:00
        let project = Project(name: "在外面吃饭", categoryName: "日常")
        context.insert(project)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 10:00", calendar: calendar)
        )
        context.insert(entry)
        try context.save()

        let count = try thoughtService.linkThoughtsForEntry(entry: entry)
        #expect(count == 1)
        #expect(thought.linkedEntryId == entry.id)
        #expect(thought.linkSource == ThoughtLinkSource.auto.rawValue)
    }

    // 5. One entry can link multiple thoughts
    @Test func oneEntryCanLinkMultipleThoughts() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)

        let thoughtService = ThoughtLinkingService(modelContext: context)
        let t1 = try thoughtService.quickCaptureThought(body: "环境一般", now: date("2026-07-08 21:10", calendar: calendar))
        let t2 = try thoughtService.quickCaptureThought(body: "价格偏贵", now: date("2026-07-08 21:25", calendar: calendar))
        let t3 = try thoughtService.quickCaptureThought(body: "下次不来了", now: date("2026-07-08 21:40", calendar: calendar))

        let project = Project(name: "在外面吃饭", categoryName: "日常")
        context.insert(project)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 21:00", calendar: calendar),
            endAt: date("2026-07-08 22:00", calendar: calendar)
        )
        context.insert(entry)
        try context.save()

        let count = try thoughtService.linkThoughtsForEntry(entry: entry)
        #expect(count == 3)
        #expect(t1.linkedEntryId == entry.id)
        #expect(t2.linkedEntryId == entry.id)
        #expect(t3.linkedEntryId == entry.id)
    }

    // 6. Manual link is not overwritten by auto-link
    @Test func manualLinkNotOverwrittenByAuto() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(name: "项目", categoryName: "工作")
        context.insert(project)
        let entryA = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 10:00", calendar: calendar)
        )
        let entryB = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 10:00", calendar: calendar),
            endAt: date("2026-07-08 11:00", calendar: calendar)
        )
        context.insert(entryA)
        context.insert(entryB)
        try context.save()

        let thoughtService = ThoughtLinkingService(modelContext: context)
        let thought = try thoughtService.quickCaptureThought(body: "想法", now: date("2026-07-08 09:30", calendar: calendar))
        // auto-linked to entryA
        #expect(thought.linkedEntryId == entryA.id)

        // Manually link to entryB
        try thoughtService.manuallyLinkThought(thought, to: entryB)
        #expect(thought.linkedEntryId == entryB.id)
        #expect(thought.linkSource == ThoughtLinkSource.manual.rawValue)

        // Try auto-link again → should not overwrite manual
        _ = try thoughtService.tryAutoLinkThought(thought: thought)
        #expect(thought.linkedEntryId == entryB.id)
        #expect(thought.linkSource == ThoughtLinkSource.manual.rawValue)
    }

    // 7. unlinkThought resets to none
    @Test func unlinkResetsToNone() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(name: "项目", categoryName: "工作")
        context.insert(project)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 10:00", calendar: calendar)
        )
        context.insert(entry)
        try context.save()

        let thoughtService = ThoughtLinkingService(modelContext: context)
        let thought = try thoughtService.quickCaptureThought(body: "想法", now: date("2026-07-08 09:30", calendar: calendar))
        #expect(thought.linkedEntryId == entry.id)

        try thoughtService.unlinkThought(thought)
        #expect(thought.linkedEntryId == nil)
        #expect(thought.linkSource == ThoughtLinkSource.none.rawValue)
    }

    // 8. Multiple entries covering anchorAt → pick shorter
    @Test func multipleCoveringPicksShorter() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(name: "项目", categoryName: "工作")
        context.insert(project)
        // Short entry: 09:00 - 09:40 (40 min)
        let shortEntry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 09:40", calendar: calendar)
        )
        // Long entry: 09:10 - 10:00 (50 min) — overlaps with shortEntry (abnormal data)
        let longEntry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:10", calendar: calendar),
            endAt: date("2026-07-08 10:00", calendar: calendar)
        )
        context.insert(shortEntry)
        context.insert(longEntry)
        try context.save()

        let thoughtService = ThoughtLinkingService(modelContext: context)
        // anchorAt = 09:20, covered by both
        let thought = try thoughtService.quickCaptureThought(body: "想法", now: date("2026-07-08 09:20", calendar: calendar))

        #expect(thought.linkedEntryId == shortEntry.id)
    }

    // 9. addThought creates manual link
    @Test func addThoughtCreatesManualLink() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(name: "项目", categoryName: "工作")
        context.insert(project)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 10:00", calendar: calendar)
        )
        context.insert(entry)
        try context.save()

        let thoughtService = ThoughtLinkingService(modelContext: context)
        let now = date("2026-07-08 22:10", calendar: calendar)
        let thought = try thoughtService.addThought(to: entry, body: "事后补充", now: now)

        #expect(thought.linkedEntryId == entry.id)
        #expect(thought.linkSource == ThoughtLinkSource.manual.rawValue)
        #expect(thought.capturedAt == now)
        #expect(thought.anchorAt == now)
    }

    // 10. thoughtsForEntry returns only linked thoughts
    @Test func thoughtsForEntryReturnsLinkedOnly() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(name: "项目", categoryName: "工作")
        context.insert(project)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 10:00", calendar: calendar)
        )
        context.insert(entry)
        try context.save()

        let thoughtService = ThoughtLinkingService(modelContext: context)
        _ = try thoughtService.quickCaptureThought(body: "linked", now: date("2026-07-08 09:30", calendar: calendar))
        _ = try thoughtService.quickCaptureThought(body: "unlinked", now: date("2026-07-08 11:00", calendar: calendar))

        let linked = try thoughtService.thoughtsForEntry(entry)
        #expect(linked.count == 1)
        #expect(linked.first?.body == "linked")
    }

    // 11. thoughtsCapturedOnDate filters by capturedAt natural day
    @Test func thoughtsCapturedOnDateFiltersByCapturedAt() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)

        let thoughtService = ThoughtLinkingService(modelContext: context)
        _ = try thoughtService.quickCaptureThought(body: "today", now: date("2026-07-08 09:00", calendar: calendar))
        _ = try thoughtService.quickCaptureThought(body: "tomorrow", now: date("2026-07-09 09:00", calendar: calendar))

        let thoughts = try thoughtService.thoughtsCapturedOnDate(date("2026-07-08 12:00", calendar: calendar), calendar: calendar)
        #expect(thoughts.count == 1)
        #expect(thoughts.first?.body == "today")
    }

    // 12. relinkAutoThoughtsForDate re-links stale auto links
    @Test func relinkFixesStaleAutoLinks() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(name: "项目", categoryName: "工作")
        context.insert(project)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00", calendar: calendar),
            endAt: date("2026-07-08 10:00", calendar: calendar)
        )
        context.insert(entry)
        try context.save()

        let thoughtService = ThoughtLinkingService(modelContext: context)
        let thought = try thoughtService.quickCaptureThought(body: "想法", now: date("2026-07-08 09:30", calendar: calendar))
        #expect(thought.linkedEntryId == entry.id)

        // Modify entry to no longer cover 09:30 (move to 09:35 - 10:00)
        entry.startAt = date("2026-07-08 09:45", calendar: calendar)
        try context.save()

        let count = try thoughtService.relinkAutoThoughtsForDate(date("2026-07-08 12:00", calendar: calendar), calendar: calendar)
        #expect(count >= 1)
        #expect(thought.linkedEntryId == nil)
        #expect(thought.linkSource == ThoughtLinkSource.none.rawValue)
    }
}
