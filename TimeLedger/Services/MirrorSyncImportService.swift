import Foundation
import SwiftData

/// Applies Mac → phone SyncBatch into local SwiftData (mirror write-back).
struct MirrorSyncImportService {
    let modelContext: ModelContext

    enum ImportError: LocalizedError {
        case invalidJSON
        case invalidDate(String)

        var errorDescription: String? {
            switch self {
            case .invalidJSON: return "无法解析同步文件"
            case .invalidDate(let s): return "日期无效: \(s)"
            }
        }
    }

    @discardableResult
    func importMacBatchJSON(_ json: String) throws -> Int {
        guard let data = json.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let envelopes = root["envelopes"] as? [[String: Any]]
        else { throw ImportError.invalidJSON }

        var applied = 0
        for env in envelopes {
            let entityType = env["entityType"] as? String ?? ""
            let operation = env["operation"] as? String ?? "upsert"
            let entityId = env["entityId"] as? String ?? ""
            let payloadJSON = env["payloadJSON"] as? String ?? "{}"
            let payload = (try? JSONSerialization.jsonObject(with: Data(payloadJSON.utf8))) as? [String: Any] ?? [:]

            switch entityType {
            case "timeEntry":
                if operation == "delete" {
                    if let uuid = UUID(uuidString: entityId) {
                        try deleteEntry(id: uuid)
                        applied += 1
                    }
                } else {
                    try upsertEntry(payload)
                    applied += 1
                }
            case "thoughtNote":
                if operation == "delete", let uuid = UUID(uuidString: entityId) {
                    try deleteJournal(id: uuid)
                } else {
                    try upsertJournal(payload)
                }
                applied += 1
            case "timeCursor":
                try upsertCursor(payload)
                applied += 1
            case "project":
                try upsertProject(payload)
                applied += 1
            default:
                break
            }
        }
        try modelContext.save()
        return applied
    }

    func importMacBatchFile(at url: URL) throws -> Int {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try importMacBatchJSON(text)
    }

