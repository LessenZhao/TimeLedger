import Foundation
import SwiftData

enum ActionCompletionError: LocalizedError {
    case emptyTitle
    case archivedItem
    case missingCompletion

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "事项名称不能为空。"
        case .archivedItem:
            "已归档事项不能标记完成。"
        case .missingCompletion:
            "今天还没有这条完成记录。"
        }
    }
}

struct ActionCompletionService {
    let modelContext: ModelContext
    let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    @discardableResult
    func createItem(title: String, sortOrder: Int = 0, now: Date = Date()) throws -> ActionItem {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ActionCompletionError.emptyTitle
        }

        let item = ActionItem(
            title: trimmed,
            sortOrder: sortOrder,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(item)
        try modelContext.save()
        return item
    }

    func updateItem(
        _ item: ActionItem,
        title: String,
        sortOrder: Int,
        isArchived: Bool,
        now: Date = Date()
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ActionCompletionError.emptyTitle
        }

        item.title = trimmed
        item.sortOrder = sortOrder
        item.isArchived = isArchived
        item.updatedAt = now
        try modelContext.save()
    }

    func completion(for item: ActionItem, on date: Date = Date()) throws -> ActionCompletion? {
        let day = calendar.startOfDay(for: date)
        return try allCompletions().first {
            $0.actionItemId == item.id && $0.dayStart == day
        }
    }

    @discardableResult
    func complete(_ item: ActionItem, now: Date = Date()) throws -> ActionCompletion {
        guard !item.isArchived else {
            throw ActionCompletionError.archivedItem
        }
        if let existing = try completion(for: item, on: now) {
            return existing
        }

        let completion = ActionCompletion(
            actionItemId: item.id,
            actionTitleSnapshot: item.title,
            completedAt: now,
            dayStart: calendar.startOfDay(for: now),
            linkedEntryId: try coveringEntry(at: now)?.id,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(completion)
        try modelContext.save()
        return completion
    }

    func undoCompletion(for item: ActionItem, on date: Date = Date()) throws {
        guard let completion = try completion(for: item, on: date) else {
            throw ActionCompletionError.missingCompletion
        }
        modelContext.delete(completion)
        try modelContext.save()
    }

    func completionsForEntry(_ entry: TimeEntry) throws -> [ActionCompletion] {
        try allCompletions()
            .filter { $0.linkedEntryId == entry.id }
            .sorted { $0.completedAt < $1.completedAt }
    }

    @discardableResult
    func linkCompletionsForEntry(_ entry: TimeEntry) throws -> Int {
        let unlinked = try allCompletions().filter {
            $0.linkedEntryId == nil && contains(entry, date: $0.completedAt)
        }
        guard !unlinked.isEmpty else { return 0 }

        let now = Date()
        for completion in unlinked {
            completion.linkedEntryId = entry.id
            completion.updatedAt = now
        }
        try modelContext.save()
        return unlinked.count
    }

    @discardableResult
    func reconcileAllLinks(now: Date = Date()) throws -> Int {
        let entries = try allEntries()
        let completions = try allCompletions()
        var changed = 0

        for completion in completions {
            let resolved = bestCoveringEntry(at: completion.completedAt, entries: entries)?.id
            if completion.linkedEntryId != resolved {
                completion.linkedEntryId = resolved
                completion.updatedAt = now
                changed += 1
            }
        }

        if changed > 0 {
            try modelContext.save()
        }
        return changed
    }

    private func allCompletions() throws -> [ActionCompletion] {
        try modelContext.fetch(
            FetchDescriptor<ActionCompletion>(sortBy: [SortDescriptor(\.completedAt)])
        )
    }

    private func allEntries() throws -> [TimeEntry] {
        try modelContext.fetch(
            FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startAt)])
        )
    }

    private func coveringEntry(at date: Date) throws -> TimeEntry? {
        bestCoveringEntry(at: date, entries: try allEntries())
    }

    private func bestCoveringEntry(at date: Date, entries: [TimeEntry]) -> TimeEntry? {
        entries
            .filter { contains($0, date: date) }
            .sorted {
                if $0.durationSeconds != $1.durationSeconds {
                    return $0.durationSeconds < $1.durationSeconds
                }
                if $0.startAt != $1.startAt {
                    return $0.startAt < $1.startAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .first
    }

    private func contains(_ entry: TimeEntry, date: Date) -> Bool {
        entry.startAt <= date && date < entry.endAt
    }
}
