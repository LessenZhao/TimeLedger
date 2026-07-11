import Foundation
import SwiftData

enum TimeCursorError: LocalizedError {
    case emptySegment
    case cannotUndo
    case cannotDelete
    case startCannotMoveEarlier
    case endOverlapsNext

    var errorDescription: String? {
        switch self {
        case .emptySegment:
            "当前未记录时间不足，无法生成记录。"
        case .cannotUndo:
            "没有可撤销的草稿记录。"
        case .cannotDelete:
            "只能删除草稿记录。"
        case .startCannotMoveEarlier:
            "开始时间不能早于当前开始时间。"
        case .endOverlapsNext:
            "结束时间不能与后一段重叠。"
        }
    }
}

struct TimeCursorService {
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
        cursor.cursorAt = now
        cursor.updatedAt = now
        try modelContext.save()
        _ = try? ThoughtLinkingService(modelContext: modelContext).linkThoughtsForEntry(entry: entry)
        return entry
    }

    @discardableResult
    func recordSegment(project: Project, startAt: Date, endAt: Date, note: String = "") throws -> TimeEntry {
        let cursor = try getOrCreateCursor(now: startAt)
        guard endAt > startAt else {
            throw TimeCursorError.emptySegment
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
            note: note
        )

        modelContext.insert(entry)
        cursor.cursorAt = endAt
        cursor.updatedAt = endAt
        try modelContext.save()
        _ = try? ThoughtLinkingService(modelContext: modelContext).linkThoughtsForEntry(entry: entry)
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

    func undoLastEntry() throws {
        let cursor = try getOrCreateCursor()
        guard let last = try lastCreatedEntry(),
              last.status == TimeEntryStatus.draft.rawValue,
              last.endAt == cursor.cursorAt
        else {
            throw TimeCursorError.cannotUndo
        }

        cursor.cursorAt = last.startAt
        cursor.updatedAt = Date()
        modelContext.delete(last)
        try modelContext.save()
    }

    func updateEntry(
        _ entry: TimeEntry,
        project: Project,
        note: String,
        startAt: Date,
        endAt: Date
    ) throws {
        let originalStartAt = entry.startAt
        let originalEndAt = entry.endAt

        entry.projectId = project.id
        entry.projectNameSnapshot = project.name
        entry.categoryNameSnapshot = project.categoryName
        entry.note = note
        entry.updatedAt = Date()

        if entry.status == TimeEntryStatus.draft.rawValue {
            guard endAt > startAt else {
                throw ValidationError.invalidTimeRange
            }
            guard startAt >= originalStartAt else {
                throw TimeCursorError.startCannotMoveEarlier
            }

            if let next = try nextEntry(after: entry), endAt > next.startAt {
                throw TimeCursorError.endOverlapsNext
            }

            try ValidationService(modelContext: modelContext).validateEntry(
                projectId: project.id,
                startAt: startAt,
                endAt: endAt,
                excluding: entry.id
            )

            if startAt > originalStartAt {
                let unknown = try SystemProject.getOrCreateUnknown(modelContext: modelContext)
                let freed = TimeEntry(
                    projectId: unknown.id,
                    projectNameSnapshot: unknown.name,
                    categoryNameSnapshot: unknown.categoryName,
                    startAt: originalStartAt,
                    endAt: startAt,
                    status: .draft
                )
                modelContext.insert(freed)
                _ = try? ThoughtLinkingService(modelContext: modelContext).linkThoughtsForEntry(entry: freed)
            }

            entry.startAt = startAt
            entry.endAt = endAt

            let cursor = try getOrCreateCursor()
            if cursor.cursorAt == originalEndAt {
                cursor.cursorAt = endAt
                cursor.updatedAt = Date()
            }
        }

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
            modelContext.delete(entry)
            try modelContext.save()
            return
        }

        if let next = try nextEntry(after: entry) {
            next.startAt = deletedStart
            next.updatedAt = Date()
        }

        modelContext.delete(entry)
        try modelContext.save()
    }

    func nextEntry(after entry: TimeEntry) throws -> TimeEntry? {
        let entries = try modelContext.fetch(
            FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startAt)])
        )
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
}
