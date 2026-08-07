import Foundation
import SwiftData

struct PersistentStoreBackupManifest: Codable, Equatable {
    let schemaVersion: Int
    let storeFilename: String
    let createdAt: Date
    let files: [String]
}

enum PersistentStoreBackupError: LocalizedError {
    case invalidManifest
    case missingBackupFile(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest:
            "迁移备份清单无效。"
        case .missingBackupFile(let filename):
            "迁移备份缺少文件：\(filename)"
        }
    }
}

struct PersistentStoreBackup {
    static let manifestFilename = "manifest.json"

    let storeURL: URL
    let backupRootURL: URL
    var fileManager: FileManager = .default

    func createIfNeeded() throws -> PersistentStoreBackupManifest {
        let manifestURL = backupRootURL.appending(path: Self.manifestFilename)
        if fileManager.fileExists(atPath: manifestURL.path) {
            let manifest = try JSONDecoder().decode(
                PersistentStoreBackupManifest.self,
                from: Data(contentsOf: manifestURL)
            )
            guard manifest.schemaVersion == 1,
                  manifest.storeFilename == storeURL.lastPathComponent
            else { throw PersistentStoreBackupError.invalidManifest }
            for filename in manifest.files where !fileManager.fileExists(
                atPath: backupRootURL.appending(path: filename).path
            ) {
                throw PersistentStoreBackupError.missingBackupFile(filename)
            }
            return manifest
        }

        try fileManager.createDirectory(
            at: backupRootURL,
            withIntermediateDirectories: true
        )
        let sources = storeFiles().filter { fileManager.fileExists(atPath: $0.path) }
        var copied: [String] = []
        for source in sources {
            let filename = source.lastPathComponent
            try copyReplacingIncompleteBackup(
                from: source,
                to: backupRootURL.appending(path: filename)
            )
            copied.append(filename)
        }
        let manifest = PersistentStoreBackupManifest(
            schemaVersion: 1,
            storeFilename: storeURL.lastPathComponent,
            createdAt: Date(),
            files: copied.sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        return manifest
    }

    private func copyReplacingIncompleteBackup(from source: URL, to destination: URL) throws {
        let staged = backupRootURL.appending(
            path: ".staging-\(UUID().uuidString)-\(destination.lastPathComponent)"
        )
        defer {
            if fileManager.fileExists(atPath: staged.path) {
                try? fileManager.removeItem(at: staged)
            }
        }

        try fileManager.copyItem(at: source, to: staged)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fileManager.moveItem(at: staged, to: destination)
        }
    }

    func restore(_ manifest: PersistentStoreBackupManifest) throws {
        guard manifest.schemaVersion == 1,
              manifest.storeFilename == storeURL.lastPathComponent
        else { throw PersistentStoreBackupError.invalidManifest }

        for filename in manifest.files {
            let source = backupRootURL.appending(path: filename)
            guard fileManager.fileExists(atPath: source.path) else {
                throw PersistentStoreBackupError.missingBackupFile(filename)
            }
            let destination = storeURL.deletingLastPathComponent().appending(path: filename)
            let replacement = destination.deletingLastPathComponent()
                .appending(path: ".restore-\(UUID().uuidString)-\(filename)")
            try fileManager.copyItem(at: source, to: replacement)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: replacement)
            } else {
                try fileManager.moveItem(at: replacement, to: destination)
            }
        }
    }

    private func storeFiles() -> [URL] {
        [
            storeURL,
            URL(filePath: storeURL.path + "-wal"),
            URL(filePath: storeURL.path + "-shm"),
        ]
    }
}

struct ContentMigrationResult: Equatable {
    let insertedCount: Int
    let processedCount: Int
    let isComplete: Bool
}

@MainActor
struct ContentMigrationRunner {
    static let completionKey = "content-unification-v2-complete"

    let modelContext: ModelContext

