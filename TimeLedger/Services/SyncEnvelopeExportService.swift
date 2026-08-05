import Foundation
import SwiftData

nonisolated struct PreparedSyncExport: Sendable {
    let json: String
    let entryCount: Int
    let thoughtCount: Int
}

/// File-exchange SyncBatch (matches EvolutionCore SyncBatchFile schema). No SQLite copy.
nonisolated struct SyncEnvelopeExportService {
    let modelContext: ModelContext
    var deviceId: String
    private let dateFormatter: ISO8601DateFormatter

    init(modelContext: ModelContext, deviceId: String? = nil) {
        self.modelContext = modelContext
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        dateFormatter = formatter
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
        let entries = allEntries.filter { entry in
            let isInRange = range?.overlaps(startAt: entry.startAt, endAt: entry.endAt) ?? true
            return isInRange && (!onlyConfirmed || entry.status == TimeEntryStatus.confirmed.rawValue)
        }
        let entryIDs = Set(entries.map(\.id))

        let allThoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
        let thoughts = allThoughts.filter { thought in
            guard let range else { return true }
            return range.contains(thought.capturedAt)
                || thought.linkedEntryId.map(entryIDs.contains) == true
        }

        let projectIDs = Set(entries.map(\.projectId))
        let allProjects = try modelContext.fetch(FetchDescriptor<Project>())
        let projects = range == nil
            ? allProjects
            : allProjects.filter { projectIDs.contains($0.id) }
        let cursors = range == nil
            ? try modelContext.fetch(FetchDescriptor<TimeCursor>())
            : []

        var envelopes: [[String: Any]] = []

        if let cursor = cursors.first {
            envelopes.append(try envelope(
                entityType: "timeCursor",
                entityId: "cursor",
                revision: max(1, Int(cursor.updatedAt.timeIntervalSince1970) % 1_000_000_000),
                updatedAt: cursor.updatedAt,
                payload: [
                    "cursorAt": iso(cursor.cursorAt),
                    "updatedAt": iso(cursor.updatedAt),
                    "revision": max(1, Int(cursor.updatedAt.timeIntervalSince1970) % 1_000_000_000)
                ]
            ))
        }

        for p in projects {
            envelopes.append(try envelope(
                entityType: "project",
                entityId: p.id.uuidString,
                revision: 1,
                updatedAt: p.updatedAt,
                payload: [
                    "id": p.id.uuidString,
                    "name": p.name,
                    "categoryName": p.categoryName,
                    "isArchived": p.isArchived,
                    "updatedAt": iso(p.updatedAt)
                ]
            ))
        }

        for e in entries {
            envelopes.append(try envelope(
                entityType: "timeEntry",
                entityId: e.id.uuidString,
                revision: revision(from: e.updatedAt, created: e.createdAt),
                updatedAt: e.updatedAt,
                payload: [
                    "id": e.id.uuidString,
                    "projectId": e.projectId.uuidString,
                    "projectNameSnapshot": e.projectNameSnapshot,
                    "categoryNameSnapshot": e.categoryNameSnapshot,
                    "startAt": iso(e.startAt),
                    "endAt": iso(e.endAt),
                    "note": e.note,
                    "status": e.status,
                    "createdAt": iso(e.createdAt),
                    "updatedAt": iso(e.updatedAt)
                ]
            ))
        }

        for t in thoughts {
            envelopes.append(try envelope(
                entityType: "thoughtNote",
                entityId: t.id.uuidString,
                revision: revision(from: t.updatedAt, created: t.createdAt),
                updatedAt: t.updatedAt,
                payload: [
                    "id": t.id.uuidString,
                    "body": t.body,
                    "capturedAt": iso(t.capturedAt),
                    "anchorAt": iso(t.anchorAt),
                    "linkedEntryId": t.linkedEntryId?.uuidString ?? "",
                    "linkSource": t.linkSource,
                    "createdAt": iso(t.createdAt),
                    "updatedAt": iso(t.updatedAt)
                ]
            ))
        }

        let batch: [String: Any] = [
            "protocolVersion": "1.0",
            "deviceId": deviceId,
            "exportedAt": iso(Date()),
            "envelopes": envelopes
        ]
        let data = try JSONSerialization.data(withJSONObject: batch, options: [.prettyPrinted, .sortedKeys])
        return PreparedSyncExport(
            json: String(data: data, encoding: .utf8) ?? "{}",
            entryCount: entries.count,
            thoughtCount: thoughts.count
        )
    }

    private func envelope(
        entityType: String,
        entityId: String,
        revision: Int,
        updatedAt: Date,
        payload: [String: Any]
    ) throws -> [String: Any] {
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"
        return [
            "protocolVersion": "1.0",
            "deviceId": deviceId,
            "entityType": entityType,
            "entityId": entityId,
            "operation": "upsert",
            "revision": revision,
            "updatedAt": iso(updatedAt),
            "payloadJSON": payloadJSON
        ]
    }

    private func revision(from updated: Date, created: Date) -> Int {
        max(1, Int(updated.timeIntervalSince(created) / 60) + 1)
    }

    private func iso(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
