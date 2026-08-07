import Foundation
import SwiftData

@MainActor
struct JournalContentService {
    let modelContext: ModelContext

    func link(_ journal: JournalEntry, to entry: TimeEntry) throws {
        let links = try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
        if let link = links.first(where: { $0.journalEntryID == journal.id }) {
            link.timeEntryID = entry.id
            link.linkSource = ThoughtLinkSource.manual.rawValue
            link.updatedAt = Date()
        } else {
            modelContext.insert(JournalTimeLink(
                id: journal.id,
                journalEntryID: journal.id,
                timeEntryID: entry.id,
                linkSource: .manual
            ))
        }
        try modelContext.save()
    }

    func unlink(_ journal: JournalEntry) throws {
        let links = try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
            .filter { $0.journalEntryID == journal.id }
        for link in links { modelContext.delete(link) }
        if !links.isEmpty { try modelContext.save() }
    }

    @discardableResult
    func linkUnlinkedJournals(to entry: TimeEntry) throws -> Int {
        let journals = try modelContext.fetch(FetchDescriptor<JournalEntry>())
        let links = try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
        let attachments = try modelContext.fetch(FetchDescriptor<ContentAttachment>())
        let linkedIDs = Set(links.map(\.journalEntryID))
        let candidates = journals.filter {
            !linkedIDs.contains($0.id)
                && !isMediaOnly($0, documents: documents, attachments: attachments)
                && $0.anchorAt >= entry.startAt
                && $0.anchorAt <= entry.endAt
        }
        for journal in candidates {
            modelContext.insert(
                JournalTimeLink(
                    journalEntryID: journal.id,
                    timeEntryID: entry.id,
                    linkSource: .auto
                )
            )
        }
        if !candidates.isEmpty { try modelContext.save() }
        return candidates.count
    }

    @discardableResult
    func reconcileAutoLinks() throws -> Int {
        let journals = try modelContext.fetch(FetchDescriptor<JournalEntry>())
        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
        let links = try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
        let attachments = try modelContext.fetch(FetchDescriptor<ContentAttachment>())
        let journalByID = Dictionary(uniqueKeysWithValues: journals.map { ($0.id, $0) })
        var changed = 0
        var removedLinkIDs: Set<UUID> = []

        for link in links where link.linkSource == ThoughtLinkSource.auto.rawValue {
            guard let journal = journalByID[link.journalEntryID] else {
                modelContext.delete(link)
                removedLinkIDs.insert(link.id)
                changed += 1
                continue
            }
            let covering = entries.filter { $0.startAt <= journal.anchorAt && $0.endAt >= journal.anchorAt }
            let replacement = covering.min { lhs, rhs in
                lhs.durationSeconds < rhs.durationSeconds
            }
            guard let replacement else {
                modelContext.delete(link)
                removedLinkIDs.insert(link.id)
                changed += 1
                continue
            }
            if link.timeEntryID != replacement.id {
                link.timeEntryID = replacement.id
                link.updatedAt = Date()
                changed += 1
            }
        }

        let linkedIDs = Set(links.filter { !removedLinkIDs.contains($0.id) }.map(\.journalEntryID))
        for journal in journals where !linkedIDs.contains(journal.id)
            && !isMediaOnly(journal, documents: documents, attachments: attachments) {
            let covering = entries.filter { $0.startAt <= journal.anchorAt && $0.endAt >= journal.anchorAt }
            if let entry = covering.min(by: { $0.durationSeconds < $1.durationSeconds }) {
                modelContext.insert(
                    JournalTimeLink(
                        journalEntryID: journal.id,
                        timeEntryID: entry.id,
                        linkSource: .auto
                    )
                )
                changed += 1
            }
        }
        if changed > 0 { try modelContext.save() }
        return changed
    }

    private func isMediaOnly(
        _ journal: JournalEntry,
        documents: [ContentDocument],
        attachments: [ContentAttachment]
    ) -> Bool {
        guard let document = documents.first(where: {
            $0.ownerID == journal.id && $0.ownerKindEnum == .journalEntry
        }) else { return false }
        return document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && attachments.contains { $0.contentDocumentID == document.id }
    }

    func delete(_ journal: JournalEntry) throws {
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
            .filter { $0.ownerID == journal.id && $0.ownerKindEnum == .journalEntry }
        let documentIDs = Set(documents.map(\.id))
        let attachments = try modelContext.fetch(FetchDescriptor<ContentAttachment>())
            .filter { documentIDs.contains($0.contentDocumentID) }
        let links = try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
            .filter { $0.journalEntryID == journal.id }
        try modelContext.transaction {
            for attachment in attachments { modelContext.delete(attachment) }
            for document in documents { modelContext.delete(document) }
            for link in links { modelContext.delete(link) }
            modelContext.delete(journal)
            try modelContext.save()
        }
    }
}
