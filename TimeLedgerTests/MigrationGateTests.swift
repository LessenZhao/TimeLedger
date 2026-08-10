import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import TimeLedger

@MainActor
struct MigrationGateTests {
    @Test func frozenHistoricalSchemaReadsCurrentShapedV1Store() throws {
        let fixture = try MigrationFixture()
        let ids = try fixture.seedCurrentV1()

        let schema = Schema(versionedSchema: TimeLedgerHistoricalSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: fixture.storeURL)]
        )
        let context = ModelContext(container)

        #expect(try context.fetchCount(FetchDescriptor<LegacyMigration.TimeEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<LegacyMigration.ThoughtNote>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<LegacyMigration.MediaMoment>()) == 3)
        #expect(try context.fetch(FetchDescriptor<LegacyMigration.TimeEntry>())
            .contains(where: { $0.id == ids.firstEntryID }))
    }

    @Test func historicalStoreUpgradePreservesDigestAndIsIdempotent() throws {
        let fixture = try MigrationFixture()
        _ = try fixture.seedHistoricalV1()

        let before = try fixture.legacyDigest()
        let opened = try fixture.openHistorical()
        guard case .ready = opened else {
            Issue.record("历史库必须按迁移计划升级成功")
            return
        }
        let afterFirst = try fixture.currentDigest()
        #expect(afterFirst == before)

        let reopened = try fixture.reopenAfterMigration()
        guard case .ready = reopened else {
            Issue.record("升级后的库必须能按常规计划重开")
            return
        }
        let afterSecond = try fixture.currentDigest()
        #expect(afterSecond == before)
        #expect(afterSecond == afterFirst)
    }

    @Test func earliestReleaseStoreUpgradesToV2WithoutDataLoss() throws {
        let fixture = try MigrationFixture()
        let entryID = try fixture.seedEarliest()

        let opened = try fixture.openEarliest()
        guard case .ready = opened else {
            Issue.record("最早发布版库必须能升级")
            return
        }

        let context = try fixture.currentContext()
        #expect(try context.fetchCount(FetchDescriptor<TimeEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Project>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TimeCursor>()) == 1)
        #expect(try context.fetch(FetchDescriptor<TimeEntry>()).first?.id == entryID)
    }

    @Test func corruptedCopyBlocksOpeningAndKeepsBackup() throws {
        let fixture = try MigrationFixture()
        _ = try fixture.seedHistoricalV1()
        let (manifest, hashes) = try fixture.makeBackup()

        try fixture.corruptStore()
        let sourceHash = try fixture.sha256(fixture.storeURL)

        let result = try fixture.openHistorical()
        guard case .blocked(let reason) = result else {
            Issue.record("损坏副本必须被迁移门禁拦截，禁止绕过 migrationPlan")
            return
        }
        #expect(reason.contains("迁移中止"))
        #expect(reason.contains(fixture.backupRootURL.path))
        #expect(try fixture.sha256(fixture.storeURL) == sourceHash)
        let backupFilename = try #require(manifest.files.first.map { $0 } ?? "")
        #expect(try fixture.sha256(
            fixture.backupRootURL.appending(path: backupFilename)
        ) == hashes[backupFilename])
    }

    @Test func unversionedHistoricalStoreCannotBypassMigrationPlan() throws {
        let fixture = try MigrationFixture()
        try fixture.seedPlainLegacy()
        _ = try fixture.makeBackup()

        let result = try fixture.openHistorical()
        guard case .blocked(let reason) = result else {
            Issue.record("未版本化历史库必须被迁移计划门禁拦截，禁止绕过 migrationPlan")
            return
        }
        #expect(reason.contains("迁移中止"))
    }

    @Test func currentFixtureDigestSurvivesDefaultPlanMigration() throws {
        let fixture = try MigrationFixture()
        _ = try fixture.seedCurrentV1()

        let before = try fixture.legacyDigest()
        let opened = try fixture.openWithCurrentPlan()
        guard case .ready = opened else {
            Issue.record("当前模拟夹具必须能按默认计划升级")
            return
        }
        let after = try fixture.currentDigest()
        #expect(after == before)
    }

    // MARK: - V2 → V3 Migration Gate

    @Test func v2ContentMigrationPreservesDataBeforeV3Upgrade() throws {
        let fixture = try MigrationFixture()
        _ = try fixture.seedV2WithContent()

        let v2Result = try fixture.openWithCurrentPlan()
        guard case .ready = v2Result else {
            Issue.record("V2 内容迁移必须成功")
            return
        }
        let v2Context = try fixture.currentContext()
        let v2Digest = try StoreSummaryDigestBuilder.currentDigest(modelContext: v2Context)

        fixture.close()
        let v3Schema = Schema(versionedSchema: TimeLedgerSchemaV3.self)
        let v3Config = ModelConfiguration("TimeLedger", schema: v3Schema, url: fixture.storeURL)
        let v3Container = try ModelContainer(
            for: v3Schema,
            migrationPlan: TimeLedgerMigrationPlan.self,
            configurations: [v3Config]
        )
        let v3Context = ModelContext(v3Container)
        let v3Digest = try StoreSummaryDigestBuilder.currentDigest(modelContext: v3Context)

        #expect(v3Digest == v2Digest)

        let v3ThoughtCount = (try? v3Context.fetchCount(FetchDescriptor<ThoughtNote>())) ?? -1
        #expect(v3ThoughtCount <= 0,
            "V3 不得包含 ThoughtNote，读到 \(v3ThoughtCount) 条")
        let v3MediaLinkCount = (try? v3Context.fetchCount(FetchDescriptor<ThoughtMediaLink>())) ?? -1
        #expect(v3MediaLinkCount <= 0,
            "V3 不得包含 ThoughtMediaLink，读到 \(v3MediaLinkCount) 条")

        #expect(try v3Context.fetchCount(FetchDescriptor<TimeEntry>()) >= 1)
        #expect(try v3Context.fetchCount(FetchDescriptor<Project>()) >= 1)
        #expect(try v3Context.fetchCount(FetchDescriptor<TimeCursor>()) >= 1)
        #expect(try v3Context.fetchCount(FetchDescriptor<JournalEntry>()) >= 1)

        fixture.close()
    }

    @Test func v3MigrationIsIdempotentOnSecondOpen() throws {
        let fixture = try MigrationFixture()
        _ = try fixture.seedV2WithContent()

        guard case .ready = try fixture.openWithCurrentPlan() else {
            Issue.record("首次 V2 打开失败")
            return
        }
        let firstDigest = try StoreSummaryDigestBuilder.currentDigest(
            modelContext: try fixture.currentContext()
        )
        fixture.close()

        let v3Schema = Schema(versionedSchema: TimeLedgerSchemaV3.self)
        let v3Config = ModelConfiguration("TimeLedger", schema: v3Schema, url: fixture.storeURL)
        let container1 = try ModelContainer(
            for: v3Schema,
            migrationPlan: TimeLedgerMigrationPlan.self,
            configurations: [v3Config]
        )
        let secondDigest = try StoreSummaryDigestBuilder.currentDigest(
            modelContext: ModelContext(container1)
        )
        #expect(secondDigest == firstDigest)

        let container2 = try ModelContainer(
            for: v3Schema,
            migrationPlan: TimeLedgerMigrationPlan.self,
            configurations: [v3Config]
        )
        let thirdDigest = try StoreSummaryDigestBuilder.currentDigest(
            modelContext: ModelContext(container2)
        )
        #expect(thirdDigest == firstDigest)

        fixture.close()
    }
}

