import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
import UIKit
@testable import TimeLedger

@MainActor
struct MediaMomentTests {
    @Test func modelRepresentsPhotoAndVideoFacts() {
        let photo = MediaMoment(
            kind: .photo,
            requestedStorage: .photosLibrary,
            thumbnailData: Data([1])
        )
        let video = MediaMoment(
            kind: .video,
            requestedStorage: .app,
            thumbnailData: Data([2]),
            durationSeconds: 12.5
        )

        #expect(photo.kind == .photo)
        #expect(photo.durationSeconds == 0)
        #expect(video.kind == .video)
        #expect(video.durationSeconds == 12.5)
        #expect(photo.saveStatus == .pending)
    }

    @Test func settingsDefaultToPhotosLibrary() {
        let settings = AppSettings()
        #expect(settings.mediaStoragePreference == MediaStoragePreference.photosLibrary.rawValue)
    }

    @Test func photoViewerFitsLandscapeAndPortraitImagesInsideViewport() {
        let viewport = CGSize(width: 390, height: 700)

        let landscape = MediaViewerLayout.fittedSize(
            imageSize: CGSize(width: 4_000, height: 3_000),
            viewportSize: viewport
        )
        #expect(landscape.width == 390)
        #expect(landscape.height == 292.5)

        let portrait = MediaViewerLayout.fittedSize(
            imageSize: CGSize(width: 3_000, height: 4_000),
            viewportSize: viewport
        )
        #expect(portrait.width == 390)
        #expect(portrait.height == 520)
    }

    @Test func appOnlySavesWithoutPhotoLibraryAccess() async throws {
        let fixture = try Fixture()
        let photos = PhotoLibraryStub()
        let service = fixture.service(photos: photos)

        let moment = try await service.saveCapture(
            sourceURL: fixture.sourceURL,
            kind: .photo,
            capturedAt: fixture.now,
            thumbnailData: Data([1, 2]),
            preference: .app
        )

        #expect(moment.saveStatus == .saved)
        #expect(moment.storedLocationEnum == .app)
        #expect(moment.appRelativePath != nil)
        #expect(moment.photosAssetIdentifier == nil)
        #expect(photos.saveCallCount == 0)
        #expect(moment.pendingRelativePath == nil)
    }

    @Test func failedDurableStagingCreatesNoDatabaseRecord() async throws {
        let fixture = try Fixture()
        let blockedRoot = fixture.directory.appending(path: "blocked-root")
        try Data("not-a-directory".utf8).write(to: blockedRoot, options: .atomic)
        let service = MediaMomentService(
            modelContext: fixture.context,
            fileStore: MediaFileStore(rootURL: blockedRoot),
            photoLibrary: PhotoLibraryStub()
        )

        do {
            _ = try await service.saveCapture(
                sourceURL: fixture.sourceURL,
                kind: .photo,
                capturedAt: fixture.now,
                thumbnailData: Data([1]),
                preference: .app
            )
            Issue.record("持久暂存失败时不应创建媒体记录")
        } catch {
            #expect(try fixture.context.fetch(FetchDescriptor<MediaMoment>()).isEmpty)
        }
    }

    @Test func photosOnlySavesAssetWithoutAppOriginal() async throws {
        let fixture = try Fixture()
        let photos = PhotoLibraryStub(results: [.success("photos-1")])

        let moment = try await fixture.service(photos: photos).saveCapture(
            sourceURL: fixture.sourceURL,
            kind: .photo,
            capturedAt: fixture.now,
            thumbnailData: Data([1]),
            preference: .photosLibrary
        )

        #expect(moment.saveStatus == .saved)
        #expect(moment.storedLocationEnum == .photosLibrary)
        #expect(moment.photosAssetIdentifier == "photos-1")
        #expect(moment.appRelativePath == nil)
        #expect(photos.saveCallCount == 1)
    }

    @Test func bothDestinationsReportSavedOnlyAfterBothSucceed() async throws {
        let fixture = try Fixture()
        let photos = PhotoLibraryStub(results: [.success("photos-both")])

        let moment = try await fixture.service(photos: photos).saveCapture(
            sourceURL: fixture.sourceURL,
            kind: .video,
            capturedAt: fixture.now,
            thumbnailData: Data([2]),
            durationSeconds: 8,
            preference: .both
        )

        #expect(moment.saveStatus == .saved)
        #expect(moment.storedLocationEnum == .both)
        #expect(moment.appRelativePath != nil)
        #expect(moment.photosAssetIdentifier == "photos-both")
        #expect(moment.pendingRelativePath == nil)
    }

    @Test func bothPhotoFailureIsPartialAndKeepsPendingOriginal() async throws {
        let fixture = try Fixture()
        let photos = PhotoLibraryStub(results: [.failure(FixtureError.photoWrite)])

        let moment = try await fixture.service(photos: photos).saveCapture(
            sourceURL: fixture.sourceURL,
            kind: .photo,
            capturedAt: fixture.now,
            thumbnailData: Data([3]),
            preference: .both
        )

        #expect(moment.saveStatus == .partial)
        #expect(moment.storedLocationEnum == .app)
        #expect(moment.appRelativePath != nil)
        #expect(moment.pendingRelativePath != nil)
        #expect(await fixture.fileStore.exists(relativePath: moment.pendingRelativePath))
        #expect(moment.lastError?.contains("照片写入失败") == true)
    }

