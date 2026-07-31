import Foundation
import SwiftData
import Testing
@testable import TimeLedger

@MainActor
struct TimeEntryAttachmentServiceTests {
    @Test func noteAttachmentsExcludeAutomaticAndThoughtMedia() throws {
        let fixture = try AttachmentFixture()
        let entry = fixture.entry()
        fixture.context.insert(entry)

        let notePhoto = fixture.moment(
            capturedAt: fixture.now.addingTimeInterval(1),
            entry: entry,
            linkSource: .manual
        )
        let automaticPhoto = fixture.moment(
            capturedAt: fixture.now.addingTimeInterval(2),
            entry: entry,
            linkSource: .auto
        )
        let thoughtPhoto = fixture.moment(
            capturedAt: fixture.now.addingTimeInterval(3),
            entry: entry,
            linkSource: .manual
        )
        let thought = ThoughtNote(
            body: "带照片的思考",
            capturedAt: fixture.now,
            linkedEntryId: entry.id,
            linkSource: .manual
        )
        let thoughtLink = ThoughtMediaLink(
            thoughtId: thought.id,
            mediaMomentId: thoughtPhoto.id,
            sortOrder: 0
        )

        fixture.context.insert(notePhoto)
        fixture.context.insert(automaticPhoto)
        fixture.context.insert(thoughtPhoto)
        fixture.context.insert(thought)
        fixture.context.insert(thoughtLink)
        try fixture.context.save()

        let attachments = try fixture.service(
            photos: EntryAttachmentPhotoLibraryStub()
        ).noteAttachments(for: entry)

        #expect(attachments.map(\.id) == [notePhoto.id])
        #expect(automaticPhoto.linkSourceEnum == .auto)
        #expect(thoughtPhoto.linkedEntryId == entry.id)

        _ = try MediaLinkingService(modelContext: fixture.context).reconcileAutoLinks()
        #expect(notePhoto.linkedEntryId == entry.id)
        #expect(notePhoto.linkSourceEnum == .manual)

        let service = fixture.service(photos: EntryAttachmentPhotoLibraryStub())
        try service.removeFromNote(notePhoto, entry: entry)
        #expect(notePhoto.linkedEntryId == entry.id)
        #expect(notePhoto.linkSourceEnum == .auto)
        #expect(try service.noteAttachments(for: entry).isEmpty)
    }

    @Test func failedPhotoSaveRemainsRecoverableAndRetryIsIdempotent() async throws {
        let fixture = try AttachmentFixture()
        let entry = fixture.entry()
        fixture.context.insert(entry)
        try fixture.context.save()

        let thoughtStore = ThoughtComposerDraftStore(
            rootURL: fixture.rootURL.appending(path: "ThoughtDraft", directoryHint: .isDirectory)
        )
        let entryStore = ThoughtComposerDraftStore(
            rootURL: fixture.rootURL.appending(path: "EntryDraft", directoryHint: .isDirectory)
        )
        _ = try thoughtStore.updateBody("不能被记录详情覆盖的思考草稿", now: fixture.now)
        _ = try entryStore.updateBody("记录详情备注", now: fixture.now)
        let draft = try await entryStore.addCapture(fixture.capture())
        let attachment = try #require(draft.attachments.first)

        let photos = EntryAttachmentPhotoLibraryStub(results: [
            .failure(AttachmentFixtureError.photoWrite),
            .success("photos-retry"),
        ])
        let service = fixture.service(photos: photos)

        let first = try await service.commit(
            attachment,
            from: entryStore,
            to: entry,
            preference: .photosLibrary
        )

        #expect(first.saveStatus == .failed)
        #expect(first.pendingRelativePath != nil)
        #expect(await fixture.mediaFileStore.exists(relativePath: first.pendingRelativePath))
        #expect(first.linkedEntryId == entry.id)
        #expect(first.linkSourceEnum == .manual)
        #expect(FileManager.default.fileExists(atPath: entryStore.originalURL(for: attachment).path))
        #expect(try thoughtStore.load().body == "不能被记录详情覆盖的思考草稿")
        #expect(try entryStore.load().body == "记录详情备注")

        let second = try await service.commit(
            attachment,
            from: entryStore,
            to: entry,
            preference: .photosLibrary
        )
        let moments = try fixture.context.fetch(FetchDescriptor<MediaMoment>())

        #expect(second.id == first.id)
        #expect(second.saveStatus == .saved)
        #expect(second.photosAssetIdentifier == "photos-retry")
        #expect(second.pendingRelativePath == nil)
        #expect(moments.count == 1)
        #expect(photos.saveCallCount == 2)
        #expect(try thoughtStore.load().body == "不能被记录详情覆盖的思考草稿")
        #expect(try entryStore.load().attachments.count == 1)
    }
}

@MainActor
private struct AttachmentFixture {
    let rootURL: URL
    let context: ModelContext
    let mediaFileStore: MediaFileStore
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "TimeEntryAttachmentTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let schema = Schema(TimeLedgerModels.all)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        context = ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
        mediaFileStore = MediaFileStore(
            rootURL: rootURL.appending(path: "MediaStore", directoryHint: .isDirectory)
        )
    }

    func entry() -> TimeEntry {
        TimeEntry(
            projectId: UUID(),
            projectNameSnapshot: "运动",
            categoryNameSnapshot: "生活",
            startAt: now,
            endAt: now.addingTimeInterval(3_600)
        )
    }

    func moment(
        capturedAt: Date,
        entry: TimeEntry,
        linkSource: ThoughtLinkSource
    ) -> MediaMoment {
        MediaMoment(
            kind: .photo,
            capturedAt: capturedAt,
            linkedEntryId: entry.id,
            linkSource: linkSource,
            requestedStorage: .app,
            thumbnailData: Data([1])
        )
    }

    func capture() throws -> CameraCapture {
        let sourceURL = rootURL.appending(path: "capture.jpg")
        try Data("original".utf8).write(to: sourceURL, options: .atomic)
        return CameraCapture(
            sourceURL: sourceURL,
            kind: .photo,
            capturedAt: now.addingTimeInterval(600),
            thumbnailData: Data("thumbnail".utf8),
            durationSeconds: 0
        )
    }

    func service(
        photos: EntryAttachmentPhotoLibraryStub
    ) -> TimeEntryAttachmentService {
        TimeEntryAttachmentService(
            modelContext: context,
            mediaFileStore: mediaFileStore,
            photoLibrary: photos
        )
    }
}

@MainActor
private final class EntryAttachmentPhotoLibraryStub: MediaPhotoLibraryWriting {
    var results: [Result<String, Error>]
    private(set) var saveCallCount = 0

    init(results: [Result<String, Error>] = []) {
        self.results = results
    }

    func saveOriginal(at fileURL: URL, kind: MediaKind) async throws -> String {
        saveCallCount += 1
        let result = results.isEmpty
            ? Result<String, Error>.success("photos-\(saveCallCount)")
            : results.removeFirst()
        return try result.get()
    }

    func assetExists(identifier: String) async -> Bool {
        false
    }
}

private enum AttachmentFixtureError: LocalizedError {
    case photoWrite

    var errorDescription: String? {
        "照片写入失败"
    }
}
