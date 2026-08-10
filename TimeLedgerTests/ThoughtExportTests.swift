import Testing
import Foundation
import SwiftData
@testable import TimeLedger

struct ThoughtExportTests {
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

    private func insertJournal(
        body: String,
        capturedAt: Date,
        linkedEntryID: UUID? = nil,
        linkSource: JournalLinkSource = .none,
        into context: ModelContext
    ) {
        let journal = JournalEntry(capturedAt: capturedAt, anchorAt: capturedAt)
        context.insert(journal)
        context.insert(ContentDocument(ownerID: journal.id, ownerKind: .journalEntry, body: body))
        if let linkedEntryID {
            context.insert(JournalTimeLink(
                journalEntryID: journal.id,
                timeEntryID: linkedEntryID,
                linkSource: linkSource
            ))
        }
    }

    // 1. JSON export includes thoughtNotes
    @Test func jsonExportIncludesThoughtNotes() throws {
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
            endAt: date("2026-07-08 10:00", calendar: calendar),
            status: .confirmed
        )
        context.insert(entry)
        context.insert(ContentDocument(ownerID: entry.id, ownerKind: .timeEntry))
        insertJournal(
            body: "这家店不好吃",
            capturedAt: date("2026-07-08 09:35", calendar: calendar),
            linkedEntryID: entry.id,
            linkSource: .auto,
            into: context
        )
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

        let thoughtNotes = parsed["thoughtNotes"] as? [[String: Any]]
        #expect(thoughtNotes?.count == 1)
        #expect(thoughtNotes?.first?["body"] as? String == "这家店不好吃")
        #expect(thoughtNotes?.first?["linkSource"] as? String == "auto")
    }

    // 2. Markdown includes linked thoughts under each entry
    @Test func markdownIncludesLinkedThoughtsUnderEntry() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "在外面吃饭", categoryName: "日常")
        context.insert(project)
        let entryStart = date("2026-07-08 09:00", calendar: calendar)
        let entryEnd = date("2026-07-08 10:00", calendar: calendar)
        let thoughtTime = date("2026-07-08 09:35", calendar: calendar)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: entryStart,
            endAt: entryEnd,
            status: .confirmed
        )
        context.insert(entry)
        context.insert(ContentDocument(ownerID: entry.id, ownerKind: .timeEntry))
        insertJournal(
            body: "这家店不好吃",
            capturedAt: thoughtTime,
            linkedEntryID: entry.id,
            linkSource: .auto,
            into: context
        )
        try context.save()

        let service = ExportService(modelContext: context, calendar: calendar)
        let md = try service.exportMarkdownDailyReport(date: date("2026-07-08 12:00", calendar: calendar), onlyConfirmed: true)

        let expectedTime = DateFormatterFactory.timeOnly.string(from: thoughtTime)
        #expect(md.contains("关联随记"))
        #expect(md.contains(expectedTime))
        #expect(md.contains("当时想法"))
        #expect(md.contains("这家店不好吃"))
    }

    // 3. Markdown includes "今日捕获的思考" section
    @Test func markdownIncludesTodayCapturedThoughts() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "AI学习", categoryName: "学习")
        context.insert(project)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 10:00", calendar: calendar),
            endAt: date("2026-07-08 11:30", calendar: calendar),
            status: .confirmed
        )
        context.insert(entry)
        context.insert(ContentDocument(ownerID: entry.id, ownerKind: .timeEntry))
        insertJournal(
            body: "handoff 的本质是状态交接",
            capturedAt: date("2026-07-08 10:22", calendar: calendar),
            linkedEntryID: entry.id,
            linkSource: .auto,
            into: context
        )
        try context.save()

        let service = ExportService(modelContext: context, calendar: calendar)
        let md = try service.exportMarkdownDailyReport(date: date("2026-07-08 12:00", calendar: calendar), onlyConfirmed: true)

        #expect(md.contains("今日捕获的随记"))
        #expect(md.contains("handoff 的本质是状态交接"))
    }

    // 4. Markdown includes "未匹配思考" section
    @Test func markdownIncludesUnlinkedThoughts() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        insertJournal(
            body: "重新设计时间线笔记结构",
            capturedAt: date("2026-07-08 23:20", calendar: calendar),
            into: context
        )
        try context.save()

        let service = ExportService(modelContext: context, calendar: calendar)
        let md = try service.exportMarkdownDailyReport(date: date("2026-07-08 12:00", calendar: calendar), onlyConfirmed: true)

        #expect(md.contains("未匹配随记"))
        #expect(md.contains("重新设计时间线笔记结构"))
    }

    // 5. Thought captured today but linked to yesterday's entry still appears in today's captured thoughts
    @Test func todayThoughtLinkedToYesterdayEntryStillInTodayCaptured() throws {
        let calendar = fixedCalendar
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "在外面吃饭", categoryName: "日常")
        context.insert(project)
        let yesterdayEntry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-07 09:00", calendar: calendar),
            endAt: date("2026-07-07 10:00", calendar: calendar),
            status: .confirmed
        )
        context.insert(yesterdayEntry)
        context.insert(ContentDocument(ownerID: yesterdayEntry.id, ownerKind: .timeEntry))
        // Thought captured today (07-08 22:10) but manually linked to yesterday's entry
        insertJournal(
            body: "今天吃饭说明选择成本太高",
            capturedAt: date("2026-07-08 22:10", calendar: calendar),
            linkedEntryID: yesterdayEntry.id,
            linkSource: .manual,
            into: context
        )
        try context.save()

        let service = ExportService(modelContext: context, calendar: calendar)
        let md = try service.exportMarkdownDailyReport(date: date("2026-07-08 12:00", calendar: calendar), onlyConfirmed: true)

        // Should appear in "今日捕获的思考"
        #expect(md.contains("今日捕获的随记"))
        #expect(md.contains("今天吃饭说明选择成本太高"))
        // Should show linked to "在外面吃饭"
        #expect(md.contains("关联：在外面吃饭"))
    }

}
