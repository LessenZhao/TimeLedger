import Foundation
import SwiftData

nonisolated enum ComposerDraftStoreFactory {
    static func newTimeEntry(
        projectID: UUID,
        draftsRootURL: URL? = nil
    ) -> ThoughtComposerDraftStore {
        store(in: "TimeEntry-New-\(projectID.uuidString)", draftsRootURL: draftsRootURL)
    }

    static func timeEntry(
        _ entryID: UUID,
        draftsRootURL: URL? = nil
    ) -> ThoughtComposerDraftStore {
        store(in: "TimeEntry-\(entryID.uuidString)", draftsRootURL: draftsRootURL)
    }

    static func thoughtForEntry(
        _ entryID: UUID,
        draftsRootURL: URL? = nil
    ) -> ThoughtComposerDraftStore {
        store(in: "Thought-Entry-\(entryID.uuidString)", draftsRootURL: draftsRootURL)
    }

    private static func store(
        in directoryName: String,
        draftsRootURL: URL?
    ) -> ThoughtComposerDraftStore {
        let root = draftsRootURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "ComposerDrafts", directoryHint: .isDirectory)
        return ThoughtComposerDraftStore(
            rootURL: root.appending(path: directoryName, directoryHint: .isDirectory)
        )
    }
}

enum TimeEntryAttachmentError: LocalizedError {
    case missingStagedOriginal

    var errorDescription: String? {
        switch self {
        case .missingStagedOriginal:
            "找不到可恢复的照片原件，请重新添加。"
        }
    }
}

@MainActor
struct TimeEntryAttachmentService {
    let modelContext: ModelContext
    let mediaFileStore: MediaFileStore
    let photoLibrary: any MediaPhotoLibraryWriting

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.mediaFileStore = MediaFileStore()
        self.photoLibrary = SystemMediaPhotoLibrary()
    }

    init(
        modelContext: ModelContext,
        mediaFileStore: MediaFileStore,
        photoLibrary: any MediaPhotoLibraryWriting
    ) {
        self.modelContext = modelContext
        self.mediaFileStore = mediaFileStore
        self.photoLibrary = photoLibrary
    }

    func noteAttachments(
        for entry: TimeEntry,
        moments: [MediaMoment]? = nil,
        thoughtLinks: [ThoughtMediaLink]? = nil
    ) throws -> [MediaMoment] {
        let allMoments = try moments ?? modelContext.fetch(FetchDescriptor<MediaMoment>())
        let allThoughtLinks = try thoughtLinks
            ?? modelContext.fetch(FetchDescriptor<ThoughtMediaLink>())
        let thoughtMediaIDs = Set(allThoughtLinks.map(\.mediaMomentId))

        return allMoments
            .filter {
                $0.linkedEntryId == entry.id
                    && !thoughtMediaIDs.contains($0.id)
            }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    func removeFromNote(_ moment: MediaMoment, entry: TimeEntry) throws {
        guard moment.linkedEntryId == entry.id else { return }
        moment.linkedEntryId = nil
        // Manual standalone ownership prevents later auto-reconciliation from
        // silently attaching this preserved media to another card.
        moment.linkSource = ThoughtLinkSource.manual.rawValue
        moment.updatedAt = Date()
        try modelContext.save()
    }

    func storagePreference() throws -> MediaStoragePreference {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        if let settings = try modelContext.fetch(descriptor).first {
            return MediaStoragePreference(rawValue: settings.mediaStoragePreference)
                ?? .photosLibrary
        }
        let settings = AppSettings()
        modelContext.insert(settings)
        try modelContext.save()
        return MediaStoragePreference(rawValue: settings.mediaStoragePreference)
            ?? .photosLibrary
    }

    @discardableResult
    func commit(
        _ attachment: ThoughtComposerDraftAttachment,
        from draftStore: ThoughtComposerDraftStore,
        to entry: TimeEntry,
        preference: MediaStoragePreference
    ) async throws -> MediaMoment {
        let mediaService = MediaMomentService(
            modelContext: modelContext,
            fileStore: mediaFileStore,
            photoLibrary: photoLibrary
        )
        let moments = try modelContext.fetch(FetchDescriptor<MediaMoment>())
        let moment: MediaMoment

        if let existing = moments.first(where: { $0.id == attachment.id }) {
            moment = existing
            if moment.saveStatus != .saved {
                await mediaService.retry(moment)
            }
        } else {
            let originalURL = draftStore.originalURL(for: attachment)
            guard FileManager.default.fileExists(atPath: originalURL.path) else {
                throw TimeEntryAttachmentError.missingStagedOriginal
            }
            moment = try await mediaService.saveCapture(
                id: attachment.id,
                sourceURL: originalURL,
                kind: attachment.kind,
                capturedAt: attachment.capturedAt,
                thumbnailData: attachment.thumbnailData,
                durationSeconds: attachment.durationSeconds,
                preference: attachment.cameFromPhotoLibrary ? .app : preference,
                autoLink: false
            )
        }

        try MediaLinkingService(modelContext: modelContext).manuallyLink(moment, to: entry)
        return moment
    }
}
