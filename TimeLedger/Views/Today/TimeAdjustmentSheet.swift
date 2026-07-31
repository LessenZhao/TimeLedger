import SwiftData
import SwiftUI

struct TimeAdjustmentSheet: View {
    let project: Project
    let cursorAt: Date
    let defaultEndAt: Date
    let saveAction: (Date, Date, String) throws -> TimeEntry
    let skipAction: (Date) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var startAt: Date
    @State private var endAt: Date
    @State private var note: String
    @State private var draft = ThoughtComposerDraft.empty
    @State private var isLoaded = false
    @State private var isImporting = false
    @State private var isSaving = false
    @State private var committedEntry: TimeEntry?
    @State private var errorMessage: String?
    @State private var showingSkipConfirmation = false

    private let draftStore: ThoughtComposerDraftStore

    init(
        project: Project,
        cursorAt: Date,
        defaultEndAt: Date,
        note: String = "",
        saveAction: @escaping (Date, Date, String) throws -> TimeEntry,
        skipAction: @escaping (Date) throws -> Void
    ) {
        self.project = project
        self.cursorAt = cursorAt
        self.defaultEndAt = defaultEndAt
        self.saveAction = saveAction
        self.skipAction = skipAction
        self.draftStore = ComposerDraftStoreFactory.newTimeEntry(projectID: project.id)
        let cappedEnd = min(defaultEndAt, Date())
        let initialStart = min(cursorAt, cappedEnd)
        _startAt = State(initialValue: initialStart)
        _endAt = State(initialValue: max(cappedEnd, initialStart.addingTimeInterval(60)))
        _note = State(initialValue: note)
    }

    private var nowBound: Date { Date() }

    private var pickerComponents: DatePickerComponents {
        Calendar.current.isDate(startAt, inSameDayAs: endAt)
            ? [.hourAndMinute]
            : [.date, .hourAndMinute]
    }

    private var durationText: String {
        let totalMinutes = max(0, Int(endAt.timeIntervalSince(startAt) / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            if hours > 0 { return "\(days)天\(hours)小时" }
            return "\(days)天"
        }
        if hours > 0 {
            if minutes > 0 { return "\(hours)小时\(minutes)分钟" }
            return "\(hours)小时"
        }
        return "\(max(1, minutes))分钟"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    timeRange
                    noteEditor

                    Button("不记录这段时间", role: .destructive) {
                        if draft.hasContent {
                            showingSkipConfirmation = true
                        } else {
                            performSkip()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isSaving || isImporting || committedEntry != nil)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(TLTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("记录详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("保存") {
                            save()
                        }
                        .disabled(isImporting)
                    }
                }
            }
            .onAppear(perform: loadDraft)
            .onChange(of: note) { _, newValue in
                guard isLoaded else { return }
                do {
                    draft = try draftStore.updateBody(newValue)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .onChange(of: startAt) { _, newStart in
                if endAt <= newStart {
                    endAt = min(newStart.addingTimeInterval(60), nowBound)
                }
                if endAt > nowBound {
                    endAt = nowBound
                }
            }
            .onChange(of: endAt) { _, newEnd in
                if newEnd > nowBound {
                    endAt = nowBound
                }
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                "不记录这段时间？",
                isPresented: $showingSkipConfirmation,
                titleVisibility: .visible
            ) {
                Button("不记录并丢弃本次内容", role: .destructive) {
                    performSkip(discardDraft: true)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会丢弃这次尚未保存的备注和照片草稿。")
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(project.name)
                .font(.headline)
            Spacer()
            Text(durationText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.top, 8)
    }

    private var timeRange: some View {
        HStack(spacing: 8) {
            DatePicker(
                "开始",
                selection: $startAt,
                in: cursorAt...nowBound,
                displayedComponents: pickerComponents
            )
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            DatePicker(
                "结束",
                selection: $endAt,
                in: startAt...nowBound,
                displayedComponents: pickerComponents
            )
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(TLTheme.cardBackground, in: RoundedRectangle(cornerRadius: TLTheme.cardRadius))
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("备注")
                .font(.headline)

            TextEditor(text: $note)
                .frame(minHeight: 92)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("entry.detail.note")
                .overlay(alignment: .topLeading) {
                    if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("写点补充，可留空……")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

            Divider()

            PhotoAttachmentEditor(
                draft: $draft,
                isImporting: $isImporting,
                draftStore: draftStore,
                existingMoments: [],
                isDisabled: isSaving,
                removeExisting: { _ in }
            )
        }
        .padding(14)
        .background(TLTheme.cardBackground, in: RoundedRectangle(cornerRadius: TLTheme.cardRadius))
    }

    private func loadDraft() {
        do {
            let loaded = try draftStore.load()
            draft = loaded
            if loaded.hasContent {
                note = loaded.body
            } else {
                draft = try draftStore.updateBody(note)
            }
            isLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let now = Date()
        guard endAt > startAt else {
            errorMessage = "结束时间必须晚于开始时间。"
            return
        }
        guard startAt >= cursorAt else {
            errorMessage = "开始时间不能早于未记录起点。"
            return
        }
        guard endAt <= now else {
            errorMessage = "结束时间不能晚于当前时间。"
            return
        }
        guard !isSaving else { return }

        isSaving = true
        Task {
            do {
                let entry = try committedEntry ?? saveAction(
                    startAt,
                    endAt,
                    note.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                committedEntry = entry

                let attachmentService = TimeEntryAttachmentService(modelContext: modelContext)
                let preference = try attachmentService.storagePreference()
                var mediaIssues: [MediaMoment] = []
                for attachment in draft.attachments {
                    let moment = try await attachmentService.commit(
                        attachment,
                        from: draftStore,
                        to: entry,
                        preference: preference
                    )
                    if moment.saveStatus != .saved {
                        mediaIssues.append(moment)
                    }
                }

                if mediaIssues.isEmpty {
                    try await draftStore.discard()
                    dismiss()
                } else {
                    errorMessage = "记录已保存，但有 \(mediaIssues.count) 张照片尚未完全保存。原件已保留，请再次点保存重试。"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func performSkip(discardDraft: Bool = false) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                if discardDraft {
                    try await draftStore.discard()
                }
                let skipTo = min(max(endAt, cursorAt.addingTimeInterval(60)), nowBound)
                try skipAction(skipTo)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

#Preview {
    let project = Project(name: "写材料", categoryName: "工作")
    TimeAdjustmentSheet(
        project: project,
        cursorAt: Date(timeIntervalSinceNow: -1_800),
        defaultEndAt: Date(),
        saveAction: { startAt, endAt, note in
            TimeEntry(
                projectId: project.id,
                projectNameSnapshot: project.name,
                categoryNameSnapshot: project.categoryName,
                startAt: startAt,
                endAt: endAt,
                note: note
            )
        },
        skipAction: { _ in }
    )
    .modelContainer(previewModelContainer)
}
