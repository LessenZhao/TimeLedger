import Foundation
import SwiftData
import Testing
@testable import TimeLedger

@MainActor
struct TimeEntryAtomicSaveRiskTests {
    @Test func failedTimeEntryUpdateRollsBackContentAttachmentsLinksAndEntry() throws {
        let schema = Schema(TimeLedgerModels.all)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [configuration]))

        let now = Date(timeIntervalSince1970: 10_000)
        let originalStart = Date(timeIntervalSince1970: 7_000)
        let originalEnd = Date(timeIntervalSince1970: 8_000)
        let desiredStart = Date(timeIntervalSince1970: 7_500)
        let desiredEnd = Date(timeIntervalSince1970: 8_500)
        let project = Project(name: "原子保存", categoryName: "测试")
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: originalStart,
            endAt: originalEnd
        )
        let document = ContentDocument(ownerID: entry.id, ownerKind: .timeEntry, body: "原正文")
        let originalMedia = makeMedia(path: "Originals/original.jpg", capturedAt: originalStart)
        let replacementMedia = makeMedia(path: "Originals/replacement.jpg", capturedAt: originalStart)
        let originalAttachment = ContentAttachment(
            contentDocumentID: document.id,
            mediaMomentID: originalMedia.id,
            state: .ready
        )
        let journal = JournalEntry(capturedAt: originalStart, anchorAt: originalStart)
        let link = JournalTimeLink(
            journalEntryID: journal.id,
            timeEntryID: entry.id,
            linkSource: .manual
        )

        context.insert(project)
        context.insert(entry)
        context.insert(document)
        context.insert(originalMedia)
        context.insert(replacementMedia)
        context.insert(originalAttachment)
        context.insert(journal)
        context.insert(link)
        try context.save()

        let cursorService = TimeCursorService(modelContext: context)
        try cursorService.validateEntryUpdate(
            entry,
            project: project,
            startAt: desiredStart,
            endAt: desiredEnd,
            now: now
        )

        let contentSession = try ContentEditorSession.load(document: document, modelContext: context)
        contentSession.updateText("不应落库的新正文")
        contentSession.apply(.removeMedia(originalMedia.id))
        contentSession.apply(.addMedia(replacementMedia.id))
        try SaveContent(modelContext: context).save(contentSession)

        // Simulate a concurrent change after preflight validation but before the entry update.
        let blockingEntry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 8_400),
            endAt: Date(timeIntervalSince1970: 9_000),
            status: .confirmed
        )
        context.insert(blockingEntry)
        context.insert(ContentDocument(ownerID: blockingEntry.id, ownerKind: .timeEntry))
        try context.save()

        #expect(throws: TimeCursorError.endOverlapsNext) {
            try cursorService.updateEntry(
                entry,
                project: project,
                note: nil,
                startAt: desiredStart,
                endAt: desiredEnd,
                now: now
            )
        }

        let attachmentIDs = Set(
            try context.fetch(FetchDescriptor<ContentAttachment>())
                .filter { $0.contentDocumentID == document.id }
                .map(\.mediaMomentID)
        )
        let persistedLink = try #require(
            try context.fetch(FetchDescriptor<JournalTimeLink>())
                .first { $0.journalEntryID == journal.id }
        )

        #expect(document.body == "原正文")
        #expect(attachmentIDs == [originalMedia.id])
        #expect(persistedLink.timeEntryID == entry.id)
        #expect(entry.startAt == originalStart)
        #expect(entry.endAt == originalEnd)
    }

    private func makeMedia(path: String, capturedAt: Date) -> MediaMoment {
        MediaMoment(
            kind: .photo,
            capturedAt: capturedAt,
            requestedStorage: .app,
            storedLocation: .app,
            appRelativePath: path,
            thumbnailData: Data(),
            status: .saved,
            originalAvailability: .available
        )
    }
}
