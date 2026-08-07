import Foundation
import SwiftData
import Testing
@testable import TimeLedger

@MainActor
struct ContentMigrationTests {
    @Test func legacyRowsBackfillWithoutChangingMediaIdentityOrPaths() throws {
        let fixture = try ContentMigrationFixture()
        let ids = try fixture.seedLegacyGraph()

        let result = try fixture.migrate()
        let snapshot = try fixture.snapshot()

        #expect(result.isComplete)
        #expect(snapshot.timeEntryDocuments == 2)
        #expect(snapshot.journals == 4)
        #expect(snapshot.journalDocuments == 4)
        #expect(snapshot.attachments == 4)
        #expect(snapshot.mediaIDs == ids.mediaIDs)
        #expect(snapshot.mediaPaths == ids.mediaPaths)
    }

    @Test func everyTimeEntryIncludingEmptyContentGetsExactlyOneDocument() throws {
        let fixture = try ContentMigrationFixture()
        _ = try fixture.seedLegacyGraph()
        _ = try fixture.migrate()

        let documents = try fixture.documents(ownerKind: .timeEntry)
        #expect(documents.count == 2)
        #expect(Set(documents.map(\.ownerID)).count == 2)
        #expect(documents.contains(where: { $0.body.isEmpty }))
    }

    @Test func manualLinkedMediaWithoutThoughtLinkBelongsToTimeEntryContent() throws {
        let fixture = try ContentMigrationFixture()
        let ids = try fixture.seedLegacyGraph()
        _ = try fixture.migrate()

        let attachment = try #require(try fixture.attachment(mediaID: ids.manualEntryMediaID))
        let document = try #require(try fixture.document(id: attachment.contentDocumentID))
        #expect(document.ownerKindEnum == .timeEntry)
        #expect(document.ownerID == ids.firstEntryID)
    }

    @Test func autoAndUnlinkedMediaBecomeMediaOnlyJournals() throws {
        let fixture = try ContentMigrationFixture()
        let ids = try fixture.seedLegacyGraph()
        _ = try fixture.migrate()

        for mediaID in [ids.autoMediaID, ids.unlinkedMediaID] {
            let attachment = try #require(try fixture.attachment(mediaID: mediaID))
            let document = try #require(try fixture.document(id: attachment.contentDocumentID))
            #expect(document.ownerKindEnum == .journalEntry)
            #expect(document.body.isEmpty)
            let links = try fixture.journalLinks(journalID: document.ownerID)
            #expect(links.isEmpty)
        }
    }

    @Test func interruptedBackfillResumesWithoutDuplicates() throws {
        let fixture = try ContentMigrationFixture()
        _ = try fixture.seedLegacyGraph()

        let interrupted = try fixture.migrate(interruptAfter: 2)
        #expect(!interrupted.isComplete)
        let resumed = try fixture.resumeMigration()
        #expect(resumed.isComplete)
        let snapshot = try fixture.snapshot()
        #expect(snapshot.timeEntryDocuments == 2)
        #expect(snapshot.journals == 4)
        #expect(snapshot.attachments == 4)
    }

    @Test func thirdMigrationRunAddsNothing() throws {
        let fixture = try ContentMigrationFixture()
        _ = try fixture.seedLegacyGraph()
        _ = try fixture.migrate()
        let second = try fixture.resumeMigration()
        let third = try fixture.resumeMigration()

        #expect(second.insertedCount == 0)
        #expect(third.insertedCount == 0)
    }

    @Test func backupCopiesSQLiteSidecarsAndCanRestoreLegacyStore() throws {
        let fixture = try ContentMigrationFixture()
        _ = try fixture.seedLegacyGraph()

        let manifest = try fixture.makeBackup()
        #expect(manifest.files.contains(where: { $0.hasSuffix(".sqlite") }))
        try fixture.restoreBackup(manifest)
        #expect(try fixture.legacyTimeEntryCount() == 2)
    }

    @Test func backupFailureBlocksOpeningV2UntilRetrySucceeds() throws {
        let fixture = try ContentMigrationFixture()
        _ = try fixture.seedLegacyGraph()

        let failed = fixture.openWithBackupRoot(fixture.storeURL)
        guard case .blocked = failed else {
            Issue.record("备份失败时必须进入迁移门禁")
            return
        }
        let retried = fixture.openWithBackupRoot(fixture.backupRootURL)
        guard case .ready = retried else {
            Issue.record("恢复可写备份目录后必须允许进入 V2")
            return
        }
    }

