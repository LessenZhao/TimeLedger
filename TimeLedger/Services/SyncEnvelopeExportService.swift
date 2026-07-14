import Foundation
import SwiftData

/// File-exchange SyncBatch (matches EvolutionCore SyncBatchFile schema). No SQLite copy.
struct SyncEnvelopeExportService {
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
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
        let thoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
        let cursors = try modelContext.fetch(FetchDescriptor<TimeCursor>())

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
        return String(data: data, encoding: .utf8) ?? "{}"
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
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
