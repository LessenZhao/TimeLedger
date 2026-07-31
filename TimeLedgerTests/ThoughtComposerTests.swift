import Foundation
import SwiftData
import Testing
import UIKit
@testable import TimeLedger

@MainActor
struct ThoughtComposerTests {
    @Test func stagedPhotosAndTextRecoverAfterTemporarySourcesDisappear() async throws {
        let fixture = try DraftFixture()
        let firstCapture = try fixture.capture(named: "first")
        let secondCapture = try fixture.capture(named: "second")

        _ = try await fixture.store.addCapture(firstCapture)
        _ = try await fixture.store.addCapture(secondCapture)
        _ = try fixture.store.updateBody("拍照后补充文字", now: fixture.now)
        try FileManager.default.moveItem(
            at: fixture.temporarySourcesURL,
            to: fixture.rootURL.appending(path: "TemporarySources-Moved")
        )

        let relaunchedStore = ThoughtComposerDraftStore(rootURL: fixture.draftURL)
        let recovered = try relaunchedStore.load()

        #expect(recovered.body == "拍照后补充文字")
        #expect(recovered.attachments.count == 2)
        #expect(recovered.attachments.allSatisfy {
            FileManager.default.fileExists(atPath: relaunchedStore.originalURL(for: $0).path)
        })
        #expect(firstCapture.sourceURL.path != relaunchedStore.originalURL(for: recovered.attachments[0]).path)
    }

    @Test func textAndPhotosCanBeAddedInEitherOrder() async throws {
        let first = try DraftFixture()
        _ = try first.store.updateBody("先写文字", now: first.now)
        let textFirst = try await first.store.addCapture(first.capture(named: "after-text"))

        #expect(textFirst.body == "先写文字")
        #expect(textFirst.attachments.count == 1)
        #expect(textFirst.anchorAt == first.now)

        let second = try DraftFixture()
        let capture = try second.capture(named: "before-text")
        _ = try await second.store.addCapture(capture)
        let photoFirst = try second.store.updateBody("后写文字", now: second.now.addingTimeInterval(10))

        #expect(photoFirst.body == "后写文字")
        #expect(photoFirst.attachments.count == 1)
        #expect(photoFirst.anchorAt == capture.capturedAt)
    }

    @Test func commitIsIdempotentAndGroupsMediaWithThought() async throws {
        let fixture = try DraftFixture()
        let draftWithPhoto = try await fixture.store.addCapture(
            fixture.capture(named: "commit")
        )
        let draft = try fixture.store.updateBody("同一条思考", now: fixture.now)
        #expect(draft.id == draftWithPhoto.id)

        let schema = Schema(TimeLedgerModels.all)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let context = ModelContext(
            try ModelContainer(for: schema, configurations: [configuration])
        )
        let mediaRoot = fixture.rootURL.appending(path: "MediaStore", directoryHint: .isDirectory)
        let service = ThoughtComposerCommitService(
            modelContext: context,
            draftStore: fixture.store,
            mediaFileStore: MediaFileStore(rootURL: mediaRoot),
            photoLibrary: ComposerPhotoLibraryStub()
        )

        let firstResult = try await service.commit(draft, preference: .app)
        let secondResult = try await service.commit(draft, preference: .app)
        let thoughts = try context.fetch(FetchDescriptor<ThoughtNote>())
        let moments = try context.fetch(FetchDescriptor<MediaMoment>())
        let links = try context.fetch(FetchDescriptor<ThoughtMediaLink>())

        #expect(thoughts.count == 1)
        #expect(moments.count == 1)
        #expect(links.count == 1)
        #expect(firstResult.thought.id == draft.id)
        #expect(secondResult.thought.id == draft.id)
        #expect(moments[0].id == draft.attachments[0].id)
        #expect(links[0].thoughtId == draft.id)
        #expect(links[0].mediaMomentId == moments[0].id)
        #expect(moments[0].anchorAt == thoughts[0].anchorAt)
    }

    @Test func selectedLibraryPhotoIsNotWrittenBackToPhotosLibrary() async throws {
        let fixture = try DraftFixture()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
        let image = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let originalData = try #require(image.jpegData(compressionQuality: 0.9))
        let thumbnailData = try #require(MediaThumbnailFactory.thumbnailData(for: image))
        let draft = try await fixture.store.addPhotoData(
            originalData,
            thumbnailData: thumbnailData,
            fileExtension: "jpg",
            capturedAt: fixture.now
        )
        let schema = Schema(TimeLedgerModels.all)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let context = ModelContext(
            try ModelContainer(for: schema, configurations: [configuration])
        )
        let photos = ComposerPhotoLibraryStub()
        let service = ThoughtComposerCommitService(
            modelContext: context,
            draftStore: fixture.store,
            mediaFileStore: MediaFileStore(
                rootURL: fixture.rootURL.appending(path: "ImportedMedia")
            ),
            photoLibrary: photos
        )

        let result = try await service.commit(draft, preference: .photosLibrary)

        #expect(photos.saveCallCount == 0)
        #expect(result.mediaMoments[0].storedLocationEnum == .app)
        #expect(result.mediaMoments[0].photosAssetIdentifier == nil)
    }
}

private struct DraftFixture {
    let rootURL: URL
    let temporarySourcesURL: URL
    let draftURL: URL
    let store: ThoughtComposerDraftStore
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "ThoughtComposerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporarySourcesURL = rootURL.appending(path: "TemporarySources", directoryHint: .isDirectory)
        draftURL = rootURL.appending(path: "Draft", directoryHint: .isDirectory)
        store = ThoughtComposerDraftStore(rootURL: draftURL)
        try FileManager.default.createDirectory(
            at: temporarySourcesURL,
            withIntermediateDirectories: true
        )
    }

    func capture(named name: String) throws -> CameraCapture {
        let sourceURL = temporarySourcesURL.appending(path: "\(name).jpg")
        try Data("original-\(name)".utf8).write(to: sourceURL, options: .atomic)
        return CameraCapture(
            sourceURL: sourceURL,
            kind: .photo,
            capturedAt: now.addingTimeInterval(TimeInterval(name.count)),
            thumbnailData: Data("thumbnail-\(name)".utf8),
            durationSeconds: 0
        )
    }
}

@MainActor
private final class ComposerPhotoLibraryStub: MediaPhotoLibraryWriting {
    private(set) var saveCallCount = 0

    func saveOriginal(at fileURL: URL, kind: MediaKind) async throws -> String {
        saveCallCount += 1
        return "unused"
    }

    func assetExists(identifier: String) async -> Bool {
        false
    }
}
