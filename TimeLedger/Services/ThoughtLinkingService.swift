import Foundation
import SwiftData

struct ThoughtLinkingService {
    let modelContext: ModelContext

    // MARK: - Quick Capture

    @discardableResult
    func quickCaptureThought(body: String, now: Date = Date()) throws -> ThoughtNote {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let thought = ThoughtNote(
            body: trimmed,
            capturedAt: now,
            anchorAt: now
        )
        modelContext.insert(thought)
        try modelContext.save()
        try tryAutoLinkThought(thought: thought)
        return thought
    }

    // MARK: - Auto Link (single thought)

    @discardableResult
    func tryAutoLinkThought(thought: ThoughtNote) throws -> Bool {
        guard thought.linkSourceEnum == .none else { return false }

        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startAt)]))
        let covering = entries.filter { entry in
            entry.startAt <= thought.anchorAt && entry.endAt >= thought.anchorAt
        }

        guard !covering.isEmpty else { return false }

        // If multiple cover (abnormal), pick the shortest duration; tie → keep unlinked
        if covering.count == 1 {
            let entry = covering[0]
            thought.linkedEntryId = entry.id
            thought.linkSource = ThoughtLinkSource.auto.rawValue
            thought.updatedAt = Date()
            try modelContext.save()
            try ThoughtMediaLinkService(modelContext: modelContext)
                .synchronizeAttachedMedia(for: thought)
            return true
        } else {
            let sorted = covering.sorted { a, b in
                a.durationSeconds < b.durationSeconds
            }
            if sorted[0].durationSeconds == sorted[1].durationSeconds {
                // ambiguous tie → don't link
                return false
            }
            let entry = sorted[0]
            thought.linkedEntryId = entry.id
            thought.linkSource = ThoughtLinkSource.auto.rawValue
            thought.updatedAt = Date()
            try modelContext.save()
            try ThoughtMediaLinkService(modelContext: modelContext)
                .synchronizeAttachedMedia(for: thought)
            return true
        }
    }

    // MARK: - Link Thoughts For New Entry (bulk)

    /// When a new TimeEntry is created, find all unlinked ThoughtNotes whose anchorAt
    /// falls within the entry's time range and auto-link them.
    @discardableResult
    func linkThoughtsForEntry(entry: TimeEntry) throws -> Int {
        let thoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
        let toLink = thoughts.filter { thought in
            thought.linkedEntryId == nil
            && thought.linkSourceEnum == .none
            && thought.anchorAt >= entry.startAt
            && thought.anchorAt <= entry.endAt
        }

        let now = Date()
        for thought in toLink {
            thought.linkedEntryId = entry.id
            thought.linkSource = ThoughtLinkSource.auto.rawValue
            thought.updatedAt = now
        }

        if !toLink.isEmpty {
            try modelContext.save()
            for thought in toLink {
                try ThoughtMediaLinkService(modelContext: modelContext)
                    .synchronizeAttachedMedia(for: thought)
            }
        }
        return toLink.count
    }

    // MARK: - Relink Auto Thoughts For Date

    /// Conservatively re-evaluate auto-linked thoughts for a given date.
    /// Only touches linkSource = .none (tries to link) or .auto whose link is stale.
    /// Manual links are never touched.
    @discardableResult
    func relinkAutoThoughtsForDate(_ date: Date, calendar: Calendar = .current) throws -> Int {
        let dayRange = DateRangeService.naturalDayRange(for: date, calendar: calendar)
        let thoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startAt)]))

        var relinkedCount = 0
        let now = Date()

        for thought in thoughts {
            // Only consider thoughts whose anchorAt falls on this day
            guard thought.anchorAt >= dayRange.lowerBound,
                  thought.anchorAt < dayRange.upperBound else {
                continue
            }

            switch thought.linkSourceEnum {
            case .manual:
                continue
            case .none:
                // Try to auto-link
                let covering = entries.filter { entry in
                    entry.startAt <= thought.anchorAt && entry.endAt >= thought.anchorAt
                }
                if let best = pickBestCovering(covering) {
                    thought.linkedEntryId = best.id
                    thought.linkSource = ThoughtLinkSource.auto.rawValue
                    thought.updatedAt = now
                    relinkedCount += 1
                }
            case .auto:
                // Check if current link is still valid
                if let linkedId = thought.linkedEntryId,
                   let linkedEntry = entries.first(where: { $0.id == linkedId }) {
                    if thought.anchorAt < linkedEntry.startAt || thought.anchorAt > linkedEntry.endAt {
                        // Stale: entry no longer covers anchorAt → try to find a new one
                        let covering = entries.filter { entry in
                            entry.startAt <= thought.anchorAt && entry.endAt >= thought.anchorAt
                        }
                        if let best = pickBestCovering(covering) {
                            thought.linkedEntryId = best.id
                            thought.updatedAt = now
                            relinkedCount += 1
                        } else {
                            // Unlink
                            thought.linkedEntryId = nil
                            thought.linkSource = ThoughtLinkSource.none.rawValue
                            thought.updatedAt = now
                            relinkedCount += 1
                        }
                    }
                } else {
                    // Linked entry no longer exists → try to re-link
                    let covering = entries.filter { entry in
                        entry.startAt <= thought.anchorAt && entry.endAt >= thought.anchorAt
                    }
                    if let best = pickBestCovering(covering) {
                        thought.linkedEntryId = best.id
                        thought.updatedAt = now
                        relinkedCount += 1
                    } else {
                        thought.linkedEntryId = nil
                        thought.linkSource = ThoughtLinkSource.none.rawValue
                        thought.updatedAt = now
                        relinkedCount += 1
                    }
                }
            }
        }

        if relinkedCount > 0 {
            try modelContext.save()
            for thought in thoughts {
                try ThoughtMediaLinkService(modelContext: modelContext)
                    .synchronizeAttachedMedia(for: thought)
            }
        }
        return relinkedCount
    }

    // MARK: - Manual Add / Link / Unlink

    @discardableResult
    func addThought(to entry: TimeEntry, body: String, now: Date = Date()) throws -> ThoughtNote {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let thought = ThoughtNote(
            body: trimmed,
            capturedAt: now,
            anchorAt: now,
            linkedEntryId: entry.id,
            linkSource: .manual
        )
        modelContext.insert(thought)
        try modelContext.save()
        return thought
    }

    func manuallyLinkThought(_ thought: ThoughtNote, to entry: TimeEntry) throws {
        thought.linkedEntryId = entry.id
        thought.linkSource = ThoughtLinkSource.manual.rawValue
        thought.updatedAt = Date()
        try modelContext.save()
        try ThoughtMediaLinkService(modelContext: modelContext)
            .synchronizeAttachedMedia(for: thought)
    }

    func unlinkThought(_ thought: ThoughtNote) throws {
        thought.linkedEntryId = nil
        thought.linkSource = ThoughtLinkSource.none.rawValue
        thought.updatedAt = Date()
        try modelContext.save()
        try ThoughtMediaLinkService(modelContext: modelContext)
            .synchronizeAttachedMedia(for: thought)
    }

    // MARK: - Queries

    func thoughtsForEntry(_ entry: TimeEntry) throws -> [ThoughtNote] {
        let thoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>(
            sortBy: [SortDescriptor(\.capturedAt)]
        ))
        return thoughts.filter { $0.linkedEntryId == entry.id }
    }

    func thoughtCountForEntry(_ entry: TimeEntry) throws -> Int {
        try thoughtsForEntry(entry).count
    }

    func thoughtsCapturedOnDate(_ date: Date, calendar: Calendar = .current) throws -> [ThoughtNote] {
        let dayRange = DateRangeService.naturalDayRange(for: date, calendar: calendar)
        let thoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>(
            sortBy: [SortDescriptor(\.capturedAt)]
        ))
        return thoughts.filter { thought in
            thought.capturedAt >= dayRange.lowerBound && thought.capturedAt < dayRange.upperBound
        }
    }

    func unlinkedThoughtsCapturedOnDate(_ date: Date, calendar: Calendar = .current) throws -> [ThoughtNote] {
        try thoughtsCapturedOnDate(date, calendar: calendar).filter { $0.linkedEntryId == nil }
    }

    // MARK: - Update / Delete

    func updateThought(_ thought: ThoughtNote, body: String) throws {
        thought.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        thought.updatedAt = Date()
        try modelContext.save()
    }

    func deleteThought(_ thought: ThoughtNote) throws {
        try ThoughtMediaLinkService(modelContext: modelContext).removeLinks(for: thought)
        modelContext.delete(thought)
        try modelContext.save()
    }

    // MARK: - Helpers

    private func pickBestCovering(_ entries: [TimeEntry]) -> TimeEntry? {
        guard !entries.isEmpty else { return nil }
        if entries.count == 1 { return entries[0] }
        let sorted = entries.sorted { $0.durationSeconds < $1.durationSeconds }
        if sorted[0].durationSeconds == sorted[1].durationSeconds {
            return nil // ambiguous tie
        }
        return sorted[0]
    }
}
