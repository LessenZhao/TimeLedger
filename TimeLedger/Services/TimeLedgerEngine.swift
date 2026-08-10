import Foundation
import SwiftData

/// 唯一外部写入口。内部按领域拆分命令处理器，失败操作必须零副作用。
@MainActor
struct TimeLedgerEngine {
    let modelContext: ModelContext



    private var entries: EntryCommandHandler {
        EntryCommandHandler(modelContext: modelContext)
    }

    private var content: ContentCommandHandler {
        ContentCommandHandler(modelContext: modelContext)
    }

    private var journals: JournalCommandHandler {
        JournalCommandHandler(modelContext: modelContext)
    }

    private var imports: ImportCommandHandler {
        ImportCommandHandler(modelContext: modelContext)
    }

    private var projects: ProjectCommandHandler {
        ProjectCommandHandler(modelContext: modelContext)
    }

    private var settings: SettingsCommandHandler {
        SettingsCommandHandler(modelContext: modelContext)
    }

    // MARK: Cursor / TimeEntry

    func getOrCreateCursor(now: Date = Date()) throws -> TimeCursor {
        try entries.getOrCreateCursor(now: now)
    }

    func currentUnclassifiedDuration(now: Date = Date()) throws -> TimeInterval {
        try entries.currentUnclassifiedDuration(now: now)
    }

    @discardableResult
    func quickRecord(project: Project, now: Date = Date()) throws -> TimeEntry {
        try entries.quickRecord(project: project, now: now)
    }

    @discardableResult
    func recordSegment(
        project: Project,
        startAt: Date,
        endAt: Date,
        note: String = "",
        now: Date = Date()
    ) throws -> TimeEntry {
        try entries.recordSegment(project: project, startAt: startAt, endAt: endAt, note: note, now: now)
    }

    func skipSegment(to date: Date) throws {
        try entries.skipSegment(to: date)
    }

    func canUndoLastEntry() throws -> Bool {
        try entries.canUndoLastEntry()
    }

    func undoLastEntry(expectedId: UUID? = nil) throws {
        try entries.undoLastEntry(expectedId: expectedId)
    }

    func lastEntryBeforeCursor() throws -> TimeEntry? {
        try entries.lastEntryBeforeCursor()
    }

    func updateEntry(
        _ entry: TimeEntry,
        project: Project,
        note: String?,
        startAt: Date,
        endAt: Date,
        now: Date = Date()
    ) throws {
        try entries.updateEntry(
            entry,
            project: project,
            note: note,
            startAt: startAt,
            endAt: endAt,
            now: now
        )
    }

    func validateEntryUpdate(
        _ entry: TimeEntry,
        project: Project,
        startAt: Date,
        endAt: Date,
        now: Date = Date()
    ) throws {
        try entries.validateEntryUpdate(
            entry,
            project: project,
            startAt: startAt,
            endAt: endAt,
            now: now
        )
    }

    func updateNote(_ entry: TimeEntry, note: String, now: Date = Date()) throws {
        try entries.updateNote(entry, note: note, now: now)
    }

    func cancelConfirmation(_ entry: TimeEntry) throws {
        try entries.cancelConfirmation(entry)
    }

    func deleteDraftEntry(_ entry: TimeEntry) throws {
        try entries.deleteDraftEntry(entry)
    }

    // MARK: Project / Settings

    func saveProject(
        project: Project?,
        name: String,
        categoryName: String,
        emoji: String?,
        colorHex: String?,
        sortOrder: Int,
        isArchived: Bool
    ) throws {
        try projects.saveProject(
            project: project,
            name: name,
            categoryName: categoryName,
            emoji: emoji,
            colorHex: colorHex,
            sortOrder: sortOrder,
            isArchived: isArchived
        )
    }

    func deleteProject(_ project: Project) throws {
        try projects.deleteProject(project)
    }

    func getOrCreateAppSettings() throws -> AppSettings {
        try settings.getOrCreateAppSettings()
    }

    func saveAppSettings(_ appSettings: AppSettings) throws {
        try settings.saveAppSettings(appSettings)
    }

    func seedUITestFixtures(kind: UITestFixtureKind, now: Date = Date()) throws {
        try FixtureCommandHandler(modelContext: modelContext).seed(kind, now: now)
    }

    // MARK: Content

    func saveContent(_ session: ContentEditorSession) throws {
        try content.save(session)
    }

    func createTimeEntryDocumentAndSave(_ session: ContentEditorSession, entry: TimeEntry) throws {
        try content.createTimeEntryDocumentAndSave(session, entry: entry)
    }

