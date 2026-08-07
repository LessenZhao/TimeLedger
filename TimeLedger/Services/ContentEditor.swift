import Foundation
import Observation
import SwiftData

struct ContentEditorAttachment: Codable, Equatable, Identifiable, Sendable {
    let mediaMomentID: UUID
    var id: UUID { mediaMomentID }
}

enum ContentEditorEvent: Equatable, Sendable {
    case addMedia(UUID)
    case removeMedia(UUID)
}

@MainActor
@Observable
final class ContentEditorSession {
    let ownerID: UUID
    let contentID: UUID
    let baseRevision: Int
    let allowsEmptyContent: Bool
    private(set) var workingBody: String
    private(set) var workingAttachments: [ContentEditorAttachment]
    private(set) var draft: ThoughtComposerDraft
    private(set) var existingMedia: [MediaMoment]
    private(set) var removedMediaIDs: Set<UUID>
    @ObservationIgnored private var saveHandler: ((ContentEditorSession) async throws -> Void)?
    @ObservationIgnored private var draftStore: ThoughtComposerDraftStore?

    init(
        ownerID: UUID,
        contentID: UUID,
        baseRevision: Int,
        workingBody: String,
        workingAttachments: [ContentEditorAttachment],
        allowsEmptyContent: Bool = false,
        draft: ThoughtComposerDraft = .empty,
        existingMedia: [MediaMoment] = []
    ) {
        self.ownerID = ownerID
        self.contentID = contentID
        self.baseRevision = baseRevision
        self.allowsEmptyContent = allowsEmptyContent
        self.workingBody = workingBody
        self.workingAttachments = workingAttachments
        self.draft = draft
        self.existingMedia = existingMedia
        self.removedMediaIDs = []
    }

    static func load(
        document: ContentDocument,
        modelContext: ModelContext
    ) throws -> ContentEditorSession {
        let attachments = try modelContext.fetch(FetchDescriptor<ContentAttachment>())
            .filter { $0.contentDocumentID == document.id }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ContentEditorAttachment(mediaMomentID: $0.mediaMomentID) }
        return ContentEditorSession(
            ownerID: document.ownerID,
            contentID: document.id,
            baseRevision: document.revision,
            workingBody: document.body,
            workingAttachments: attachments
        )
    }

    func updateBody(_ body: String) {
        workingBody = body
        draft.body = body
        _ = try? draftStore?.updateBody(body)
    }

    func updateText(_ text: String) {
        updateBody(text)
    }

    var textDraft: String { workingBody }

    var visibleExistingMedia: [MediaMoment] {
        existingMedia.filter { !removedMediaIDs.contains($0.id) }
    }

    var hasContent: Bool {
        allowsEmptyContent
            || !workingBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !workingAttachments.isEmpty
            || !draft.attachments.isEmpty
            || !removedMediaIDs.isEmpty
    }

    func apply(_ event: ContentEditorEvent) {
        switch event {
        case .addMedia(let mediaID):
            guard !workingAttachments.contains(where: { $0.mediaMomentID == mediaID }) else {
                return
            }
            workingAttachments.append(ContentEditorAttachment(mediaMomentID: mediaID))
        case .removeMedia(let mediaID):
            workingAttachments.removeAll { $0.mediaMomentID == mediaID }
        }
    }

    func replaceDraft(_ draft: ThoughtComposerDraft) {
        self.draft = draft
        let stagedIDs = Set(draft.attachments.map(\.id))
        let existingIDs = Set(existingMedia.map(\.id)).subtracting(removedMediaIDs)
        workingAttachments = (existingIDs.union(stagedIDs))
            .map(ContentEditorAttachment.init(mediaMomentID:))
        workingBody = draft.body
    }

    func stageRemoval(_ moment: MediaMoment) {
        removedMediaIDs.insert(moment.id)
        apply(.removeMedia(moment.id))
    }

    func configure(
        draftStore: ThoughtComposerDraftStore,
        save: @escaping (ContentEditorSession) async throws -> Void
    ) {
        self.draftStore = draftStore
        self.saveHandler = save
    }

    func save(discardDraft: Bool = true) async throws {
        guard let saveHandler else { throw SaveContentError.missingDocument }
        try await saveHandler(self)
        if discardDraft {
            try await finishSuccessfulSave()
        }
    }

    func finishSuccessfulSave() async throws {
        try await draftStore?.discard()
    }

    func cancel() async throws {
        try await draftStore?.discard()
    }
}

private struct PersistedContentEditorDraft: Codable {
    let ownerID: UUID
    let contentID: UUID
    let baseRevision: Int
    let workingBody: String
    let workingAttachments: [ContentEditorAttachment]
}

