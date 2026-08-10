import Foundation
import SwiftData

enum TimeCursorError: LocalizedError {
    case emptySegment
    case cannotUndo
    case cannotDelete
    case startCannotMoveEarlier
    case endOverlapsNext
    case squeezesNextDraft
    case endAfterNow
    case startBeforeCursor

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
        case .squeezesNextDraft:
            "结束时间会挤掉下一段草稿。"
        case .endAfterNow:
            "结束时间不能晚于当前时间。"
        case .startBeforeCursor:
            "开始时间不能早于未记录起点。"
        }
    }
}

/// 兼容 facade：只转发给 TimeLedgerEngine，不再直接写数据库。
struct TimeCursorService {
    let modelContext: ModelContext

    private var engine: TimeLedgerEngine {
        TimeLedgerEngine(modelContext: modelContext)
    }

    func getOrCreateCursor(now: Date = Date()) throws -> TimeCursor {
        try engine.getOrCreateCursor(now: now)
    }

    func currentUnclassifiedDuration(now: Date = Date()) throws -> TimeInterval {
        try engine.currentUnclassifiedDuration(now: now)
    }

    @discardableResult
    func quickRecord(project: Project, now: Date = Date()) throws -> TimeEntry {
        try engine.quickRecord(project: project, now: now)
    }

    @discardableResult
    func recordSegment(
        project: Project,
        startAt: Date,
        endAt: Date,
        note: String = "",
        now: Date = Date()
    ) throws -> TimeEntry {
        try engine.recordSegment(project: project, startAt: startAt, endAt: endAt, note: note, now: now)
    }

    func skipSegment(to date: Date) throws {
        try engine.skipSegment(to: date)
    }

    func canUndoLastEntry() throws -> Bool {
        try engine.canUndoLastEntry()
    }

    func undoLastEntry(expectedId: UUID? = nil) throws {
        try engine.undoLastEntry(expectedId: expectedId)
    }

    func lastEntryBeforeCursor() throws -> TimeEntry? {
        try engine.lastEntryBeforeCursor()
    }

    func updateEntry(
        _ entry: TimeEntry,
        project: Project,
        note: String?,
        startAt: Date,
        endAt: Date,
        now: Date = Date()
    ) throws {
        try engine.updateEntry(
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
        try engine.validateEntryUpdate(
            entry,
            project: project,
            startAt: startAt,
            endAt: endAt,
            now: now
        )
    }

    func updateNote(_ entry: TimeEntry, note: String, now: Date = Date()) throws {
        try engine.updateNote(entry, note: note, now: now)
    }

    func cancelConfirmation(_ entry: TimeEntry) throws {
        try engine.cancelConfirmation(entry)
    }

    func deleteDraftEntry(_ entry: TimeEntry) throws {
        try engine.deleteDraftEntry(entry)
    }
}
