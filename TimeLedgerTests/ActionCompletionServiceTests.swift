import Foundation
import SwiftData
import Testing
@testable import TimeLedger

struct ActionCompletionServiceTests {
    @Test func createItemTrimsTitleAndPersistsOrder() throws {
        let context = try makeContext()
        let service = ActionCompletionService(modelContext: context, calendar: calendar)

        let item = try service.createItem(title: "  吃药  ", sortOrder: 3, now: date("2026-07-08 08:00"))

        #expect(item.title == "吃药")
        #expect(item.sortOrder == 3)
        #expect(try context.fetch(FetchDescriptor<ActionItem>()).count == 1)
    }

    @Test func repeatedCompletionIsIdempotentWithinNaturalDay() throws {
        let context = try makeContext()
        let service = ActionCompletionService(modelContext: context, calendar: calendar)
        let item = try service.createItem(title: "吃药")

        let first = try service.complete(item, now: date("2026-07-08 08:00"))
        let repeated = try service.complete(item, now: date("2026-07-08 20:00"))

        #expect(first.id == repeated.id)
        #expect(try context.fetch(FetchDescriptor<ActionCompletion>()).count == 1)
    }

    @Test func completionResetsAtLocalMidnight() throws {
        let context = try makeContext()
        let service = ActionCompletionService(modelContext: context, calendar: calendar)
        let item = try service.createItem(title: "吃药")

        _ = try service.complete(item, now: date("2026-07-08 23:59"))
        _ = try service.complete(item, now: date("2026-07-09 00:01"))

        let completions = try context.fetch(FetchDescriptor<ActionCompletion>())
        #expect(completions.count == 2)
        #expect(Set(completions.map(\.dayStart)).count == 2)
    }

    @Test func completionImmediatelyLinksDraftOrConfirmedEntry() throws {
        for status in [TimeEntryStatus.draft, .confirmed] {
            let context = try makeContext()
            let project = Project(name: "生活", categoryName: "日常")
            let entry = TimeEntry(
                projectId: project.id,
                projectNameSnapshot: project.name,
                categoryNameSnapshot: project.categoryName,
                startAt: date("2026-07-08 08:00"),
                endAt: date("2026-07-08 09:00"),
                status: status
            )
            context.insert(project)
            context.insert(entry)
            let service = ActionCompletionService(modelContext: context, calendar: calendar)
            let item = try service.createItem(title: "吃药")

            let completion = try service.complete(item, now: date("2026-07-08 08:30"))

            #expect(completion.linkedEntryId == entry.id)
        }
    }

    @Test func pendingCompletionLinksWhenEntryIsRecordedLater() throws {
        let context = try makeContext()
        let project = Project(name: "早餐", categoryName: "生活")
        context.insert(project)
        let cursor = TimeCursor(cursorAt: date("2026-07-08 08:00"), updatedAt: date("2026-07-08 08:00"))
        context.insert(cursor)
        let service = ActionCompletionService(modelContext: context, calendar: calendar)
        let item = try service.createItem(title: "吃药")
        let completion = try service.complete(item, now: date("2026-07-08 08:30"))
        #expect(completion.linkedEntryId == nil)

        let entry = try TimeCursorService(modelContext: context).quickRecord(
            project: project,
            now: date("2026-07-08 09:00")
        )

        #expect(completion.linkedEntryId == entry.id)
    }