    func createJournalAndSave(
        _ session: ContentEditorSession,
        capturedAt: Date,
        anchorAt: Date,
        linkedEntryID: UUID?,
        linkSource: JournalLinkSource
    ) throws {
        try content.createJournalAndSave(
            session,
            capturedAt: capturedAt,
            anchorAt: anchorAt,
            linkedEntryID: linkedEntryID,
            linkSource: linkSource
        )
    }

    func clearPendingContent(ownerID: UUID, ownerKind: ContentOwnerKind) {
        PendingContentSnapshots.clear(ownerID: ownerID, ownerKind: ownerKind)
    }

    // MARK: Journal

    func link(_ journal: JournalEntry, to entry: TimeEntry) throws {
        try journals.link(journal, to: entry)
    }

    func unlink(_ journal: JournalEntry) throws {
        try journals.unlink(journal)
    }

    @discardableResult
    func linkUnlinkedJournals(to entry: TimeEntry) throws -> Int {
        try journals.linkUnlinkedJournals(to: entry)
    }

    @discardableResult
    func reconcileAutoLinks() throws -> Int {
        try journals.reconcileAutoLinks()
    }

    func delete(_ journal: JournalEntry) throws {
        try journals.delete(journal)
    }

    func setFavorite(_ journal: JournalEntry, _ value: Bool) throws {
        try journals.setFavorite(journal, value)
    }

    // MARK: Import

    @discardableResult
    func importMacBatchJSON(_ json: String) throws -> Int {
        try imports.importMacBatchJSON(json)
    }

    // MARK: - Generic Write Wrappers (facade for migrated services)

    /// Insert any PersistentModel through the engine.
    func insert<T: PersistentModel>(_ model: T) {
        modelContext.insert(model)
    }

    /// Delete any PersistentModel through the engine.
    func delete<T: PersistentModel>(_ model: T) {
        modelContext.delete(model)
    }

    /// Save the model context through the engine.
    func save() throws {
        try modelContext.save()
    }
}

// MARK: - Entry / cursor commands

@MainActor
struct EntryCommandHandler {
    let modelContext: ModelContext

    func getOrCreateCursor(now: Date = Date()) throws -> TimeCursor {
        var descriptor = FetchDescriptor<TimeCursor>(sortBy: [SortDescriptor(\.updatedAt)])
        descriptor.fetchLimit = 1

        if let cursor = try modelContext.fetch(descriptor).first {
            return cursor
        }

        let cursor = TimeCursor(cursorAt: now, updatedAt: now)
        modelContext.insert(cursor)
        try modelContext.save()
        return cursor
    }

    func currentUnclassifiedDuration(now: Date = Date()) throws -> TimeInterval {
        let cursor = try getOrCreateCursor(now: now)
        return max(0, now.timeIntervalSince(cursor.cursorAt))
    }

    @discardableResult
    func quickRecord(project: Project, now: Date = Date()) throws -> TimeEntry {
        let cursor = try getOrCreateCursor(now: now)
        guard now > cursor.cursorAt else {
            throw TimeCursorError.emptySegment
        }
        try ValidationService(modelContext: modelContext).validateEntry(
            projectId: project.id,
            startAt: cursor.cursorAt,
            endAt: now
        )

        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: cursor.cursorAt,
            endAt: now
        )