    func run(interruptAfter maximumRows: Int? = nil) throws -> ContentMigrationResult {
        if try checkpointExists(Self.completionKey) {
            return ContentMigrationResult(insertedCount: 0, processedCount: 0, isComplete: true)
        }

        var inserted = 0
        var processed = 0
        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let thoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let moments = try modelContext.fetch(FetchDescriptor<MediaMoment>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let thoughtMediaLinks = try modelContext.fetch(FetchDescriptor<ThoughtMediaLink>())

        for entry in entries {
            if shouldInterrupt(processed, maximumRows) {
                return .init(insertedCount: inserted, processedCount: processed, isComplete: false)
            }
            inserted += try migrate(entry)
            processed += 1
        }
        for thought in thoughts {
            if shouldInterrupt(processed, maximumRows) {
                return .init(insertedCount: inserted, processedCount: processed, isComplete: false)
            }
            inserted += try migrate(thought)
            processed += 1
        }
        for moment in moments {
            if shouldInterrupt(processed, maximumRows) {
                return .init(insertedCount: inserted, processedCount: processed, isComplete: false)
            }
            inserted += try migrate(moment, thoughtMediaLinks: thoughtMediaLinks)
            processed += 1
        }

        try verifyInvariants(entries: entries)
        modelContext.insert(ContentMigrationCheckpoint(key: Self.completionKey))
        try modelContext.save()
        return .init(insertedCount: inserted, processedCount: processed, isComplete: true)
    }

    private func shouldInterrupt(_ processed: Int, _ maximumRows: Int?) -> Bool {
        maximumRows.map { processed >= $0 } ?? false
    }

    private func migrate(_ entry: TimeEntry) throws -> Int {
        let key = "timeEntry:\(entry.id.uuidString.lowercased())"
        guard try !checkpointExists(key) else { return 0 }
        var inserted = 0
        if try document(ownerID: entry.id, kind: .timeEntry) == nil {
            modelContext.insert(ContentDocument(
                id: entry.id,
                ownerID: entry.id,
                ownerKind: .timeEntry,
                body: entry.note,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt
            ))
            inserted += 1
        }
        modelContext.insert(ContentMigrationCheckpoint(key: key))
        try modelContext.save()
        return inserted
    }

    private func migrate(_ thought: ThoughtNote) throws -> Int {
        let key = "journal:\(thought.id.uuidString.lowercased())"
        guard try !checkpointExists(key) else { return 0 }
        var inserted = 0
        if try journal(id: thought.id) == nil {
            modelContext.insert(JournalEntry(
                id: thought.id,
                capturedAt: thought.capturedAt,
                anchorAt: thought.anchorAt,
                createdAt: thought.createdAt,
                updatedAt: thought.updatedAt
            ))
            inserted += 1
        }
        if try document(ownerID: thought.id, kind: .journalEntry) == nil {
            modelContext.insert(ContentDocument(
                id: thought.id,
                ownerID: thought.id,
                ownerKind: .journalEntry,
                body: thought.body,
                createdAt: thought.createdAt,
                updatedAt: thought.updatedAt
            ))
            inserted += 1
        }
        if let entryID = thought.linkedEntryId,
           try journalLink(journalID: thought.id) == nil {
            modelContext.insert(JournalTimeLink(
                id: thought.id,
                journalEntryID: thought.id,
                timeEntryID: entryID,
                linkSource: thought.linkSourceEnum,
                createdAt: thought.createdAt,
                updatedAt: thought.updatedAt
            ))
            inserted += 1
        }
        modelContext.insert(ContentMigrationCheckpoint(key: key))
        try modelContext.save()
        return inserted
    }

    private func migrate(
        _ moment: MediaMoment,
        thoughtMediaLinks: [ThoughtMediaLink]
    ) throws -> Int {
        let key = "media:\(moment.id.uuidString.lowercased())"
        guard try !checkpointExists(key) else { return 0 }
        var inserted = 0
        let thoughtLink = thoughtMediaLinks.first { $0.mediaMomentId == moment.id }
        let targetDocument: ContentDocument

        if let thoughtLink {
            targetDocument = try requireDocument(ownerID: thoughtLink.thoughtId, kind: .journalEntry)
        } else if moment.linkSourceEnum == .manual, let entryID = moment.linkedEntryId {
            targetDocument = try requireDocument(ownerID: entryID, kind: .timeEntry)
        } else {
            if try journal(id: moment.id) == nil {
                modelContext.insert(JournalEntry(
                    id: moment.id,
                    capturedAt: moment.capturedAt,
                    anchorAt: moment.anchorAt,
                    createdAt: moment.createdAt,
                    updatedAt: moment.updatedAt
                ))
                inserted += 1
            }
            if try document(ownerID: moment.id, kind: .journalEntry) == nil {
                modelContext.insert(ContentDocument(
                    id: moment.id,
                    ownerID: moment.id,
                    ownerKind: .journalEntry,
                    createdAt: moment.createdAt,
                    updatedAt: moment.updatedAt
                ))
                try modelContext.save()
                inserted += 1
            }
            targetDocument = try requireDocument(ownerID: moment.id, kind: .journalEntry)
        }

        if try attachment(mediaID: moment.id) == nil {
            modelContext.insert(ContentAttachment(
                id: moment.id,
                contentDocumentID: targetDocument.id,
                mediaMomentID: moment.id,
                sortOrder: thoughtLink?.sortOrder ?? 0,
                createdAt: thoughtLink?.createdAt ?? moment.createdAt
            ))
            inserted += 1
        }
        modelContext.insert(ContentMigrationCheckpoint(key: key))
        try modelContext.save()
        return inserted
    }

    private func verifyInvariants(entries: [TimeEntry]) throws {
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
        for entry in entries {
            guard documents.filter({
                $0.ownerID == entry.id && $0.ownerKindEnum == .timeEntry
            }).count == 1 else {
                throw ContentMigrationError.invalidDocumentCount(entry.id)
            }
        }
        let journals = try modelContext.fetch(FetchDescriptor<JournalEntry>())
        for journal in journals {
            guard documents.filter({
                $0.ownerID == journal.id && $0.ownerKindEnum == .journalEntry
            }).count == 1 else {
                throw ContentMigrationError.invalidDocumentCount(journal.id)
            }
        }
    }

    private func checkpointExists(_ key: String) throws -> Bool {
        try modelContext.fetch(FetchDescriptor<ContentMigrationCheckpoint>())
            .contains { $0.key == key }
    }

    private func document(ownerID: UUID, kind: ContentOwnerKind) throws -> ContentDocument? {
        try modelContext.fetch(FetchDescriptor<ContentDocument>()).first {
            $0.ownerID == ownerID && $0.ownerKindEnum == kind
        }
    }

    private func requireDocument(ownerID: UUID, kind: ContentOwnerKind) throws -> ContentDocument {
        guard let result = try document(ownerID: ownerID, kind: kind) else {
            throw ContentMigrationError.missingDocument(ownerID)
        }
        return result
    }

    private func journal(id: UUID) throws -> JournalEntry? {
        try modelContext.fetch(FetchDescriptor<JournalEntry>()).first { $0.id == id }
    }

    private func journalLink(journalID: UUID) throws -> JournalTimeLink? {
        try modelContext.fetch(FetchDescriptor<JournalTimeLink>()).first {
            $0.journalEntryID == journalID
        }
    }

    private func attachment(mediaID: UUID) throws -> ContentAttachment? {
        try modelContext.fetch(FetchDescriptor<ContentAttachment>()).first {
            $0.mediaMomentID == mediaID
        }
    }
}

enum ContentMigrationError: LocalizedError {
    case missingDocument(UUID)
    case invalidDocumentCount(UUID)

    var errorDescription: String? {
        switch self {
        case .missingDocument(let id):
            "迁移缺少内容文档：\(id.uuidString)"
        case .invalidDocumentCount(let id):
            "迁移后的内容文档数量无效：\(id.uuidString)"
        }
    }
}

enum ContentMigrationOpenResult {
    case ready(ModelContainer)
    case blocked(String)
}

@MainActor
struct ContentMigrationCoordinator {
    static func open(
        storeURL: URL,
        backupRootURL: URL
    ) -> ContentMigrationOpenResult {
        do {
            _ = try PersistentStoreBackup(
                storeURL: storeURL,
                backupRootURL: backupRootURL
            ).createIfNeeded()
            let schema = Schema(versionedSchema: TimeLedgerSchemaV2.self)
            let configuration = ModelConfiguration("TimeLedger", schema: schema, url: storeURL)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: TimeLedgerMigrationPlan.self,
                configurations: [configuration]
            )
            let result = try ContentMigrationRunner(
                modelContext: ModelContext(container)
            ).run()
            guard result.isComplete else {
                return .blocked("内容迁移尚未完成，请重试。")
            }
            return .ready(container)
        } catch {
            return .blocked(error.localizedDescription)
        }
    }
}
