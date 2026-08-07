import Foundation
import Observation
import SwiftData
import SwiftUI

enum RichCardContentMode: Equatable {
    case readOnly
    case edit
    case create
}

final class RichCardContentTimeEntryDraft {
    var startAt: Date
    var endAt: Date

    init(startAt: Date, endAt: Date) {
        self.startAt = startAt
        self.endAt = endAt
    }
}

enum RichCardContentTarget {
    case timeEntry(TimeEntry)
    case thought(ThoughtNote)
    case newThought(entry: TimeEntry?)
    case newTimeEntry(
        project: Project,
        timeRange: RichCardContentTimeEntryDraft,
        initialText: String,
        save: (Date, Date, String) throws -> TimeEntry
    )
}

enum RichCardContentError: LocalizedError {
    case readOnly
    case mediaSaveFailed(MediaMomentStatus)
    case emptyTarget

    var errorDescription: String? {
        switch self {
        case .readOnly:
            "当前内容只读，请先进入编辑模式。"
        case .mediaSaveFailed(let status):
            switch status {
            case .partial:
                "媒体只保存了一部分，原件和草稿已保留，请重试。"
            case .failed:
                "媒体保存失败，原件和草稿已保留，请重试。"
            default:
                "媒体尚未完成保存，原件和草稿已保留，请重试。"
            }
        case .emptyTarget:
            "找不到要编辑的内容。"
        }
    }
}

@MainActor
@Observable
final class RichCardContentSession {
    let target: RichCardContentTarget
    let mode: RichCardContentMode

    private let modelContext: ModelContext
    private let draftStore: ThoughtComposerDraftStore
    private let mediaFileStore: MediaFileStore
    private let photoLibrary: any MediaPhotoLibraryWriting
    private let mediaPreference: MediaStoragePreference?

    private(set) var textDraft: String
    private(set) var existingMedia: [MediaMoment]
    private(set) var draft: ThoughtComposerDraft
    private(set) var removedMediaIDs: Set<UUID> = []
    private var committedNewTimeEntry: TimeEntry?

    var visibleExistingMedia: [MediaMoment] {
        existingMedia.filter { !removedMediaIDs.contains($0.id) }
    }

    var hasContent: Bool {
        if case .newTimeEntry = target {
            return true
        }
        return !textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.attachments.isEmpty
            || !visibleExistingMedia.isEmpty
            || !removedMediaIDs.isEmpty
    }

    init(
        target: RichCardContentTarget,
        mode: RichCardContentMode,
        modelContext: ModelContext,
        draftStore: ThoughtComposerDraftStore = ThoughtComposerDraftStore(),
        mediaFileStore: MediaFileStore? = nil,
        photoLibrary: (any MediaPhotoLibraryWriting)? = nil,
        mediaPreference: MediaStoragePreference? = nil
    ) throws {
        self.target = target
        self.mode = mode
        self.modelContext = modelContext
        self.draftStore = draftStore
        self.mediaFileStore = mediaFileStore ?? MediaFileStore()
        self.photoLibrary = photoLibrary ?? SystemMediaPhotoLibrary()
        self.mediaPreference = mediaPreference

        let loadedDraft = try draftStore.load()
        self.draft = loadedDraft

        switch target {
        case .timeEntry(let entry):
            self.textDraft = entry.note
            self.existingMedia = try TimeEntryAttachmentService(modelContext: modelContext)
                .noteAttachments(for: entry)
        case .thought(let thought):
            self.textDraft = thought.body
            self.existingMedia = try ThoughtMediaLinkService(modelContext: modelContext)
                .mediaMoments(for: thought)
        case .newThought:
            self.textDraft = loadedDraft.body
            self.existingMedia = []
        case .newTimeEntry(_, _, let initialText, _):
            self.textDraft = loadedDraft.hasContent ? loadedDraft.body : initialText
            self.existingMedia = []
        }

        if mode != .readOnly, loadedDraft.hasContent {
            self.textDraft = loadedDraft.body
        }
    }

