import Foundation
import SwiftData

struct MediaLinkingService {
    let modelContext: ModelContext

    @discardableResult
    func tryAutoLink(_ moment: MediaMoment) throws -> Bool {
        guard moment.linkSourceEnum == .none else { return false }
        guard let entry = try bestCoveringEntry(for: moment.anchorAt) else { return false }

        moment.linkedEntryId = entry.id
        moment.linkSource = ThoughtLinkSource.auto.rawValue
        moment.updatedAt = Date()
        try modelContext.save()
        return true
    }

    @discardableResult
    func linkMediaForEntry(_ entry: TimeEntry) throws -> Int {
        let moments = try modelContext.fetch(FetchDescriptor<MediaMoment>())
        let candidates = moments.filter {
            $0.linkedEntryId == nil
            && $0.linkSourceEnum == .none
            && $0.anchorAt >= entry.startAt
            && $0.anchorAt <= entry.endAt
        }

        let now = Date()
        for moment in candidates {
            moment.linkedEntryId = entry.id
            moment.linkSource = ThoughtLinkSource.auto.rawValue
            moment.updatedAt = now
        }
        if !candidates.isEmpty {
            try modelContext.save()
        }
        return candidates.count
    }

    @discardableResult
    func reconcileAutoLinks() throws -> Int {
        let moments = try modelContext.fetch(FetchDescriptor<MediaMoment>())
        let entries = try modelContext.fetch(
            FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startAt)])
        )
        let entryByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var changed = 0
        let now = Date()

        for moment in moments where moment.linkSourceEnum != .manual {
            let currentIsValid = moment.linkedEntryId.flatMap { entryByID[$0] }.map {
                $0.startAt <= moment.anchorAt && $0.endAt >= moment.anchorAt
            } ?? false
            if currentIsValid {
                continue
            }

            let covering = entries.filter {
                $0.startAt <= moment.anchorAt && $0.endAt >= moment.anchorAt
            }
            let replacement = pickBestCovering(covering)
            let replacementID = replacement?.id
            let replacementSource = replacement == nil
                ? ThoughtLinkSource.none
                : ThoughtLinkSource.auto
            if moment.linkedEntryId != replacementID || moment.linkSourceEnum != replacementSource {
                moment.linkedEntryId = replacementID
                moment.linkSource = replacementSource.rawValue
                moment.updatedAt = now
                changed += 1
            }
        }

        if changed > 0 {
            try modelContext.save()
        }
        return changed
    }

    func manuallyLink(_ moment: MediaMoment, to entry: TimeEntry) throws {
        moment.linkedEntryId = entry.id
        moment.linkSource = ThoughtLinkSource.manual.rawValue
        moment.updatedAt = Date()
        try modelContext.save()
    }

    func unlink(_ moment: MediaMoment) throws {
        moment.linkedEntryId = nil
        moment.linkSource = ThoughtLinkSource.none.rawValue
        moment.updatedAt = Date()
        try modelContext.save()
    }

    private func bestCoveringEntry(for anchorAt: Date) throws -> TimeEntry? {
        let entries = try modelContext.fetch(
            FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startAt)])
        )
        return pickBestCovering(entries.filter {
            $0.startAt <= anchorAt && $0.endAt >= anchorAt
        })
    }

    private func pickBestCovering(_ entries: [TimeEntry]) -> TimeEntry? {
        guard !entries.isEmpty else { return nil }
        if entries.count == 1 { return entries[0] }
        let sorted = entries.sorted { $0.durationSeconds < $1.durationSeconds }
        guard sorted[0].durationSeconds != sorted[1].durationSeconds else { return nil }
        return sorted[0]
    }
}
