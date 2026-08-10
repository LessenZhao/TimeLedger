import EvolutionCore
import Foundation
import SwiftData

@MainActor
struct ImportCommandHandler {
    let modelContext: ModelContext

    private var queries: TimeLedgerQueries {
        TimeLedgerQueries(modelContext: modelContext)
    }


    enum ImportError: LocalizedError {
        case invalidJSON

        var errorDescription: String? {
            switch self {
            case .invalidJSON: return "无法解析同步文件"
            }
        }
    }

    @discardableResult
    func importMacBatchJSON(_ json: String) throws -> Int {
        guard let data = json.data(using: .utf8) else { throw ImportError.invalidJSON }
        let batch: SyncBatchFile
        do {
            batch = try ISO8601Codec.decoder.decode(SyncBatchFile.self, from: data)
        } catch {
            throw ImportError.invalidJSON
        }

        var applied = 0
        for envelope in batch.envelopes {
            switch envelope.entityType {
            case .timeEntry:
                if envelope.operation == .delete {
                    if let uuid = UUID(uuidString: envelope.entityId) {
                        try deleteEntry(id: uuid)
                        applied += 1
                    }
                } else {
                    let payload = try envelope.decodePayload(TimeEntrySyncPayload.self)
                    try upsertEntry(payload)
                    applied += 1
                }
            case .thoughtNote:
                if envelope.operation == .delete, let uuid = UUID(uuidString: envelope.entityId) {
                    try deleteJournal(id: uuid)
                } else {
                    let payload = try envelope.decodePayload(ThoughtNoteSyncPayload.self)
                    try upsertJournal(payload)
                }
                applied += 1
            case .timeCursor:
                let payload = try envelope.decodePayload(TimeCursorSyncPayload.self)
                try upsertCursor(payload)
                applied += 1
            case .project:
                let payload = try envelope.decodePayload(ProjectSyncPayload.self)
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

    private func upsertEntry(_ payload: TimeEntrySyncPayload) throws {
        guard let id = UUID(uuidString: payload.id),
              let projectId = UUID(uuidString: payload.projectId)
        else { return }

        var descriptor = FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.projectId = projectId
            existing.projectNameSnapshot = payload.projectNameSnapshot
            existing.categoryNameSnapshot = payload.categoryNameSnapshot
            existing.startAt = payload.startAt
            existing.endAt = payload.endAt
            existing.status = payload.status
            existing.updatedAt = payload.updatedAt
            try upsertDocument(
                ownerID: existing.id,
                ownerKind: .timeEntry,
                body: payload.note,
                createdAt: existing.createdAt,
                updatedAt: payload.updatedAt
            )
        } else {
            let entry = TimeEntry(
                id: id,
                projectId: projectId,
                projectNameSnapshot: payload.projectNameSnapshot,
                categoryNameSnapshot: payload.categoryNameSnapshot,
                startAt: payload.startAt,
                endAt: payload.endAt,
                note: "",
                status: TimeEntryStatus(rawValue: payload.status) ?? .draft,
                createdAt: payload.createdAt,
                updatedAt: payload.updatedAt
            )
            modelContext.insert(entry)
            try upsertDocument(
                ownerID: entry.id,
                ownerKind: .timeEntry,
                body: payload.note,
                createdAt: payload.createdAt,
                updatedAt: payload.updatedAt
            )
        }
    }

    private func deleteEntry(id: UUID) throws {
        var descriptor = FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            let documents = try queries.documents(ownerID: existing.id, ownerKind: .timeEntry)
            for document in documents {
                let attachments = try queries.attachments(documentID: document.id)
                for attachment in attachments { modelContext.delete(attachment) }
                modelContext.delete(document)
            }
            let links = try queries.journalLinks(timeEntryID: existing.id)
            for link in links { modelContext.delete(link) }
            modelContext.delete(existing)
        }
    }

    private func upsertJournal(_ payload: ThoughtNoteSyncPayload) throws {
        guard let id = UUID(uuidString: payload.id) else { return }
        let linkSource = payload.linkSource
        let linked = payload.linkedEntryId.flatMap(UUID.init(uuidString:))

        if let existing = try queries.journal(id: id) {
            existing.capturedAt = payload.capturedAt
            existing.anchorAt = payload.anchorAt
            existing.updatedAt = payload.updatedAt
        } else {
            modelContext.insert(JournalEntry(
                id: id,
                capturedAt: payload.capturedAt,
                anchorAt: payload.anchorAt,
                createdAt: payload.createdAt,
                updatedAt: payload.updatedAt
            ))
        }
        try upsertDocument(
            ownerID: id,
            ownerKind: .journalEntry,
            body: payload.body,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt
        )
        if let linked {
            if let existing = try queries.journalLink(journalEntryID: id) {
                existing.timeEntryID = linked
                existing.linkSource = linkSource
                existing.updatedAt = payload.updatedAt
            } else {
                modelContext.insert(JournalTimeLink(
                    id: id,
                    journalEntryID: id,
                    timeEntryID: linked,
                    linkSource: JournalLinkSource(rawValue: linkSource) ?? .none,
                    createdAt: payload.createdAt,
                    updatedAt: payload.updatedAt
                ))
            }
        } else {
            for existing in try queries.journalLinks(journalEntryID: id) {
                modelContext.delete(existing)
            }
        }
    }

    private func deleteJournal(id: UUID) throws {
        guard let journal = try queries.journal(id: id) else { return }
        try TimeLedgerEngine(modelContext: modelContext).delete(journal)
    }

    private func upsertDocument(
        ownerID: UUID,
        ownerKind: ContentOwnerKind,
        body: String,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        if let document = try queries.document(ownerID: ownerID, ownerKind: ownerKind) {
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

    private func upsertCursor(_ payload: TimeCursorSyncPayload) throws {
        if let existing = try queries.cursor() {
            if payload.updatedAt >= existing.updatedAt {
                existing.cursorAt = payload.cursorAt
                existing.updatedAt = payload.updatedAt
            }
        } else {
            modelContext.insert(TimeCursor(cursorAt: payload.cursorAt, updatedAt: payload.updatedAt))
        }
    }

    private func upsertProject(_ payload: ProjectSyncPayload) throws {
        guard let id = UUID(uuidString: payload.id) else { return }
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.name = payload.name
            existing.categoryName = payload.categoryName
            existing.isArchived = payload.isArchived
            existing.updatedAt = payload.updatedAt
        } else {
            let project = Project(id: id, name: payload.name, categoryName: payload.categoryName)
            project.isArchived = payload.isArchived
            project.updatedAt = payload.updatedAt
            modelContext.insert(project)
        }
    }
}

private nonisolated struct TimeCursorSyncPayload: Codable, Sendable {
    let cursorAt: Date
    let updatedAt: Date
    let revision: Int
}