@MainActor
private final class MigrationFixture {
    let rootURL: URL
    let storeURL: URL
    let backupRootURL: URL
    private var container: ModelContainer?
    private var context: ModelContext?

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "MigrationGateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        storeURL = rootURL.appending(path: "TimeLedger.sqlite")
        backupRootURL = rootURL.appending(path: "Backups/HistoricalV1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    struct SeedIDs {
        let firstEntryID: UUID
    }

    @discardableResult
    func seedCurrentV1() throws -> SeedIDs {
        let schema = Schema(versionedSchema: TimeLedgerSchemaV1.self)
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("TimeLedger", schema: schema, url: storeURL)]
        )
        let context = ModelContext(try #require(container))
        self.context = context
        let firstEntryID = seedRows(
            context: context,
            project: Project(name: "写作", categoryName: "工作"),
            entryID: UUID(),
            thoughtBody: "图文随记",
            manualMedia: true,
            autoMedia: true
        )
        try context.save()
        close()
        return SeedIDs(firstEntryID: firstEntryID)
    }

    @discardableResult
    func seedHistoricalV1() throws -> SeedIDs {
        let schema = Schema(versionedSchema: TimeLedgerHistoricalSchemaV1.self)
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("TimeLedger", schema: schema, url: storeURL)]
        )
        let context = ModelContext(try #require(container))
        self.context = context
        let project = LegacyMigration.Project(name: "写作", categoryName: "工作")
        let entry = LegacyMigration.TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 1_800_000_000),
            endAt: Date(timeIntervalSince1970: 1_800_003_600),
            note: "旧记录正文",
            status: .confirmed
        )
        let thought = LegacyMigration.ThoughtNote(
            body: "图文随记",
            capturedAt: Date(timeIntervalSince1970: 1_800_000_600),
            linkedEntryId: entry.id,
            linkSource: .manual
        )
        let manualMedia = LegacyMigration.MediaMoment(
            kind: .photo,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_700),
            linkedEntryId: entry.id,
            linkSource: .manual,
            requestedStorage: .app,
            storedLocation: .app,
            appRelativePath: "Media/manual.jpg",
            thumbnailData: Data("manual".utf8),
            status: .saved,
            originalAvailability: .available
        )
        let autoMedia = LegacyMigration.MediaMoment(
            kind: .video,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_800),
            linkedEntryId: entry.id,
            linkSource: .auto,
            requestedStorage: .app,
            storedLocation: .app,
            appRelativePath: "Media/auto.mov",
            thumbnailData: Data("auto".utf8),
            durationSeconds: 12,
            status: .saved,
            originalAvailability: .available
        )
        let unlinkedMedia = LegacyMigration.MediaMoment(
            kind: .photo,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_900),
            requestedStorage: .app,
            storedLocation: .app,
            appRelativePath: "Media/unlinked.jpg",
            thumbnailData: Data("unlinked".utf8),
            status: .saved,
            originalAvailability: .available
        )
        context.insert(project)
        context.insert(entry)
        context.insert(thought)
        context.insert(manualMedia)
        context.insert(autoMedia)
        context.insert(unlinkedMedia)
        context.insert(LegacyMigration.ThoughtMediaLink(
            thoughtId: thought.id,
            mediaMomentId: manualMedia.id,
            sortOrder: 0
        ))
        context.insert(LegacyMigration.TimeCursor(cursorAt: entry.endAt, updatedAt: entry.endAt))
        context.insert(LegacyMigration.AppSettings())
        context.insert(LegacyMigration.ActionItem(title: "吃药", sortOrder: 0))
        try context.save()
        close()
        return SeedIDs(firstEntryID: entry.id)
    }

    @discardableResult
    func seedEarliest() throws -> UUID {
        let schema = Schema(versionedSchema: TimeLedgerEarliestSchema.self)
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("TimeLedger", schema: schema, url: storeURL)]
        )
        let context = ModelContext(try #require(container))
        self.context = context
        let project = LegacyMigration.Project(name: "写作", categoryName: "工作")
        let entry = LegacyMigration.TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 1_800_000_000),
            endAt: Date(timeIntervalSince1970: 1_800_003_600),
            note: "最早版记录",
            status: .confirmed
        )
        context.insert(project)
        context.insert(entry)
        context.insert(LegacyMigration.TimeCursor(cursorAt: entry.endAt, updatedAt: entry.endAt))
        context.insert(LegacyMigration.AppSettings())
        try context.save()
        close()
        return entry.id
    }

    func seedPlainLegacy() throws {
        let schema = Schema([
            LegacyMigration.Project.self,
            LegacyMigration.TimeCursor.self,
            LegacyMigration.TimeEntry.self,
            LegacyMigration.AppSettings.self,
        ])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("TimeLedger", schema: schema, url: storeURL)]
        )
        let context = ModelContext(try #require(container))
        self.context = context
        let project = LegacyMigration.Project(name: "写作", categoryName: "工作")
        context.insert(project)
        context.insert(LegacyMigration.TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 1_800_000_000),
            endAt: Date(timeIntervalSince1970: 1_800_003_600),
            status: .confirmed
        ))
        try context.save()
        close()
    }

    @discardableResult
    func seedV2WithContent() throws -> SeedIDs {
        let schema = Schema(versionedSchema: TimeLedgerSchemaV2.self)
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("TimeLedger", schema: schema, url: storeURL)]
        )
        let context = ModelContext(try #require(container))
        self.context = context
        let project = Project(name: "写作", categoryName: "工作")
        let entry = TimeEntry(
            id: UUID(),
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 1_800_000_000),
            endAt: Date(timeIntervalSince1970: 1_800_003_600),
            note: "旧记录正文",
            status: .confirmed
        )
        let thought = ThoughtNote(
            body: "图文随记",
            capturedAt: Date(timeIntervalSince1970: 1_800_000_600),
            linkedEntryId: entry.id,
            linkSource: .manual
        )
        let manualMedia = MediaMoment(
            kind: .photo,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_700),
            linkedEntryId: entry.id,
            linkSource: .manual,
            requestedStorage: .app,
            storedLocation: .app,
            appRelativePath: "Media/manual.jpg",
            thumbnailData: Data("manual".utf8),
            status: .saved,
            originalAvailability: .available
        )
        context.insert(project)
        context.insert(entry)
        context.insert(thought)
        context.insert(manualMedia)
        context.insert(ThoughtMediaLink(thoughtId: thought.id, mediaMomentId: manualMedia.id, sortOrder: 0))
        context.insert(TimeCursor(cursorAt: entry.endAt, updatedAt: entry.endAt))
        context.insert(AppSettings())
        try context.save()
        close()
        return SeedIDs(firstEntryID: entry.id)
    }

    private func seedRows(
        context: ModelContext,
        project: Project,
        entryID: UUID,
        thoughtBody: String,
        manualMedia: Bool,
        autoMedia: Bool
    ) -> UUID {
        let entry = TimeEntry(
            id: entryID,
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 1_800_000_000),
            endAt: Date(timeIntervalSince1970: 1_800_003_600),
            note: "旧记录正文",
            status: .confirmed
        )
        let thought = ThoughtNote(
            body: thoughtBody,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_600),
            linkedEntryId: entry.id,
            linkSource: .manual
        )
        context.insert(project)
        context.insert(entry)
        context.insert(thought)
        if manualMedia {
            let media = MediaMoment(
                kind: .photo,
                capturedAt: Date(timeIntervalSince1970: 1_800_000_700),
                linkedEntryId: entry.id,
                linkSource: .manual,
                requestedStorage: .app,
                storedLocation: .app,
                appRelativePath: "Media/manual.jpg",
                thumbnailData: Data("manual".utf8),
                status: .saved,
                originalAvailability: .available
            )
            context.insert(media)
            context.insert(ThoughtMediaLink(thoughtId: thought.id, mediaMomentId: media.id, sortOrder: 0))
        }
        if autoMedia {
            context.insert(MediaMoment(
                kind: .video,
                capturedAt: Date(timeIntervalSince1970: 1_800_000_800),
                linkedEntryId: entry.id,
                linkSource: .auto,
                requestedStorage: .app,
                storedLocation: .app,
                appRelativePath: "Media/auto.mov",
                thumbnailData: Data("auto".utf8),
                durationSeconds: 12,
                status: .saved,
                originalAvailability: .available
            ))
        }
        context.insert(MediaMoment(
            kind: .photo,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_900),
            requestedStorage: .app,
            storedLocation: .app,
            appRelativePath: "Media/unlinked.jpg",
            thumbnailData: Data("unlinked".utf8),
            status: .saved,
            originalAvailability: .available
        ))
        return entry.id
    }

    func legacyDigest() throws -> StoreSummaryDigest {
        let schema = Schema(versionedSchema: TimeLedgerHistoricalSchemaV1.self)
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("TimeLedger", schema: schema, url: storeURL)]
        )
        return try StoreSummaryDigestBuilder.legacyDigest(
            modelContext: ModelContext(try #require(container))
        )
    }

    func currentDigest() throws -> StoreSummaryDigest {
        let context = try currentContext()
        return try StoreSummaryDigestBuilder.currentDigest(modelContext: context)
    }

    func currentContext() throws -> ModelContext {
        let schema = Schema(TimeLedgerModels.all)
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("TimeLedger", schema: schema, url: storeURL)]
        )
        context = ModelContext(try #require(container))
        return try #require(context)
    }

    func openHistorical() throws -> ContentMigrationOpenResult {
        close()
        return ContentMigrationCoordinator.open(
            storeURL: storeURL,
            backupRootURL: backupRootURL,
            migrationPlan: TimeLedgerHistoricalMigrationPlan.self
        )
    }

    func openEarliest() throws -> ContentMigrationOpenResult {
        close()
        return ContentMigrationCoordinator.open(
            storeURL: storeURL,
            backupRootURL: backupRootURL,
            migrationPlan: TimeLedgerEarliestMigrationPlan.self
        )
    }

    func openWithCurrentPlan() throws -> ContentMigrationOpenResult {
        close()
        return ContentMigrationCoordinator.open(
            storeURL: storeURL,
            backupRootURL: backupRootURL
        )
    }

    func reopenAfterMigration() throws -> ContentMigrationOpenResult {
        close()
        return ContentMigrationCoordinator.open(
            storeURL: storeURL,
            backupRootURL: backupRootURL
        )
    }

    func makeBackup() throws -> (manifest: PersistentStoreBackupManifest, fileHashes: [String: String]) {
        close()
        let backup = PersistentStoreBackup(storeURL: storeURL, backupRootURL: backupRootURL)
        let manifest = try backup.createIfNeeded()
        var hashes: [String: String] = [:]
        for filename in manifest.files {
            hashes[filename] = try sha256(backupRootURL.appending(path: filename))
        }
        return (manifest, hashes)
    }

    func corruptStore() throws {
        close()
        var data = try Data(contentsOf: storeURL)
        guard data.count > 16 else { return }
        data.replaceSubrange(0..<8, with: Data(repeating: 0xA5, count: 8))
        try data.write(to: storeURL, options: .atomic)
    }

    func sha256(_ url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func close() {
        context = nil
        container = nil
    }
}