    @Test func boundaryCompletionBelongsToFollowingEntry() throws {
        let context = try makeContext()
        let project = Project(name: "日常", categoryName: "生活")
        let first = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: "第一段",
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 08:00"),
            endAt: date("2026-07-08 09:00")
        )
        let second = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: "第二段",
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00"),
            endAt: date("2026-07-08 10:00")
        )
        context.insert(project)
        context.insert(first)
        context.insert(second)
        let service = ActionCompletionService(modelContext: context, calendar: calendar)
        let item = try service.createItem(title: "吃药")

        let completion = try service.complete(item, now: date("2026-07-08 09:00"))

        #expect(completion.linkedEntryId == second.id)
    }

    @Test func reconcileMovesOrClearsStaleLink() throws {
        let context = try makeContext()
        let project = Project(name: "生活", categoryName: "日常")
        let original = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 08:00"),
            endAt: date("2026-07-08 09:00")
        )
        context.insert(project)
        context.insert(original)
        let service = ActionCompletionService(modelContext: context, calendar: calendar)
        let item = try service.createItem(title: "吃药")
        let completion = try service.complete(item, now: date("2026-07-08 08:30"))
        #expect(completion.linkedEntryId == original.id)

        original.startAt = date("2026-07-08 09:00")
        original.endAt = date("2026-07-08 10:00")
        try context.save()
        _ = try service.reconcileAllLinks()
        #expect(completion.linkedEntryId == nil)

        let replacement = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 08:00"),
            endAt: date("2026-07-08 09:00")
        )
        context.insert(replacement)
        try context.save()
        _ = try service.reconcileAllLinks()
        #expect(completion.linkedEntryId == replacement.id)

        context.delete(replacement)
        try context.save()
        _ = try service.reconcileAllLinks()
        #expect(completion.linkedEntryId == nil)
    }

    @Test func timeCursorUpdateReconcilesCompletionLink() throws {
        let context = try makeContext()
        let project = Project(name: "生活", categoryName: "日常")
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 08:00"),
            endAt: date("2026-07-08 09:00")
        )
        context.insert(project)
        context.insert(entry)
        context.insert(TimeCursor(
            cursorAt: date("2026-07-08 09:00"),
            updatedAt: date("2026-07-08 09:00")
        ))
        let service = ActionCompletionService(modelContext: context, calendar: calendar)
        let item = try service.createItem(title: "吃药")
        let completion = try service.complete(item, now: date("2026-07-08 08:30"))
        #expect(completion.linkedEntryId == entry.id)

        try TimeCursorService(modelContext: context).updateEntry(
            entry,
            project: project,
            note: "",
            startAt: date("2026-07-08 08:00"),
            endAt: date("2026-07-08 08:20"),
            now: date("2026-07-08 10:00")
        )

        #expect(completion.linkedEntryId == nil)
    }

    @Test func timeCursorDeleteClearsCompletionLink() throws {
        let context = try makeContext()
        let project = Project(name: "生活", categoryName: "日常")
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 08:00"),
            endAt: date("2026-07-08 09:00")
        )
        context.insert(project)
        context.insert(entry)
        context.insert(TimeCursor(
            cursorAt: date("2026-07-08 09:00"),
            updatedAt: date("2026-07-08 09:00")
        ))
        let service = ActionCompletionService(modelContext: context, calendar: calendar)
        let item = try service.createItem(title: "吃药")
        let completion = try service.complete(item, now: date("2026-07-08 08:30"))
        #expect(completion.linkedEntryId == entry.id)

        try TimeCursorService(modelContext: context).deleteDraftEntry(entry)

        #expect(completion.linkedEntryId == nil)
    }

    @Test func undoRemovesOnlyRequestedDaysCompletion() throws {
        let context = try makeContext()
        let service = ActionCompletionService(modelContext: context, calendar: calendar)
        let item = try service.createItem(title: "吃药")
        _ = try service.complete(item, now: date("2026-07-08 08:00"))
        _ = try service.complete(item, now: date("2026-07-09 08:00"))

        try service.undoCompletion(for: item, on: date("2026-07-09 12:00"))

        let completions = try context.fetch(FetchDescriptor<ActionCompletion>())
        #expect(completions.count == 1)
        #expect(completions.first?.dayStart == calendar.startOfDay(for: date("2026-07-08 12:00")))
    }

    @Test func archivedItemCannotBeCompleted() throws {
        let context = try makeContext()
        let service = ActionCompletionService(modelContext: context, calendar: calendar)
        let item = try service.createItem(title: "吃药")
        try service.updateItem(item, title: item.title, sortOrder: 0, isArchived: true)

        #expect(throws: ActionCompletionError.self) {
            try service.complete(item, now: date("2026-07-08 08:00"))
        }
    }

    @Test func additiveSchemaKeepsLegacyProjectAndEntry() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TimeLedgerMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "TimeLedger.store")
        let legacyModels: [any PersistentModel.Type] = [
            Project.self,
            TimeCursor.self,
            TimeEntry.self,
            AppSettings.self,
            ThoughtNote.self,
        ]

        var legacyContainer: ModelContainer? = try ModelContainer(
            for: Schema(legacyModels),
            configurations: [ModelConfiguration("MigrationTest", schema: Schema(legacyModels), url: storeURL)]
        )
        let legacyContext = ModelContext(legacyContainer!)
        let project = Project(name: "保留项目", categoryName: "工作")
        legacyContext.insert(project)
        legacyContext.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: date("2026-07-08 09:00"),
            endAt: date("2026-07-08 10:00")
        ))
        try legacyContext.save()
        legacyContainer = nil

        let currentSchema = Schema(TimeLedgerModels.all)
        let currentContainer = try ModelContainer(
            for: currentSchema,
            configurations: [ModelConfiguration("MigrationTest", schema: currentSchema, url: storeURL)]
        )
        let currentContext = ModelContext(currentContainer)

        let projects = try currentContext.fetch(FetchDescriptor<Project>())
        let entries = try currentContext.fetch(FetchDescriptor<TimeEntry>())
        #expect(projects.count == 1)
        #expect(projects.first?.name == "保留项目")
        #expect(entries.count == 1)
        #expect(entries.first?.projectNameSnapshot == "保留项目")
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(TimeLedgerModels.all)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.locale = Locale(identifier: "en_US_POSIX")
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