    @Test func retryCompletesPartialAndRemovesPendingOriginal() async throws {
        let fixture = try Fixture()
        let photos = PhotoLibraryStub(results: [
            .failure(FixtureError.photoWrite),
            .success("photos-retry"),
        ])
        let service = fixture.service(photos: photos)
        let moment = try await service.saveCapture(
            sourceURL: fixture.sourceURL,
            kind: .photo,
            capturedAt: fixture.now,
            thumbnailData: Data([3]),
            preference: .both
        )
        let pendingPath = moment.pendingRelativePath
        #expect(moment.saveStatus == .partial)

        await service.retry(moment)

        #expect(moment.saveStatus == .saved)
        #expect(moment.storedLocationEnum == .both)
        #expect(moment.photosAssetIdentifier == "photos-retry")
        #expect(moment.pendingRelativePath == nil)
        #expect(await fixture.fileStore.exists(relativePath: pendingPath) == false)
    }

    @Test func failedPhotosSaveCanBeChangedToApp() async throws {
        let fixture = try Fixture()
        let photos = PhotoLibraryStub(results: [.failure(FixtureError.photoWrite)])
        let service = fixture.service(photos: photos)
        let moment = try await service.saveCapture(
            sourceURL: fixture.sourceURL,
            kind: .photo,
            capturedAt: fixture.now,
            thumbnailData: Data([4]),
            preference: .photosLibrary
        )
        #expect(moment.saveStatus == .failed)

        await service.saveToAppInstead(moment)

        #expect(moment.storagePreference == .app)
        #expect(moment.saveStatus == .saved)
        #expect(moment.storedLocationEnum == .app)
        #expect(moment.appRelativePath != nil)
    }

    @Test func missingPhotosAssetKeepsMomentAndMarksOriginalUnavailable() async throws {
        let fixture = try Fixture()
        let photos = PhotoLibraryStub(results: [.success("deleted-asset")])
        let service = fixture.service(photos: photos)
        let moment = try await service.saveCapture(
            sourceURL: fixture.sourceURL,
            kind: .photo,
            capturedAt: fixture.now,
            thumbnailData: Data([5]),
            preference: .photosLibrary
        )
        photos.existingIdentifiers = []

        await service.refreshOriginalAvailability(moment)

        #expect(moment.availability == .unavailable)
        #expect(moment.thumbnailData == Data([5]))
        #expect(try fixture.context.fetch(FetchDescriptor<MediaMoment>()).count == 1)
    }

    @Test func cameraConfigurationIncludesPhotoVideoHighQualityAndSixtySeconds() {
        #expect(SystemCameraConfiguration.mediaTypes.contains(UTType.image.identifier))
        #expect(SystemCameraConfiguration.mediaTypes.contains(UTType.movie.identifier))
        #expect(SystemCameraConfiguration.photoOnlyMediaTypes == [UTType.image.identifier])
        #expect(SystemCameraConfiguration.videoMaximumDuration == 60)
        #expect(SystemCameraConfiguration.videoQuality == .typeHigh)
    }

    @Test func mediaAutoLinksAndManualLinkIsNeverOverwritten() throws {
        let fixture = try Fixture()
        let first = fixture.entry(start: -3_600, end: 0, name: "第一段")
        let second = fixture.entry(start: 60, end: 3_600, name: "第二段")
        let moment = MediaMoment(
            kind: .photo,
            capturedAt: fixture.now.addingTimeInterval(-600),
            requestedStorage: .app,
            thumbnailData: Data([1])
        )
        fixture.context.insert(first)
        fixture.context.insert(second)
        fixture.context.insert(moment)
        try fixture.context.save()
        let service = MediaLinkingService(modelContext: fixture.context)

        #expect(try service.tryAutoLink(moment))
        #expect(moment.linkedEntryId == first.id)
        try service.manuallyLink(moment, to: second)
        _ = try service.reconcileAutoLinks()

        #expect(moment.linkSourceEnum == .manual)
        #expect(moment.linkedEntryId == second.id)
    }

    @Test func timeCursorNewEntryAbsorbsPendingMedia() throws {
        let fixture = try Fixture()
        let project = Project(name: "拍摄项目", categoryName: "生活")
        fixture.context.insert(project)
        fixture.context.insert(TimeCursor(
            cursorAt: fixture.now.addingTimeInterval(-3_600),
            updatedAt: fixture.now.addingTimeInterval(-3_600)
        ))
        let moment = MediaMoment(
            kind: .video,
            capturedAt: fixture.now.addingTimeInterval(-600),
            requestedStorage: .app,
            thumbnailData: Data([1]),
            durationSeconds: 10
        )
        fixture.context.insert(moment)
        try fixture.context.save()

        let entry = try TimeCursorService(modelContext: fixture.context).quickRecord(
            project: project,
            now: fixture.now
        )

        #expect(moment.linkedEntryId == entry.id)
        #expect(moment.linkSourceEnum == .auto)
    }

