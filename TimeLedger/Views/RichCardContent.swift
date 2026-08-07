import Foundation
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
    case journal(JournalEntry)
    case newJournal(entry: TimeEntry?)
    case newTimeEntry(
        project: Project,
        timeRange: RichCardContentTimeEntryDraft,
        initialText: String,
        save: (Date, Date, String) throws -> TimeEntry
    )
}

enum RichCardContentError: LocalizedError {
    case mediaSaveFailed(MediaMomentStatus)

    var errorDescription: String? {
        switch self {
        case .mediaSaveFailed(.partial):
            "媒体只保存了一部分，原件和工作副本已保留，请重试。"
        case .mediaSaveFailed(.failed):
            "媒体保存失败，原件和工作副本已保留，请重试。"
        case .mediaSaveFailed:
            "媒体尚未完成保存，原件和工作副本已保留，请重试。"
        }
    }
}

struct RichCardContentView: View {
    @Environment(\.modelContext) private var modelContext

    let target: RichCardContentTarget
    let mode: RichCardContentMode
    let onSessionReady: ((ContentEditorSession) -> Void)?

    @State private var session: ContentEditorSession?
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var revision = 0
    @State private var selectedMedia: MediaMoment?

    init(
        target: RichCardContentTarget,
        mode: RichCardContentMode,
        onSave: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {},
        onSessionReady: ((ContentEditorSession) -> Void)? = nil
    ) {
        self.target = target
        self.mode = mode
        self.onSessionReady = onSessionReady
        _ = onSave
        _ = onCancel
    }

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task { loadSession() }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .fullScreenCover(item: $selectedMedia) { MediaViewer(moment: $0) }
    }

    @ViewBuilder
    private func content(_ session: ContentEditorSession) -> some View {
        let _ = revision
        VStack(alignment: .leading, spacing: 16) {
            if mode == .readOnly {
                if session.textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("暂无文字内容").foregroundStyle(.secondary)
                } else {
                    Text(session.textDraft).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !session.visibleExistingMedia.isEmpty {
                    TimelineMediaGrid(moments: session.visibleExistingMedia) { selectedMedia = $0 }
                }
            } else {
                if let targetEntry {
                    LabeledContent("关联到", value: targetEntry.projectNameSnapshot)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: Binding(
                        get: { session.textDraft },
                        set: {
                            session.updateText($0)
                            revision += 1
                        }
                    ))
                    .frame(minHeight: 116, maxHeight: 180)
                    .scrollContentBackground(.hidden)
                    .accessibilityIdentifier(editorAccessibilityIdentifier)

                    if session.textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(isNewJournalTarget
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
                            revision += 1
                        }
                    ),
                    isImporting: $isImporting,
                    draftStore: draftStore,
                    existingMoments: session.visibleExistingMedia,
                    isDisabled: false,
                    removeExisting: {
                        session.stageRemoval($0)
                        revision += 1
                    },
                    addButtonAccessibilityIdentifier: "richContent.addMedia"
                )

                if !session.removedMediaIDs.isEmpty {
                    Text("已有媒体将在保存时移除；原件不会删除")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("richContent.media.pendingRemoval")
                }
            }
        }
        .padding(mode == .readOnly ? 16 : 0)
        .background {
            if mode == .readOnly {
                RoundedRectangle(cornerRadius: TLTheme.cardRadius).fill(TLTheme.cardBackground)
            }
        }
    }

    private func loadSession() {
        guard session == nil else { return }
        do {
            let loaded: ContentEditorSession
            switch target {
            case .timeEntry(let entry):
                loaded = try ContentEditorSessionFactory.existing(
                    ownerID: entry.id,
                    ownerKind: .timeEntry,
                    modelContext: modelContext,
                    draftStore: draftStore
                )
            case .journal(let journal):
                loaded = try ContentEditorSessionFactory.existing(
                    ownerID: journal.id,
                    ownerKind: .journalEntry,
                    modelContext: modelContext,
                    draftStore: draftStore
                )
            case .newJournal(let entry):
                loaded = try ContentEditorSessionFactory.newJournal(
                    targetEntryID: entry?.id,
                    modelContext: modelContext,
                    draftStore: draftStore
                )
            case .newTimeEntry(_, let range, let text, let save):
                loaded = try ContentEditorSessionFactory.newTimeEntry(
                    timeRange: range,
                    initialText: text,
                    createEntry: save,
                    modelContext: modelContext,
                    draftStore: draftStore
                )
            }
            session = loaded
            onSessionReady?(loaded)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var targetEntry: TimeEntry? {
        if case .newJournal(let entry) = target { return entry }
        return nil
    }

    private var isNewJournalTarget: Bool {
        if case .newJournal = target { return true }
        return false
    }

    private var editorAccessibilityIdentifier: String {
        switch target {
        case .timeEntry: "timeEntry.edit.content"
        case .journal: "journal.edit.body"
        case .newJournal: "journal.composer.text"
        case .newTimeEntry: "timeEntry.create.content"
        }
    }

    private var draftStore: ThoughtComposerDraftStore {
        switch target {
        case .timeEntry(let entry):
            ComposerDraftStoreFactory.timeEntry(entry.id)
        case .journal(let journal):
            ComposerDraftStoreFactory.thoughtForEntry(journal.id)
        case .newJournal(let entry):
            entry.map { ComposerDraftStoreFactory.thoughtForEntry($0.id) }
                ?? ThoughtComposerDraftStore()
        case .newTimeEntry(let project, _, _, _):
            ComposerDraftStoreFactory.newTimeEntry(projectID: project.id)
        }
    }
}