@MainActor
final class ContentEditorDraftStore {
    let rootURL: URL

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.rootURL = applicationSupport
                .appending(path: "ContentEditorDrafts", directoryHint: .isDirectory)
        }
    }

    func save(_ session: ContentEditorSession) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let draft = PersistedContentEditorDraft(
            ownerID: session.ownerID,
            contentID: session.contentID,
            baseRevision: session.baseRevision,
            workingBody: session.workingBody,
            workingAttachments: session.workingAttachments
        )
        try JSONEncoder().encode(draft).write(to: url(ownerID: session.ownerID), options: .atomic)
    }

    func load(ownerID: UUID) throws -> ContentEditorSession? {
        let fileURL = url(ownerID: ownerID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let draft = try JSONDecoder().decode(
            PersistedContentEditorDraft.self,
            from: Data(contentsOf: fileURL)
        )
        return ContentEditorSession(
            ownerID: draft.ownerID,
            contentID: draft.contentID,
            baseRevision: draft.baseRevision,
            workingBody: draft.workingBody,
            workingAttachments: draft.workingAttachments
        )
    }

    func discard(ownerID: UUID) throws {
        let fileURL = url(ownerID: ownerID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func url(ownerID: UUID) -> URL {
        rootURL.appending(path: "\(ownerID.uuidString.lowercased()).json")
    }
}

enum SaveContentError: LocalizedError, Equatable {
    case missingDocument
    case revisionConflict
    case missingMedia(UUID)
    case mediaAlreadyAttached(UUID)

    var errorDescription: String? {
        switch self {
        case .missingDocument:
            "内容已不存在，工作副本仍保留。"
        case .revisionConflict:
            "内容已在别处更新，未覆盖新版本；工作副本仍保留。"
        case .missingMedia(let id):
            "找不到媒体：\(id.uuidString)"
        case .mediaAlreadyAttached(let id):
            "媒体已属于另一条内容：\(id.uuidString)"
        }
    }
}

@MainActor
struct SaveContent {
    let modelContext: ModelContext

    func save(_ session: ContentEditorSession) throws {
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
        guard let document = documents.first(where: { $0.id == session.contentID }) else {
            throw SaveContentError.missingDocument
        }
        guard document.revision == session.baseRevision else {
            throw SaveContentError.revisionConflict
        }

        let allMedia = try modelContext.fetch(FetchDescriptor<MediaMoment>())
        let desiredIDs = session.workingAttachments.map(\.mediaMomentID)
        let desiredSet = Set(desiredIDs)
        for mediaID in desiredIDs where !allMedia.contains(where: { $0.id == mediaID }) {
            throw SaveContentError.missingMedia(mediaID)
        }

        try modelContext.transaction {
            let allAttachments = try modelContext.fetch(FetchDescriptor<ContentAttachment>())
            let current = allAttachments.filter { $0.contentDocumentID == document.id }
            for attachment in current where !desiredSet.contains(attachment.mediaMomentID) {
                modelContext.delete(attachment)
            }
            for (index, mediaID) in desiredIDs.enumerated() {
                if let existing = current.first(where: { $0.mediaMomentID == mediaID }) {
                    existing.sortOrder = index
                    existing.state = ContentAttachmentState.ready.rawValue
                    existing.lastError = nil
                } else if let attachedElsewhere = allAttachments.first(where: {
                    $0.mediaMomentID == mediaID && $0.contentDocumentID != document.id
                }) {
                    throw SaveContentError.mediaAlreadyAttached(attachedElsewhere.mediaMomentID)
                } else {
                    modelContext.insert(ContentAttachment(
                        contentDocumentID: document.id,
                        mediaMomentID: mediaID,
                        sortOrder: index,
                        state: .ready
                    ))
                }
            }
            document.body = session.workingBody.trimmingCharacters(in: .whitespacesAndNewlines)
            document.revision += 1
            document.updatedAt = Date()
            try modelContext.save()
        }
    }

    func createTimeEntryDocumentAndSave(
        _ session: ContentEditorSession,
        entry: TimeEntry
    ) throws {
        if let existing = try modelContext.fetch(FetchDescriptor<ContentDocument>())
            .first(where: { $0.ownerID == entry.id && $0.ownerKindEnum == .timeEntry }) {
            try modelContext.transaction {
                existing.body = session.workingBody.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.revision = max(1, existing.revision)
                existing.updatedAt = Date()
                try insertDesiredAttachments(session, document: existing)
                try modelContext.save()
            }
            return
        }
        try modelContext.transaction {
            let document = ContentDocument(
                id: session.contentID,
                ownerID: entry.id,
                ownerKind: .timeEntry,
                body: session.workingBody.trimmingCharacters(in: .whitespacesAndNewlines),
                revision: 1,
                createdAt: entry.createdAt,
                updatedAt: Date()
            )
            modelContext.insert(document)
            try insertDesiredAttachments(session, document: document)
            try modelContext.save()
        }
    }

    func createJournalAndSave(
        _ session: ContentEditorSession,
        capturedAt: Date,
        anchorAt: Date,
        linkedEntryID: UUID?,
        linkSource: ThoughtLinkSource
    ) throws {
        if try modelContext.fetch(FetchDescriptor<JournalEntry>())
            .contains(where: { $0.id == session.ownerID }) {
            try save(session)
            return
        }
        try modelContext.transaction {
            modelContext.insert(JournalEntry(
                id: session.ownerID,
                capturedAt: capturedAt,
                anchorAt: anchorAt,
                createdAt: capturedAt,
                updatedAt: Date()
            ))
            let document = ContentDocument(
                id: session.contentID,
                ownerID: session.ownerID,
                ownerKind: .journalEntry,
                body: session.workingBody.trimmingCharacters(in: .whitespacesAndNewlines),
                revision: 1,
                createdAt: capturedAt,
                updatedAt: Date()
            )
            modelContext.insert(document)
            if let linkedEntryID {
                modelContext.insert(JournalTimeLink(
                    id: session.ownerID,
                    journalEntryID: session.ownerID,
                    timeEntryID: linkedEntryID,
                    linkSource: linkSource,
                    createdAt: capturedAt,
                    updatedAt: Date()
                ))
            }
            try insertDesiredAttachments(session, document: document)
            try modelContext.save()
        }
    }

    private func insertDesiredAttachments(
        _ session: ContentEditorSession,
        document: ContentDocument
    ) throws {
        let media = try modelContext.fetch(FetchDescriptor<MediaMoment>())
        for (index, attachment) in session.workingAttachments.enumerated() {
            guard media.contains(where: { $0.id == attachment.mediaMomentID }) else {
                throw SaveContentError.missingMedia(attachment.mediaMomentID)
            }
            modelContext.insert(ContentAttachment(
                contentDocumentID: document.id,
                mediaMomentID: attachment.mediaMomentID,
                sortOrder: index,
                state: .ready
            ))
        }
    }
}

@MainActor
enum ContentEditorSessionFactory {
    static func existing(
        ownerID: UUID,
        ownerKind: ContentOwnerKind,
        modelContext: ModelContext,
        draftStore: ThoughtComposerDraftStore,
        mediaFileStore: MediaFileStore? = nil,
        photoLibrary: (any MediaPhotoLibraryWriting)? = nil
    ) throws -> ContentEditorSession {
        let document = try requireDocument(
            ownerID: ownerID,
            ownerKind: ownerKind,
            modelContext: modelContext
        )
        let allAttachments = try modelContext.fetch(FetchDescriptor<ContentAttachment>())
            .filter { $0.contentDocumentID == document.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        let media = try modelContext.fetch(FetchDescriptor<MediaMoment>())
        let mediaByID = Dictionary(uniqueKeysWithValues: media.map { ($0.id, $0) })
        let existingMedia = allAttachments.compactMap { mediaByID[$0.mediaMomentID] }
        let loadedDraft = try draftStore.prepareExisting(
            ownerID: ownerID,
            contentID: document.id,
            baseRevision: document.revision,
            canonicalBody: document.body
        )
        let persisted = allAttachments.map { ContentEditorAttachment(mediaMomentID: $0.mediaMomentID) }
        let staged = loadedDraft.attachments.map { ContentEditorAttachment(mediaMomentID: $0.id) }
        let session = ContentEditorSession(
            ownerID: ownerID,
            contentID: document.id,
            baseRevision: document.revision,
            workingBody: loadedDraft.body,
            workingAttachments: persisted + staged.filter { !persisted.contains($0) },
            draft: loadedDraft,
            existingMedia: existingMedia
        )
        session.configure(draftStore: draftStore) { session in
            try await persistStagedMedia(
                session,
                modelContext: modelContext,
                draftStore: draftStore,
                mediaFileStore: mediaFileStore ?? MediaFileStore(),
                photoLibrary: photoLibrary ?? SystemMediaPhotoLibrary()
            )
            try SaveContent(modelContext: modelContext).save(session)
        }
        return session
    }

    static func newJournal(
        targetEntryID: UUID?,
        modelContext: ModelContext,
        draftStore: ThoughtComposerDraftStore,
        mediaFileStore: MediaFileStore? = nil,
        photoLibrary: (any MediaPhotoLibraryWriting)? = nil
    ) throws -> ContentEditorSession {
        let draft = try draftStore.load()
        let ownerID = draft.id
        let session = ContentEditorSession(
            ownerID: ownerID,
            contentID: ownerID,
            baseRevision: 0,
            workingBody: draft.body,
            workingAttachments: draft.attachments.map { ContentEditorAttachment(mediaMomentID: $0.id) },
            draft: draft
        )
        session.configure(draftStore: draftStore) { session in
            try await persistStagedMedia(
                session,
                modelContext: modelContext,
                draftStore: draftStore,
                mediaFileStore: mediaFileStore ?? MediaFileStore(),
                photoLibrary: photoLibrary ?? SystemMediaPhotoLibrary()
            )
            let anchor = session.draft.anchorAt
                ?? session.draft.attachments.map(\.capturedAt).min()
                ?? Date()
            try SaveContent(modelContext: modelContext).createJournalAndSave(
                session,
                capturedAt: anchor,
                anchorAt: anchor,
                linkedEntryID: targetEntryID,
                linkSource: targetEntryID == nil ? .none : .manual
            )
        }
        return session
    }

    static func newTimeEntry(
        timeRange: RichCardContentTimeEntryDraft,
        initialText: String,
        createEntry: @escaping (Date, Date, String) throws -> TimeEntry,
        modelContext: ModelContext,
        draftStore: ThoughtComposerDraftStore,
        mediaFileStore: MediaFileStore? = nil,
        photoLibrary: (any MediaPhotoLibraryWriting)? = nil
    ) throws -> ContentEditorSession {
        var draft = try draftStore.load()
        if !draft.hasContent && !initialText.isEmpty {
            draft = try draftStore.updateBody(initialText)
        }
        let session = ContentEditorSession(
            ownerID: draft.id,
            contentID: draft.id,
            baseRevision: 0,
            workingBody: draft.body,
            workingAttachments: draft.attachments.map { ContentEditorAttachment(mediaMomentID: $0.id) },
            allowsEmptyContent: true,
            draft: draft
        )
        session.configure(draftStore: draftStore) { session in
            try await persistStagedMedia(
                session,
                modelContext: modelContext,
                draftStore: draftStore,
                mediaFileStore: mediaFileStore ?? MediaFileStore(),
                photoLibrary: photoLibrary ?? SystemMediaPhotoLibrary()
            )
            let entry = try createEntry(timeRange.startAt, timeRange.endAt, "")
            try SaveContent(modelContext: modelContext).createTimeEntryDocumentAndSave(
                session,
                entry: entry
            )
        }
        return session
    }

    private static func persistStagedMedia(
        _ session: ContentEditorSession,
        modelContext: ModelContext,
        draftStore: ThoughtComposerDraftStore,
        mediaFileStore: MediaFileStore,
        photoLibrary: any MediaPhotoLibraryWriting
    ) async throws {
        let existing = try modelContext.fetch(FetchDescriptor<MediaMoment>())
        let mediaService = MediaMomentService(
            modelContext: modelContext,
            fileStore: mediaFileStore,
            photoLibrary: photoLibrary
        )
        var settingsDescriptor = FetchDescriptor<AppSettings>()
        settingsDescriptor.fetchLimit = 1
        let appSettings: AppSettings
        if let existingSettings = try modelContext.fetch(settingsDescriptor).first {
            appSettings = existingSettings
        } else {
            appSettings = AppSettings()
            modelContext.insert(appSettings)
            try modelContext.save()
        }
        let storagePreference = MediaStoragePreference(rawValue: appSettings.mediaStoragePreference) ?? .photosLibrary
        for attachment in session.draft.attachments {
            if let moment = existing.first(where: { $0.id == attachment.id }) {
                if moment.saveStatus != .saved {
                    await mediaService.retry(moment)
                }
                guard moment.saveStatus == .saved else {
                    throw RichCardContentError.mediaSaveFailed(moment.saveStatus)
                }
            } else {
                let moment = try await mediaService.saveCapture(
                    id: attachment.id,
                    sourceURL: draftStore.originalURL(for: attachment),
                    kind: attachment.kind,
                    capturedAt: attachment.capturedAt,
                    thumbnailData: attachment.thumbnailData,
                    durationSeconds: attachment.durationSeconds,
                    preference: attachment.cameFromPhotoLibrary ? .app : storagePreference,
                    autoLink: false
                )
                guard moment.saveStatus == .saved else {
                    throw RichCardContentError.mediaSaveFailed(moment.saveStatus)
                }
            }
            session.apply(.addMedia(attachment.id))
        }
    }

    private static func requireDocument(
        ownerID: UUID,
        ownerKind: ContentOwnerKind,
        modelContext: ModelContext
    ) throws -> ContentDocument {
        guard let document = try modelContext.fetch(FetchDescriptor<ContentDocument>()).first(where: {
            $0.ownerID == ownerID && $0.ownerKindEnum == ownerKind
        }) else { throw SaveContentError.missingDocument }
        return document
    }
}
