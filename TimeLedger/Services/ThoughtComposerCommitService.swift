import Foundation
import SwiftData

enum ThoughtComposerCommitError: LocalizedError {
    case emptyDraft
    case missingAttachment

    var errorDescription: String? {
        switch self {
        case .emptyDraft:
            "请先输入文字或添加照片。"
        case .missingAttachment:
            "有附件原件不可用，草稿已保留，请重试。"
        }
    }
}

struct ThoughtComposerCommitResult {
    let thought: ThoughtNote
    let mediaMoments: [MediaMoment]

    var mediaIssues: [MediaMoment] {
        mediaMoments.filter { $0.saveStatus != .saved }
    }
}

@MainActor
struct ThoughtComposerCommitService {
    let modelContext: ModelContext
    let draftStore: ThoughtComposerDraftStore
    let mediaFileStore: MediaFileStore
    let photoLibrary: any MediaPhotoLibraryWriting

    init(
        modelContext: ModelContext,
        draftStore: ThoughtComposerDraftStore = ThoughtComposerDraftStore()
    ) {
        self.modelContext = modelContext
        self.draftStore = draftStore
        self.mediaFileStore = MediaFileStore()
        self.photoLibrary = SystemMediaPhotoLibrary()
    }

    init(
        modelContext: ModelContext,
        draftStore: ThoughtComposerDraftStore,
        mediaFileStore: MediaFileStore,
        photoLibrary: any MediaPhotoLibraryWriting
    ) {
        self.modelContext = modelContext
        self.draftStore = draftStore
        self.mediaFileStore = mediaFileStore
        self.photoLibrary = photoLibrary
    }

    func commit(
        _ draft: ThoughtComposerDraft,
        preference: MediaStoragePreference
    ) async throws -> ThoughtComposerCommitResult {
        guard draft.hasContent else {
            throw ThoughtComposerCommitError.emptyDraft
        }

        let thought = try findOrCreateThought(for: draft)
        let existingMoments = try modelContext.fetch(FetchDescriptor<MediaMoment>())
        var momentByID = Dictionary(uniqueKeysWithValues: existingMoments.map { ($0.id, $0) })
        var committedMoments: [MediaMoment] = []
        let mediaService = MediaMomentService(
            modelContext: modelContext,
            fileStore: mediaFileStore,
            photoLibrary: photoLibrary
        )
        let linkService = ThoughtMediaLinkService(modelContext: modelContext)

        for (index, attachment) in draft.attachments.enumerated() {
            let moment: MediaMoment
            if let existing = momentByID[attachment.id] {
                moment = existing
            } else {
                let originalURL = draftStore.originalURL(for: attachment)
                guard FileManager.default.fileExists(atPath: originalURL.path) else {
                    throw ThoughtComposerCommitError.missingAttachment
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
                momentByID[moment.id] = moment
            }

            _ = try linkService.link(moment, to: thought, sortOrder: index)
            committedMoments.append(moment)
        }

        try await draftStore.discard()
        return ThoughtComposerCommitResult(
            thought: thought,
            mediaMoments: committedMoments
        )
    }

    private func findOrCreateThought(for draft: ThoughtComposerDraft) throws -> ThoughtNote {
        let thoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
        if let existing = thoughts.first(where: { $0.id == draft.id }) {
            existing.body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.updatedAt = Date()
            try modelContext.save()
            return existing
        }

        let anchorAt = draft.anchorAt
            ?? draft.attachments.map(\.capturedAt).min()
            ?? Date()
        let thought = ThoughtNote(
            id: draft.id,
            body: draft.body.trimmingCharacters(in: .whitespacesAndNewlines),
            capturedAt: anchorAt,
            anchorAt: anchorAt
        )
        modelContext.insert(thought)
        try modelContext.save()
        _ = try ThoughtLinkingService(modelContext: modelContext)
            .tryAutoLinkThought(thought: thought)
        return thought
    }
}
