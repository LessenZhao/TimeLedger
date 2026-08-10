import CoreData
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
                linkSource: JournalLinkSource(rawValue: thought.linkSourceEnum.rawValue) ?? .none,
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

/// 旧模型摘要属于迁移实现；生产业务不得读取冻结模型。
@MainActor
extension StoreSummaryDigestBuilder {
    static func legacyDigest(modelContext: ModelContext) throws -> StoreSummaryDigest {
        var rows: [String] = []

        let projects = try modelContext.fetch(FetchDescriptor<LegacyMigration.Project>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for project in projects {
            rows.append([
                "project",
                project.id.uuidString.lowercased(),
                hash(project.name),
                hash(project.categoryName),
                hash(project.emoji),
                hash(project.colorHex),
                String(project.sortOrder),
                String(project.isArchived),
                date(project.createdAt),
                date(project.updatedAt),
            ].joined(separator: "|"))
        }

        let entries = try modelContext.fetch(FetchDescriptor<LegacyMigration.TimeEntry>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for entry in entries {
            rows.append([
                "timeEntry",
                entry.id.uuidString.lowercased(),
                entry.projectId.uuidString.lowercased(),
                hash(entry.projectNameSnapshot),
                hash(entry.categoryNameSnapshot),
                date(entry.startAt),
                date(entry.endAt),
                entry.status,
                hash(entry.note),
                date(entry.createdAt),
                date(entry.updatedAt),
            ].joined(separator: "|"))
        }

        let thoughts = try modelContext.fetch(FetchDescriptor<LegacyMigration.ThoughtNote>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for thought in thoughts {
            rows.append([
                "thought",
                thought.id.uuidString.lowercased(),
                date(thought.capturedAt),
                date(thought.anchorAt),
                hash(thought.body),
                optionalID(thought.linkedEntryId),
                thought.linkSource,
                date(thought.createdAt),
                date(thought.updatedAt),
                "false",
            ].joined(separator: "|"))
        }

        let moments = try modelContext.fetch(FetchDescriptor<LegacyMigration.MediaMoment>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let thoughtLinks = try modelContext.fetch(FetchDescriptor<LegacyMigration.ThoughtMediaLink>())
        let thoughtLinkByMediaID = Dictionary(
            uniqueKeysWithValues: thoughtLinks.map { ($0.mediaMomentId, $0) }
        )
        for moment in moments {
            rows.append([
                "media",
                moment.id.uuidString.lowercased(),
                moment.mediaType,
                date(moment.capturedAt),
                date(moment.anchorAt),
                optionalID(moment.linkedEntryId),
                moment.linkSource,
                moment.requestedStorage,
                moment.storedLocation,
                hash(moment.appRelativePath),
                hash(moment.photosAssetIdentifier),
                hash(moment.pendingRelativePath),
                hash(moment.sourceTemporaryPath),
                hash(moment.thumbnailData),
                formatDouble(moment.durationSeconds),
                moment.status,
                hash(moment.lastError),
                moment.originalAvailability,
                date(moment.createdAt),
                date(moment.updatedAt),
            ].joined(separator: "|"))

            if let link = thoughtLinkByMediaID[moment.id] {
                rows.append([
                    "mediaAttachment",
                    moment.id.uuidString.lowercased(),
                    link.thoughtId.uuidString.lowercased(),
                    ContentOwnerKind.journalEntry.rawValue,
                    String(link.sortOrder),
                ].joined(separator: "|"))
            } else if moment.linkSource == LegacyMigration.ThoughtLinkSource.manual.rawValue,
                      let entryID = moment.linkedEntryId {
                rows.append([
                    "mediaAttachment",
                    moment.id.uuidString.lowercased(),
                    entryID.uuidString.lowercased(),
                    ContentOwnerKind.timeEntry.rawValue,
                    "0",
                ].joined(separator: "|"))
            } else {
                rows.append([
                    "mediaAttachment",
                    moment.id.uuidString.lowercased(),
                    moment.id.uuidString.lowercased(),
                    ContentOwnerKind.journalEntry.rawValue,
                    "0",
                ].joined(separator: "|"))
                rows.append([
                    "thought",
                    moment.id.uuidString.lowercased(),
                    date(moment.capturedAt),
                    date(moment.anchorAt),
                    hash(""),
                    "nil",
                    LegacyMigration.ThoughtLinkSource.none.rawValue,
                    date(moment.createdAt),
                    date(moment.updatedAt),
                    "false",
                ].joined(separator: "|"))
            }
        }

        let cursors = try modelContext.fetch(FetchDescriptor<LegacyMigration.TimeCursor>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for cursor in cursors {
            rows.append([
                "cursor",
                cursor.id.uuidString.lowercased(),
                date(cursor.cursorAt),
                date(cursor.updatedAt),
            ].joined(separator: "|"))
        }

        let settings = try modelContext.fetch(FetchDescriptor<LegacyMigration.AppSettings>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for setting in settings {
            rows.append([
                "settings",
                setting.id.uuidString.lowercased(),
                String(setting.longUnclassifiedThresholdMinutes),
                String(setting.exportOnlyConfirmed),
                String(setting.includeDraftInTodaySummary),
                setting.mediaStoragePreference,
            ].joined(separator: "|"))
        }

        let actionItems = try modelContext.fetch(FetchDescriptor<LegacyMigration.ActionItem>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for item in actionItems {
            rows.append([
                "actionItem",
                item.id.uuidString.lowercased(),
                hash(item.title),
                String(item.sortOrder),
                String(item.isArchived),
                optionalDate(item.activeCycleStartedAt),
                date(item.createdAt),
                date(item.updatedAt),
            ].joined(separator: "|"))
        }

        let completions = try modelContext.fetch(FetchDescriptor<LegacyMigration.ActionCompletion>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for completion in completions {
            rows.append([
                "actionCompletion",
                completion.id.uuidString.lowercased(),
                completion.actionItemId.uuidString.lowercased(),
                hash(completion.actionTitleSnapshot),
                date(completion.completedAt),
                date(completion.dayStart),
                optionalID(completion.linkedEntryId),
                date(completion.createdAt),
                date(completion.updatedAt),
            ].joined(separator: "|"))
        }

        return makeDigest(rows: rows)
    }
}

enum ContentMigrationError: LocalizedError {
    case missingDocument(UUID)
    case invalidDocumentCount(UUID)
    case incomplete

    var errorDescription: String? {
        switch self {
        case .missingDocument(let id):
            "迁移缺少内容文档：\(id.uuidString)"
        case .invalidDocumentCount(let id):
            "迁移后的内容文档数量无效：\(id.uuidString)"
        case .incomplete:
            "内容迁移尚未完成，请重试。"
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
        backupRootURL: URL,
        migrationPlan: (any SchemaMigrationPlan.Type)? = nil
    ) -> ContentMigrationOpenResult {
        do {
            _ = try PersistentStoreBackup(
                storeURL: storeURL,
                backupRootURL: backupRootURL
            ).createIfNeeded()
            if try storeVersionIdentifier(at: storeURL) != TimeLedgerSchemaV3.versionIdentifier {
                try migrateContentThroughV2(
                    storeURL: storeURL,
                    migrationPlan: migrationPlan ?? TimeLedgerMigrationPlan.self
                )
            }
            return .ready(try openV3(storeURL: storeURL))
        } catch {
            return .blocked(
                "迁移中止：数据库无法按迁移计划升级，已停止打开。"
                    + "备份位于 \(backupRootURL.path)，请勿删除；可先恢复备份后重试。"
                    + "原因：\(error.localizedDescription)"
            )
        }
    }

    private static func storeVersionIdentifier(at storeURL: URL) throws -> Schema.Version? {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return nil }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite,
            at: storeURL
        )
        guard let identifiers = metadata[NSStoreModelVersionIdentifiersKey] as? [String],
              let identifier = identifiers.first
        else { return nil }
        let components = identifier.split(separator: ".").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        return Schema.Version(components[0], components[1], components[2])
    }

    private static func migrateContentThroughV2(
        storeURL: URL,
        migrationPlan: any SchemaMigrationPlan.Type
    ) throws {
        let schema = Schema(versionedSchema: TimeLedgerSchemaV2.self)
        let configuration = ModelConfiguration("TimeLedger", schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: migrationPlan,
            configurations: [configuration]
        )
        let result = try ContentMigrationRunner(
            modelContext: ModelContext(container)
        ).run()
        guard result.isComplete else {
            throw ContentMigrationError.incomplete
        }
    }

    private static func openV3(storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TimeLedgerSchemaV3.self)
        let configuration = ModelConfiguration("TimeLedger", schema: schema, url: storeURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeLedgerMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