    @Test func incompleteBackupWithoutManifestCanBeRetriedInPlace() throws {
        let fixture = try ContentMigrationFixture()
        _ = try fixture.seedLegacyGraph()
        try fixture.seedIncompleteBackup()

        let manifest = try fixture.makeBackup()

        #expect(manifest.files.contains(fixture.storeURL.lastPathComponent))
        #expect(FileManager.default.fileExists(
            atPath: fixture.backupRootURL
                .appending(path: PersistentStoreBackup.manifestFilename).path
        ))
    }
}

@MainActor
private final class ContentMigrationFixture {
    struct SeedIDs {
        let firstEntryID: UUID
        let manualEntryMediaID: UUID
        let autoMediaID: UUID
        let unlinkedMediaID: UUID
        let mediaIDs: Set<UUID>
        let mediaPaths: Set<String>
    }

    struct Snapshot {
        let timeEntryDocuments: Int
        let journals: Int
        let journalDocuments: Int
        let attachments: Int
        let mediaIDs: Set<UUID>
        let mediaPaths: Set<String>
    }

    let rootURL: URL
    let storeURL: URL
    let backupRootURL: URL
    private var container: ModelContainer?
    private var context: ModelContext?

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "ContentMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        storeURL = rootURL.appending(path: "TimeLedger.sqlite")
        backupRootURL = rootURL.appending(path: "Backups/V1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func seedLegacyGraph() throws -> SeedIDs {
        let schema = Schema(versionedSchema: TimeLedgerSchemaV1.self)
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("TimeLedger", schema: schema, url: storeURL)]
        )
        let context = ModelContext(try #require(container))
        self.context = context
        let firstEntryID = UUID()
        let secondEntryID = UUID()
        let projectID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = TimeEntry(
            id: firstEntryID,
            projectId: projectID,
            projectNameSnapshot: "写作",
            categoryNameSnapshot: "工作",
            startAt: now.addingTimeInterval(-3_600),
            endAt: now.addingTimeInterval(-1_800),
            note: "旧记录正文"
        )
        let second = TimeEntry(
            id: secondEntryID,
            projectId: projectID,
            projectNameSnapshot: "写作",
            categoryNameSnapshot: "工作",
            startAt: now.addingTimeInterval(-1_800),
            endAt: now,
            note: ""
        )
        let linkedThought = ThoughtNote(
            body: "图文随记",
            capturedAt: now.addingTimeInterval(-1_200),
            linkedEntryId: firstEntryID,
            linkSource: .manual
        )
        let textThought = ThoughtNote(body: "纯文字随记", capturedAt: now.addingTimeInterval(-600))
        context.insert(first)
        context.insert(second)
        context.insert(linkedThought)
        context.insert(textThought)

        let thoughtMedia = makeMedia(
            path: "Media/thought.jpg",
            at: now.addingTimeInterval(-1_100),
            linkedEntryID: firstEntryID,
            linkSource: .manual
        )
        let manualEntryMedia = makeMedia(
            path: "Media/entry.mov",
            at: now.addingTimeInterval(-1_000),
            linkedEntryID: firstEntryID,
            linkSource: .manual,
            kind: .video
        )
        let autoMedia = makeMedia(
            path: "Media/auto.jpg",
            at: now.addingTimeInterval(-900),
            linkedEntryID: secondEntryID,
            linkSource: .auto
        )
        let unlinkedMedia = makeMedia(
            path: "Media/unlinked.mov",
            at: now.addingTimeInterval(-800),
            linkedEntryID: nil,
            linkSource: .none,
            kind: .video
        )
        for moment in [thoughtMedia, manualEntryMedia, autoMedia, unlinkedMedia] {
            context.insert(moment)
        }
        context.insert(ThoughtMediaLink(
            thoughtId: linkedThought.id,
            mediaMomentId: thoughtMedia.id,
            sortOrder: 0
        ))
        try context.save()

        let result = SeedIDs(
            firstEntryID: firstEntryID,
            manualEntryMediaID: manualEntryMedia.id,
            autoMediaID: autoMedia.id,
            unlinkedMediaID: unlinkedMedia.id,
            mediaIDs: Set([thoughtMedia.id, manualEntryMedia.id, autoMedia.id, unlinkedMedia.id]),
            mediaPaths: Set(["Media/thought.jpg", "Media/entry.mov", "Media/auto.jpg", "Media/unlinked.mov"])
        )
        close()
        return result
    }

    func migrate(interruptAfter: Int? = nil) throws -> ContentMigrationResult {
        _ = try makeBackup()
        let schema = Schema(versionedSchema: TimeLedgerSchemaV2.self)
        container = try ModelContainer(
            for: schema,
            migrationPlan: TimeLedgerMigrationPlan.self,
            configurations: [ModelConfiguration("TimeLedger", schema: schema, url: storeURL)]
        )
        let context = ModelContext(try #require(container))
        self.context = context
        return try ContentMigrationRunner(modelContext: context).run(interruptAfter: interruptAfter)
    }

    func resumeMigration() throws -> ContentMigrationResult {
        let context = try #require(context)
        return try ContentMigrationRunner(modelContext: context).run()
    }

    func makeBackup() throws -> PersistentStoreBackupManifest {
        close()
        return try PersistentStoreBackup(storeURL: storeURL, backupRootURL: backupRootURL).createIfNeeded()
    }

    func seedIncompleteBackup() throws {
        close()
        try FileManager.default.createDirectory(
            at: backupRootURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: storeURL,
            to: backupRootURL.appending(path: storeURL.lastPathComponent)
        )
    }

    func restoreBackup(_ manifest: PersistentStoreBackupManifest) throws {
        close()
        try PersistentStoreBackup(storeURL: storeURL, backupRootURL: backupRootURL).restore(manifest)
    }

    func openWithBackupRoot(_ root: URL) -> ContentMigrationOpenResult {
        close()
        return ContentMigrationCoordinator.open(storeURL: storeURL, backupRootURL: root)
    }

    func legacyTimeEntryCount() throws -> Int {
        let schema = Schema(versionedSchema: TimeLedgerSchemaV1.self)
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("TimeLedger", schema: schema, url: storeURL)]
        )
        let context = ModelContext(try #require(container))
        self.context = context
        return try context.fetchCount(FetchDescriptor<TimeEntry>())
    }

    func snapshot() throws -> Snapshot {
        let context = try #require(context)
        let documents = try context.fetch(FetchDescriptor<ContentDocument>())
        let moments = try context.fetch(FetchDescriptor<MediaMoment>())
        return Snapshot(
            timeEntryDocuments: documents.filter { $0.ownerKindEnum == .timeEntry }.count,
            journals: try context.fetchCount(FetchDescriptor<JournalEntry>()),
            journalDocuments: documents.filter { $0.ownerKindEnum == .journalEntry }.count,
            attachments: try context.fetchCount(FetchDescriptor<ContentAttachment>()),
            mediaIDs: Set(moments.map(\.id)),
            mediaPaths: Set(moments.compactMap(\.appRelativePath))
        )
    }

    func documents(ownerKind: ContentOwnerKind) throws -> [ContentDocument] {
        try #require(context).fetch(FetchDescriptor<ContentDocument>()).filter {
            $0.ownerKindEnum == ownerKind
        }
    }

    func attachment(mediaID: UUID) throws -> ContentAttachment? {
        try #require(context).fetch(FetchDescriptor<ContentAttachment>()).first {
            $0.mediaMomentID == mediaID
        }
    }

    func document(id: UUID) throws -> ContentDocument? {
        try #require(context).fetch(FetchDescriptor<ContentDocument>()).first { $0.id == id }
    }

    func journalLinks(journalID: UUID) throws -> [JournalTimeLink] {
        try #require(context).fetch(FetchDescriptor<JournalTimeLink>()).filter {
            $0.journalEntryID == journalID
        }
    }

    private func makeMedia(
        path: String,
        at date: Date,
        linkedEntryID: UUID?,
        linkSource: ThoughtLinkSource,
        kind: MediaKind = .photo
    ) -> MediaMoment {
        MediaMoment(
            kind: kind,
            capturedAt: date,
            linkedEntryId: linkedEntryID,
            linkSource: linkSource,
            requestedStorage: .app,
            storedLocation: .app,
            appRelativePath: path,
            thumbnailData: Data(path.utf8),
            status: .saved
        )
    }

    private func close() {
        context = nil
        container = nil
    }
}