        modelContext.insert(entry)
        modelContext.insert(ContentDocument(ownerID: entry.id, ownerKind: ContentOwnerKind.timeEntry))
        cursor.cursorAt = now
        cursor.updatedAt = now
        try modelContext.save()
        _ = try? TimeLedgerEngine(modelContext: modelContext).linkUnlinkedJournals(to: entry)
        _ = try? ActionCompletionService(modelContext: modelContext).linkCompletionsForEntry(entry)
        return entry
    }

    @discardableResult
    func recordSegment(
        project: Project,
        startAt: Date,
        endAt: Date,
        note: String = "",
        now: Date = Date()
    ) throws -> TimeEntry {
        let cursor = try getOrCreateCursor(now: now)
        guard endAt > startAt else {
            throw TimeCursorError.emptySegment
        }
        guard startAt >= cursor.cursorAt else {
            throw TimeCursorError.startBeforeCursor
        }
        guard endAt <= now else {
            throw TimeCursorError.endAfterNow
        }
        try ValidationService(modelContext: modelContext).validateEntry(
            projectId: project.id,
            startAt: startAt,
            endAt: endAt
        )

        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: startAt,
            endAt: endAt,
            note: ""
        )

        modelContext.insert(entry)
        modelContext.insert(ContentDocument(ownerID: entry.id, ownerKind: ContentOwnerKind.timeEntry, body: note))
        cursor.cursorAt = endAt
        cursor.updatedAt = now
        try modelContext.save()
        _ = try? TimeLedgerEngine(modelContext: modelContext).linkUnlinkedJournals(to: entry)
        _ = try? ActionCompletionService(modelContext: modelContext).linkCompletionsForEntry(entry)
        return entry
    }

    func skipSegment(to date: Date) throws {
        let cursor = try getOrCreateCursor(now: date)
        guard date > cursor.cursorAt else {
            throw TimeCursorError.emptySegment
        }

        cursor.cursorAt = date
        cursor.updatedAt = date
        try modelContext.save()
    }

    func canUndoLastEntry() throws -> Bool {
        let cursor = try getOrCreateCursor()
        guard let last = try lastCreatedEntry() else {
            return false
        }
        return last.status == TimeEntryStatus.draft.rawValue && last.endAt == cursor.cursorAt
    }

    func undoLastEntry(expectedId: UUID? = nil) throws {
        let cursor = try getOrCreateCursor()
        guard let last = try lastCreatedEntry(),
              last.status == TimeEntryStatus.draft.rawValue,
              last.endAt == cursor.cursorAt
        else {
            throw TimeCursorError.cannotUndo
        }

        if let expectedId, last.id != expectedId {
            throw TimeCursorError.cannotUndo
        }

        cursor.cursorAt = last.startAt
        cursor.updatedAt = Date()
        try deleteContent(for: last)
        modelContext.delete(last)
        try modelContext.save()
        _ = try? TimeLedgerEngine(modelContext: modelContext).reconcileAutoLinks()
        reconcileActionLinks()
    }

    func lastEntryBeforeCursor() throws -> TimeEntry? {
        let cursor = try getOrCreateCursor()
        let entries = try modelContext.fetch(
            FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.endAt, order: .reverse)])
        )
        return entries.first { $0.endAt <= cursor.cursorAt }
    }

    func updateEntry(
        _ entry: TimeEntry,
        project: Project,
        note: String?,
        startAt: Date,
        endAt: Date,
        now: Date = Date()
    ) throws {
        do {
            let originalStartAt = entry.startAt
            let originalEndAt = entry.endAt
            var nextDraftToSnap: TimeEntry?
            var unknownProject: Project?
            var cursorToMove: TimeCursor?

            if entry.status == TimeEntryStatus.draft.rawValue {
                try validateEntryUpdate(
                    entry,
                    project: project,
                    startAt: startAt,
                    endAt: endAt,
                    now: now
                )

                let next = try nextEntry(after: entry)
                if let next {
                    let nextIsDraft = next.status == TimeEntryStatus.draft.rawValue
                    if nextIsDraft {
                        let shouldSnapNextStart =
                            endAt > next.startAt
                            || (endAt < originalEndAt && next.startAt == originalEndAt)
                        if shouldSnapNextStart {
                            nextDraftToSnap = next
                        }
                    }
                }

                if startAt > originalStartAt {
                    unknownProject = try SystemProject.getOrCreateUnknown(modelContext: modelContext)
                }

                let cursor = try getOrCreateCursor(now: now)
                if cursor.cursorAt == originalEndAt {
                    cursorToMove = cursor
                }
            }

            entry.projectId = project.id
            entry.projectNameSnapshot = project.name
            entry.categoryNameSnapshot = project.categoryName
            _ = note
            entry.updatedAt = now

            var freedEntry: TimeEntry?
            if entry.status == TimeEntryStatus.draft.rawValue {
                if let nextDraftToSnap {
                    nextDraftToSnap.startAt = endAt
                    nextDraftToSnap.updatedAt = now
                }

                if let unknownProject {
                    let freed = TimeEntry(
                        projectId: unknownProject.id,
                        projectNameSnapshot: unknownProject.name,
                        categoryNameSnapshot: unknownProject.categoryName,
                        startAt: originalStartAt,
                        endAt: startAt,
                        status: .draft
                    )
                    modelContext.insert(freed)
                    modelContext.insert(ContentDocument(ownerID: freed.id, ownerKind: ContentOwnerKind.timeEntry))
                    freedEntry = freed
                }

                entry.startAt = startAt
                entry.endAt = endAt

                if let cursorToMove {
                    cursorToMove.cursorAt = endAt
                    cursorToMove.updatedAt = now
                }
            }

            try modelContext.save()
            if let freedEntry {
                _ = try? TimeLedgerEngine(modelContext: modelContext).linkUnlinkedJournals(to: freedEntry)
            }
            _ = try? TimeLedgerEngine(modelContext: modelContext).reconcileAutoLinks()
            reconcileActionLinks()
            PendingContentSnapshots.clear(ownerID: entry.id, ownerKind: ContentOwnerKind.timeEntry)
        } catch {
            try? ContentRollback.restorePendingContent(
                ownerID: entry.id,
                ownerKind: ContentOwnerKind.timeEntry,
                modelContext: modelContext
            )
            throw error
        }
    }

    func validateEntryUpdate(
        _ entry: TimeEntry,
        project: Project,
        startAt: Date,
        endAt: Date,
        now: Date = Date()
    ) throws {
        guard entry.status == TimeEntryStatus.draft.rawValue else { return }
        guard endAt > startAt else {
            throw ValidationError.invalidTimeRange
        }
        guard startAt >= entry.startAt else {
            throw TimeCursorError.startCannotMoveEarlier
        }
        guard endAt <= now else {
            throw TimeCursorError.endAfterNow
        }

        var excludedEntryIds: Set<UUID> = [entry.id]
        if let next = try nextEntry(after: entry) {
            if next.status == TimeEntryStatus.draft.rawValue {
                if endAt >= next.endAt {
                    throw TimeCursorError.squeezesNextDraft
                }
                if endAt > next.startAt {
                    excludedEntryIds.insert(next.id)
                }
            } else if endAt > next.startAt {
                throw TimeCursorError.endOverlapsNext
            }
        }

        try ValidationService(modelContext: modelContext).validateEntry(
            projectId: project.id,
            startAt: startAt,
            endAt: endAt,
            excludingEntryIds: excludedEntryIds
        )
    }

    func updateNote(_ entry: TimeEntry, note: String, now: Date = Date()) throws {
        let document: ContentDocument
        if let existing = try TimeLedgerQueries(modelContext: modelContext).document(ownerID: entry.id, ownerKind: ContentOwnerKind.timeEntry) {
            document = existing
        } else {
            document = ContentDocument(ownerID: entry.id, ownerKind: ContentOwnerKind.timeEntry)
            modelContext.insert(document)
        }
        document.body = note
        document.revision += 1
        document.updatedAt = now
        entry.updatedAt = now
        try modelContext.save()
    }

    func cancelConfirmation(_ entry: TimeEntry) throws {
        entry.status = TimeEntryStatus.draft.rawValue
        entry.updatedAt = Date()
        try modelContext.save()
    }

    func deleteDraftEntry(_ entry: TimeEntry) throws {
        guard entry.status == TimeEntryStatus.draft.rawValue else {
            throw TimeCursorError.cannotDelete
        }

        let deletedStart = entry.startAt
        let deletedEnd = entry.endAt
        let cursor = try getOrCreateCursor()

        if cursor.cursorAt == deletedEnd {
            cursor.cursorAt = deletedStart
            cursor.updatedAt = Date()
            try deleteContent(for: entry)
            modelContext.delete(entry)
            try modelContext.save()
            _ = try? TimeLedgerEngine(modelContext: modelContext).reconcileAutoLinks()
            reconcileActionLinks()
            return
        }

        if let next = try nextEntry(after: entry),
           next.status == TimeEntryStatus.draft.rawValue {
            next.startAt = deletedStart
            next.updatedAt = Date()
        }

        try deleteContent(for: entry)
        modelContext.delete(entry)
        try modelContext.save()
        _ = try? TimeLedgerEngine(modelContext: modelContext).reconcileAutoLinks()
        reconcileActionLinks()
    }

    func nextEntry(after entry: TimeEntry) throws -> TimeEntry? {
        let entries = try TimeLedgerQueries(modelContext: modelContext).entriesSortedByStartAt()
        return entries.first { candidate in
            candidate.id != entry.id && candidate.startAt >= entry.endAt
        } ?? entries.first { candidate in
            candidate.id != entry.id && candidate.startAt > entry.startAt
        }
    }

    private func lastCreatedEntry() throws -> TimeEntry? {
        var descriptor = FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func reconcileActionLinks() {
        _ = try? ActionCompletionService(modelContext: modelContext).reconcileAllLinks()
    }

    private func deleteContent(for entry: TimeEntry) throws {
        let documents = try TimeLedgerQueries(modelContext: modelContext).documents(ownerID: entry.id, ownerKind: ContentOwnerKind.timeEntry)
        let documentIDs = Set(documents.map(\.id))
        let attachments = try TimeLedgerQueries(modelContext: modelContext).attachments(documentIDs: documentIDs)
        let links = try TimeLedgerQueries(modelContext: modelContext).journalLinks(timeEntryID: entry.id)
        for attachment in attachments { modelContext.delete(attachment) }
        for document in documents { modelContext.delete(document) }
        for link in links { modelContext.delete(link) }
    }

    // MARK: - Generic Write Wrappers (facade for migrated services)

    /// Insert any PersistentModel through the engine.
    func insert<T: PersistentModel>(_ model: T) {
        modelContext.insert(model)
    }

    /// Delete any PersistentModel through the engine.
    func delete<T: PersistentModel>(_ model: T) {
        modelContext.delete(model)
    }

    /// Save the model context through the engine.
    func save() throws {
        try modelContext.save()
    }
}