    func updateText(_ text: String) {
        guard mode != .readOnly else { return }
        textDraft = text
        draft.body = text
        _ = try? draftStore.updateBody(text)
    }

    func replaceDraft(_ draft: ThoughtComposerDraft) {
        guard mode != .readOnly else { return }
        self.draft = draft
        textDraft = draft.body
    }

    func stageMedia(_ attachment: ThoughtComposerDraftAttachment) {
        guard mode != .readOnly else { return }
        guard !draft.attachments.contains(where: { $0.id == attachment.id }) else { return }
        draft.attachments.append(attachment)
    }

    func stageRemoval(_ moment: MediaMoment) {
        guard mode != .readOnly else { return }
        removedMediaIDs.insert(moment.id)
    }

    func cancel() async throws {
        try await draftStore.discard()
    }

    func save(discardDraft: Bool = true) async throws {
        guard mode != .readOnly else { throw RichCardContentError.readOnly }

        switch target {
        case .timeEntry(let entry):
            try await saveTimeEntry(entry)
        case .thought(let thought):
            try await saveThought(thought)
        case .newThought(let entry):
            try await saveNewThought(entry: entry)
        case .newTimeEntry(_, let timeRange, _, let save):
            let entry: TimeEntry
            if let committedNewTimeEntry {
                entry = committedNewTimeEntry
            } else {
                entry = try save(
                    timeRange.startAt,
                    timeRange.endAt,
                    textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                committedNewTimeEntry = entry
            }
            try await saveEntryMedia(entry)
        }

        if discardDraft {
            try await finishSuccessfulSave()
        }
    }

    func finishSuccessfulSave() async throws {
        try await draftStore.discard()
    }

    private func saveTimeEntry(_ entry: TimeEntry) async throws {
        try await saveEntryMedia(entry)
        try detachEntryMedia(from: entry)
        try TimeCursorService(modelContext: modelContext).updateNote(
            entry,
            note: textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func saveEntryMedia(_ entry: TimeEntry) async throws {
        let existingIDs = Set(existingMedia.map(\.id))
        let service = TimeEntryAttachmentService(
            modelContext: modelContext,
            mediaFileStore: mediaFileStore,
            photoLibrary: photoLibrary
        )
        let preference = try mediaPreference ?? service.storagePreference()
        for attachment in draft.attachments where !existingIDs.contains(attachment.id) {
            let moment = try await service.commit(
                attachment,
                from: draftStore,
                to: entry,
                preference: preference
            )
            guard moment.saveStatus == .saved else {
                throw RichCardContentError.mediaSaveFailed(moment.saveStatus)
            }
        }
    }

    private func detachEntryMedia(from entry: TimeEntry) throws {
        guard !removedMediaIDs.isEmpty else { return }
        for moment in existingMedia where removedMediaIDs.contains(moment.id) {
            guard moment.linkedEntryId == entry.id else { continue }
            moment.linkedEntryId = nil
            moment.linkSource = ThoughtLinkSource.manual.rawValue
            moment.updatedAt = Date()
        }
        try modelContext.save()
    }

    private func saveThought(_ thought: ThoughtNote) async throws {
        try await saveThoughtMedia(thought)
        try detachThoughtMedia(from: thought)
        try ThoughtLinkingService(modelContext: modelContext).updateThought(
            thought,
            body: textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func saveThoughtMedia(_ thought: ThoughtNote) async throws {
        let existingIDs = Set(existingMedia.map(\.id))
        let mediaService = MediaMomentService(
            modelContext: modelContext,
            fileStore: mediaFileStore,
            photoLibrary: photoLibrary
        )
        let preference = try mediaPreference
            ?? TimeEntryAttachmentService(modelContext: modelContext).storagePreference()
        let linkService = ThoughtMediaLinkService(modelContext: modelContext)
        let persistedMoments = try modelContext.fetch(FetchDescriptor<MediaMoment>())
        for (index, attachment) in draft.attachments.enumerated() where !existingIDs.contains(attachment.id) {
            let originalURL = draftStore.originalURL(for: attachment)
            let moment: MediaMoment
            if let persisted = persistedMoments.first(where: { $0.id == attachment.id }) {
                moment = persisted
                if moment.saveStatus != .saved {
                    await mediaService.retry(moment)
                }
            } else {
                moment = try await mediaService.saveCapture(
                    id: attachment.id,
                    sourceURL: originalURL,
                    kind: attachment.kind,
                    capturedAt: attachment.capturedAt,
                    thumbnailData: attachment.thumbnailData,
                    durationSeconds: attachment.durationSeconds,
                    preference: preference,
                    autoLink: false
                )
            }
            guard moment.saveStatus == .saved else {
                throw RichCardContentError.mediaSaveFailed(moment.saveStatus)
            }
            _ = try linkService.link(moment, to: thought, sortOrder: index)
        }
    }

    private func detachThoughtMedia(from thought: ThoughtNote) throws {
        guard !removedMediaIDs.isEmpty else { return }
        let links = try modelContext.fetch(FetchDescriptor<ThoughtMediaLink>())
            .filter { $0.thoughtId == thought.id && removedMediaIDs.contains($0.mediaMomentId) }
        let moments = try modelContext.fetch(FetchDescriptor<MediaMoment>())
        for link in links {
            modelContext.delete(link)
            if let moment = moments.first(where: { $0.id == link.mediaMomentId }) {
                moment.linkedEntryId = nil
                moment.linkSource = ThoughtLinkSource.manual.rawValue
                moment.updatedAt = Date()
            }
        }
        if !links.isEmpty {
            try modelContext.save()
        }
    }

    private func saveNewThought(entry: TimeEntry?) async throws {
        let thoughtID = draft.id
        let thought: ThoughtNote
        if let existing = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
            .first(where: { $0.id == thoughtID }) {
            thought = existing
            thought.body = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            thought.updatedAt = Date()
            try modelContext.save()
        } else {
            thought = ThoughtNote(
                id: thoughtID,
                body: textDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                capturedAt: draft.anchorAt ?? draft.attachments.map(\.capturedAt).min() ?? Date(),
                anchorAt: draft.anchorAt ?? draft.attachments.map(\.capturedAt).min() ?? Date()
            )
            modelContext.insert(thought)
            try modelContext.save()
        }
        if let entry {
            try ThoughtLinkingService(modelContext: modelContext).manuallyLinkThought(thought, to: entry)
        } else {
            _ = try ThoughtLinkingService(modelContext: modelContext).tryAutoLinkThought(thought: thought)
        }
        try await saveThoughtMedia(thought)
    }
}

struct RichCardContentView: View {
    @Environment(\.modelContext) private var modelContext

    let target: RichCardContentTarget
    let mode: RichCardContentMode
    let onSessionReady: ((RichCardContentSession) -> Void)?

    @State private var activeMode: RichCardContentMode
    @State private var session: RichCardContentSession?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var draft = ThoughtComposerDraft.empty
    @State private var isImporting = false
    @State private var contentRevision = 0
    @State private var selectedMedia: MediaMoment?

    init(
        target: RichCardContentTarget,
        mode: RichCardContentMode,
        onSave: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {},
        onSessionReady: ((RichCardContentSession) -> Void)? = nil
    ) {
        self.target = target
        self.mode = mode
        self.onSessionReady = onSessionReady
        _activeMode = State(initialValue: mode)
        _ = onSave
        _ = onCancel
    }

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                ProgressView()
            }
        }
        .task(id: activeMode) {
            loadSession()
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func content(_ session: RichCardContentSession) -> some View {
        let _ = contentRevision
        VStack(alignment: .leading, spacing: 16) {
            if activeMode == .readOnly {
                readOnlyText(session)
                mediaReadOnly(session)
            } else {
                if let targetEntry {
                    LabeledContent(
                        "关联到",
                        value: targetEntry.projectNameSnapshot
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("richContent.targetEntry")
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: Binding(
                        get: { session.textDraft },
                        set: {
                            session.updateText($0)
                            contentRevision += 1
                        }
                    ))
                    .frame(minHeight: 116, maxHeight: 180)
                    .scrollContentBackground(.hidden)
                    .accessibilityIdentifier(editorAccessibilityIdentifier)

                    if session.textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(isNewThoughtTarget
                             ? "记下你的想法，也可以只添加照片或视频…"
                             : "写点补充，可留空……")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

                PhotoAttachmentEditor(
                    draft: Binding(
                        get: { session.draft },
                        set: {
                            session.replaceDraft($0)
                            contentRevision += 1
                        }
                    ),
                    isImporting: $isImporting,
                    draftStore: ComposerDraftStoreFactory.storeForRichContent(target: target),
                    existingMoments: session.visibleExistingMedia,
                    isDisabled: isSaving,
                    removeExisting: { moment in
                        session.stageRemoval(moment)
                        contentRevision += 1
                    },
                    addButtonAccessibilityIdentifier: "richContent.addMedia"
                )

                if !session.removedMediaIDs.isEmpty {
                    Text("已有媒体将在保存时移除")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("richContent.media.pendingRemoval")
                }
                if isNewThoughtTarget, !session.draft.attachments.isEmpty {
                    Text("\(session.draft.attachments.count) 个附件")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("thought.composer.attachmentCount")
                }
            }
        }
        .padding(activeMode == .readOnly ? 16 : 0)
        .background {
            if activeMode == .readOnly {
                RoundedRectangle(cornerRadius: TLTheme.cardRadius)
                    .fill(TLTheme.cardBackground)
            }
        }
        .fullScreenCover(item: $selectedMedia) { moment in
            MediaViewer(moment: moment)
        }
    }

    private func readOnlyText(_ session: RichCardContentSession) -> some View {
        Group {
            if session.textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("暂无文字内容")
                    .foregroundStyle(.secondary)
            } else {
                Text(session.textDraft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("richContent.readOnly")
    }

    private func mediaReadOnly(_ session: RichCardContentSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.visibleExistingMedia.isEmpty {
                Text("暂无媒体")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                TimelineMediaGrid(moments: session.visibleExistingMedia) { moment in
                    selectedMedia = moment
                }
            }
        }
        .accessibilityIdentifier("richContent.media.readOnly")
    }

    private func loadSession() {
        do {
            let newSession = try RichCardContentSession(
                target: target,
                mode: activeMode,
                modelContext: modelContext,
                draftStore: ComposerDraftStoreFactory.storeForRichContent(target: target)
            )
            session = newSession
            draft = newSession.draft
            onSessionReady?(newSession)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var editorAccessibilityIdentifier: String {
        if case .timeEntry = target {
            return "timeEntry.edit.note"
        }
        if case .thought = target {
            return "thought.edit.body"
        }
        if case .newThought = target {
            return "thought.composer.text"
        }
        return "richContent.text"
    }

    private var isNewThoughtTarget: Bool {
        if case .newThought = target {
            return true
        }
        return false
    }

    private var targetEntry: TimeEntry? {
        if case .newThought(let entry) = target {
            return entry
        }
        return nil
    }

}

private extension ComposerDraftStoreFactory {
    static func storeForRichContent(target: RichCardContentTarget) -> ThoughtComposerDraftStore {
        switch target {
        case .timeEntry(let entry):
            return timeEntry(entry.id)
        case .thought(let thought):
            return thoughtForEntry(thought.id)
        case .newThought(let entry):
            if let entry {
                return thoughtForEntry(entry.id)
            }
            return ThoughtComposerDraftStore()
        case .newTimeEntry(let project, _, _, _):
            return newTimeEntry(projectID: project.id)
        }
    }
}