    private func upsertEntry(_ p: [String: Any]) throws {
        guard let idStr = p["id"] as? String, let id = UUID(uuidString: idStr),
              let projectIdStr = p["projectId"] as? String, let projectId = UUID(uuidString: projectIdStr)
        else { return }

        let startAt = try date(p["startAt"])
        let endAt = try date(p["endAt"])
        let createdAt = try date(p["createdAt"])
        let updatedAt = try date(p["updatedAt"])
        let status = p["status"] as? String ?? "draft"
        let note = p["note"] as? String ?? ""
        let name = p["projectNameSnapshot"] as? String ?? ""
        let cat = p["categoryNameSnapshot"] as? String ?? ""

        var descriptor = FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.projectId = projectId
            existing.projectNameSnapshot = name
            existing.categoryNameSnapshot = cat
            existing.startAt = startAt
            existing.endAt = endAt
            existing.status = status
            existing.updatedAt = updatedAt
            try upsertDocument(
                ownerID: existing.id,
                ownerKind: .timeEntry,
                body: note,
                createdAt: existing.createdAt,
                updatedAt: updatedAt
            )
        } else {
            let entry = TimeEntry(
                id: id,
                projectId: projectId,
                projectNameSnapshot: name,
                categoryNameSnapshot: cat,
                startAt: startAt,
                endAt: endAt,
                note: "",
                status: TimeEntryStatus(rawValue: status) ?? .draft,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            modelContext.insert(entry)
            try upsertDocument(
                ownerID: entry.id,
                ownerKind: .timeEntry,
                body: note,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private func deleteEntry(id: UUID) throws {
        var descriptor = FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
            for document in documents where document.ownerID == existing.id && document.ownerKindEnum == .timeEntry {
                let attachments = try modelContext.fetch(FetchDescriptor<ContentAttachment>())
                    .filter { $0.contentDocumentID == document.id }
                for attachment in attachments { modelContext.delete(attachment) }
                modelContext.delete(document)
            }
            let links = try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
                .filter { $0.timeEntryID == existing.id }
            for link in links { modelContext.delete(link) }
            modelContext.delete(existing)
        }
    }

    private func upsertJournal(_ p: [String: Any]) throws {
        guard let idStr = p["id"] as? String, let id = UUID(uuidString: idStr) else { return }
        let body = p["body"] as? String ?? ""
        let capturedAt = try date(p["capturedAt"])
        let anchorAt = try date(p["anchorAt"])
        let createdAt = try date(p["createdAt"])
        let updatedAt = try date(p["updatedAt"])
        let linkSource = p["linkSource"] as? String ?? "none"
        let linkedRaw = p["linkedEntryId"] as? String ?? ""
        let linked = linkedRaw.isEmpty ? nil : UUID(uuidString: linkedRaw)

        let journals = try modelContext.fetch(FetchDescriptor<JournalEntry>())
        if let existing = journals.first(where: { $0.id == id }) {
            existing.capturedAt = capturedAt
            existing.anchorAt = anchorAt
            existing.updatedAt = updatedAt
        } else {
            modelContext.insert(JournalEntry(
                id: id,
                capturedAt: capturedAt,
                anchorAt: anchorAt,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }
        try upsertDocument(
            ownerID: id,
            ownerKind: .journalEntry,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let links = try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
        if let linked {
            if let existing = links.first(where: { $0.journalEntryID == id }) {
                existing.timeEntryID = linked
                existing.linkSource = linkSource
                existing.updatedAt = updatedAt
            } else {
                modelContext.insert(JournalTimeLink(
                    id: id,
                    journalEntryID: id,
                    timeEntryID: linked,
                    linkSource: ThoughtLinkSource(rawValue: linkSource) ?? .none,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                ))
            }
        } else {
            for existing in links where existing.journalEntryID == id {
                modelContext.delete(existing)
            }
        }
    }

    private func deleteJournal(id: UUID) throws {
        guard let journal = try modelContext.fetch(FetchDescriptor<JournalEntry>())
            .first(where: { $0.id == id }) else { return }
        try JournalContentService(modelContext: modelContext).delete(journal)
    }

    private func upsertDocument(
        ownerID: UUID,
        ownerKind: ContentOwnerKind,
        body: String,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
        if let document = documents.first(where: {
            $0.ownerID == ownerID && $0.ownerKindEnum == ownerKind
        }) {
            if document.body != body {
                document.body = body
                document.revision += 1
            }
            document.updatedAt = updatedAt
        } else {
            modelContext.insert(ContentDocument(
                id: ownerID,
                ownerID: ownerID,
                ownerKind: ownerKind,
                body: body,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }
    }

    private func upsertCursor(_ p: [String: Any]) throws {
        let cursorAt = try date(p["cursorAt"])
        let updatedAt = try date(p["updatedAt"])
        var descriptor = FetchDescriptor<TimeCursor>()
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            // Only move cursor forward or accept explicit mac revision by updatedAt
            if updatedAt >= existing.updatedAt {
                existing.cursorAt = cursorAt
                existing.updatedAt = updatedAt
            }
        } else {
            modelContext.insert(TimeCursor(cursorAt: cursorAt, updatedAt: updatedAt))
        }
    }

    private func upsertProject(_ p: [String: Any]) throws {
        guard let idStr = p["id"] as? String, let id = UUID(uuidString: idStr) else { return }
        let name = p["name"] as? String ?? ""
        let category = p["categoryName"] as? String ?? ""
        let archived = p["isArchived"] as? Bool ?? false
        let updatedAt = (try? date(p["updatedAt"])) ?? Date()

        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.name = name
            existing.categoryName = category
            existing.isArchived = archived
            existing.updatedAt = updatedAt
        } else {
            let project = Project(id: id, name: name, categoryName: category)
            project.isArchived = archived
            project.updatedAt = updatedAt
            modelContext.insert(project)
        }
    }

    private func date(_ value: Any?) throws -> Date {
        guard let raw = value as? String else { throw ImportError.invalidDate("nil") }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: raw) { return d }
        throw ImportError.invalidDate(raw)
    }
}