    @Test func deletingRecordRemovesOnlyAppFilesAndNeverTouchesPhotosAsset() async throws {
        let fixture = try Fixture()
        let photos = PhotoLibraryStub(results: [.success("keep-in-photos")])
        let service = fixture.service(photos: photos)
        let moment = try await service.saveCapture(
            sourceURL: fixture.sourceURL,
            kind: .photo,
            capturedAt: fixture.now,
            thumbnailData: Data([9]),
            preference: .both
        )
        let appPath = moment.appRelativePath

        await service.deleteRecord(moment)

        #expect(await fixture.fileStore.exists(relativePath: appPath) == false)
        #expect(try fixture.context.fetch(FetchDescriptor<MediaMoment>()).isEmpty)
        #expect(photos.deletedAssetIdentifiers.isEmpty)
        #expect(photos.existingIdentifiers.contains("keep-in-photos"))
    }

    @Test func additiveMediaSchemaKeepsLegacyModels() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TimeLedgerMediaMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "TimeLedger.store")
        let legacyModels: [any PersistentModel.Type] = [
            Project.self,
            TimeCursor.self,
            TimeEntry.self,
            AppSettings.self,
            ThoughtNote.self,
            ActionItem.self,
            ActionCompletion.self,
        ]
        let legacySchema = Schema(legacyModels)
        var legacyContainer: ModelContainer? = try ModelContainer(
            for: legacySchema,
            configurations: [ModelConfiguration("MediaMigration", schema: legacySchema, url: storeURL)]
        )
        let legacyContext = ModelContext(legacyContainer!)
        let project = Project(name: "旧项目", categoryName: "工作")
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: now.addingTimeInterval(-3_600),
            endAt: now
        )
        legacyContext.insert(project)
        legacyContext.insert(entry)
        legacyContext.insert(ThoughtNote(body: "旧思考", linkedEntryId: entry.id, linkSource: .manual))
        legacyContext.insert(ActionItem(title: "旧事项"))
        try legacyContext.save()
        legacyContainer = nil

        let currentSchema = Schema(TimeLedgerModels.all)
        let currentContainer = try ModelContainer(
            for: currentSchema,
            configurations: [ModelConfiguration("MediaMigration", schema: currentSchema, url: storeURL)]
        )
        let currentContext = ModelContext(currentContainer)

        #expect(try currentContext.fetch(FetchDescriptor<Project>()).count == 1)
        #expect(try currentContext.fetch(FetchDescriptor<TimeEntry>()).count == 1)
        #expect(try currentContext.fetch(FetchDescriptor<ThoughtNote>()).count == 1)
        #expect(try currentContext.fetch(FetchDescriptor<ActionItem>()).count == 1)
        #expect(try currentContext.fetch(FetchDescriptor<MediaMoment>()).isEmpty)
    }

    private var now: Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }
}

@MainActor
private final class PhotoLibraryStub: MediaPhotoLibraryWriting {
    var results: [Result<String, Error>]
    var existingIdentifiers: Set<String>
    private(set) var saveCallCount = 0
    private(set) var deletedAssetIdentifiers: Set<String> = []

    init(
        results: [Result<String, Error>] = [],
        existingIdentifiers: Set<String> = []
    ) {
        self.results = results
        self.existingIdentifiers = existingIdentifiers
    }

    func saveOriginal(at fileURL: URL, kind: MediaKind) async throws -> String {
        saveCallCount += 1
        let result = results.isEmpty
            ? Result<String, Error>.success("photos-\(saveCallCount)")
            : results.removeFirst()
        let identifier = try result.get()
        existingIdentifiers.insert(identifier)
        return identifier
    }

    func assetExists(identifier: String) async -> Bool {
        existingIdentifiers.contains(identifier)
    }
}

@MainActor
private struct Fixture {
    let directory: URL
    let sourceURL: URL
    let fileStore: MediaFileStore
    let context: ModelContext
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "MediaMomentTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        sourceURL = directory.appending(path: "capture.jpg")
        try Data("original".utf8).write(to: sourceURL, options: .atomic)
        fileStore = MediaFileStore(
            rootURL: directory.appending(path: "store", directoryHint: .isDirectory)
        )
        let schema = Schema(TimeLedgerModels.all)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        context = ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    func service(photos: PhotoLibraryStub) -> MediaMomentService {
        MediaMomentService(
            modelContext: context,
            fileStore: fileStore,
            photoLibrary: photos
        )
    }

    func entry(start: TimeInterval, end: TimeInterval, name: String) -> TimeEntry {
        let projectID = UUID()
        return TimeEntry(
            projectId: projectID,
            projectNameSnapshot: name,
            categoryNameSnapshot: "测试",
            startAt: now.addingTimeInterval(start),
            endAt: now.addingTimeInterval(end)
        )
    }
}

private enum FixtureError: LocalizedError {
    case photoWrite

    var errorDescription: String? {
        "照片写入失败"
    }
}
