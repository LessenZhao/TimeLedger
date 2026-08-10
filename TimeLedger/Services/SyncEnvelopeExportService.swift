import EvolutionCore
import Foundation
import SwiftData

nonisolated struct PreparedSyncExport: Sendable {
    let json: String
    let entryCount: Int
    let thoughtCount: Int
}

/// File-exchange SyncBatch via EvolutionCore typed DTOs. No SQLite copy.
nonisolated struct SyncEnvelopeExportService {
    let modelContext: ModelContext
    var deviceId: String

    init(modelContext: ModelContext, deviceId: String? = nil) {
        self.modelContext = modelContext
        if let deviceId {
            self.deviceId = deviceId
        } else if let id = UserDefaults.standard.string(forKey: "pee.deviceId") {
            self.deviceId = id
        } else {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: "pee.deviceId")
            self.deviceId = id
        }
    }

    func exportSyncBatchJSON() throws -> String {
        try prepareSyncBatchJSON(range: nil, onlyConfirmed: false).json
    }

    func prepareSyncBatchJSON(
        range: ExportDateRange?,
        onlyConfirmed: Bool
    ) throws -> PreparedSyncExport {
        let allEntries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
        let journals = try modelContext.fetch(FetchDescriptor<JournalEntry>())
        let journalLinks = try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
        let entries = allEntries.filter { entry in
            let isInRange = range?.overlaps(startAt: entry.startAt, endAt: entry.endAt) ?? true
            return isInRange && (!onlyConfirmed || entry.status == TimeEntryStatus.confirmed.rawValue)
        }
        let entryIDs = Set(entries.map(\.id))

        let selectedJournals = journals.filter { journal in
            guard let range else { return true }
            let linkedEntryID = journalLinks.first { $0.journalEntryID == journal.id }?.timeEntryID
            return range.contains(journal.capturedAt)
                || linkedEntryID.map(entryIDs.contains) == true
        }

        let projectIDs = Set(entries.map(\.projectId))
        let allProjects = try modelContext.fetch(FetchDescriptor<Project>())
        let projects = range == nil
            ? allProjects
            : allProjects.filter { projectIDs.contains($0.id) }
        let cursors = range == nil
            ? try modelContext.fetch(FetchDescriptor<TimeCursor>())
            : []

        var envelopes: [AnySyncEnvelope] = []

        if let cursor = cursors.first {
            let revision = max(1, Int(cursor.updatedAt.timeIntervalSince1970) % 1_000_000_000)
            envelopes.append(try AnySyncEnvelope(
                deviceId: deviceId,
                entityType: .timeCursor,
                entityId: "cursor",
                revision: revision,
                updatedAt: cursor.updatedAt,
                payload: TimeCursorSyncPayload(
                    cursorAt: cursor.cursorAt,
                    updatedAt: cursor.updatedAt,
                    revision: revision
                )
            ))
        }

        for project in projects {
            envelopes.append(try AnySyncEnvelope(
                deviceId: deviceId,
                entityType: .project,
                entityId: project.id.uuidString,
                revision: 1,
                updatedAt: project.updatedAt,
                payload: ProjectSyncPayload(
                    id: project.id.uuidString,
                    name: project.name,
                    categoryName: project.categoryName,
                    isArchived: project.isArchived,
                    updatedAt: project.updatedAt
                )
            ))
        }

        for entry in entries {
            envelopes.append(try AnySyncEnvelope(
                deviceId: deviceId,
                entityType: .timeEntry,
                entityId: entry.id.uuidString,
                revision: revision(from: entry.updatedAt, created: entry.createdAt),
                updatedAt: entry.updatedAt,
                payload: TimeEntrySyncPayload(
                    id: entry.id.uuidString,
                    projectId: entry.projectId.uuidString,
                    projectNameSnapshot: entry.projectNameSnapshot,
                    categoryNameSnapshot: entry.categoryNameSnapshot,
                    startAt: entry.startAt,
                    endAt: entry.endAt,
                    note: document(ownerID: entry.id, kind: .timeEntry, in: documents)?.body ?? "",
                    status: entry.status,
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt
                )
            ))
        }

        for journal in selectedJournals {
            let content = document(ownerID: journal.id, kind: .journalEntry, in: documents)
            let link = journalLinks.first { $0.journalEntryID == journal.id }
            let updatedAt = max(journal.updatedAt, content?.updatedAt ?? journal.updatedAt)
            envelopes.append(try AnySyncEnvelope(
                deviceId: deviceId,
                entityType: .thoughtNote,
                entityId: journal.id.uuidString,
                revision: max(1, content?.revision ?? 1),
                updatedAt: updatedAt,
                payload: ThoughtNoteSyncPayload(
                    id: journal.id.uuidString,
                    body: content?.body ?? "",
                    capturedAt: journal.capturedAt,
                    anchorAt: journal.anchorAt,
                    linkedEntryId: link?.timeEntryID.uuidString,
                    linkSource: link?.linkSource ?? ThoughtLinkSource.none.rawValue,
                    createdAt: journal.createdAt,
                    updatedAt: updatedAt
                )
            ))
        }

        let batch = SyncBatchFile(
            deviceId: deviceId,
            exportedAt: Date(),
            envelopes: envelopes
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601Codec.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(batch)
        return PreparedSyncExport(
            json: String(data: data, encoding: .utf8) ?? "{}",
            entryCount: entries.count,
            thoughtCount: selectedJournals.count
        )
    }

    private func revision(from updated: Date, created: Date) -> Int {
        max(1, Int(updated.timeIntervalSince(created) / 60) + 1)
    }

    private func document(
        ownerID: UUID,
        kind: ContentOwnerKind,
        in documents: [ContentDocument]
    ) -> ContentDocument? {
        documents.first { $0.ownerID == ownerID && $0.ownerKindEnum == kind }
    }
}

private nonisolated struct TimeCursorSyncPayload: Codable, Sendable {
    let cursorAt: Date
    let updatedAt: Date
    let revision: Int
}
