import SwiftData
import SwiftUI

struct TimeEntryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.sortOrder) private var projects: [Project]
    @Query private var allJournals: [JournalEntry]
    @Query private var allDocuments: [ContentDocument]
    @Query private var allContentAttachments: [ContentAttachment]
    @Query private var allJournalLinks: [JournalTimeLink]
    @Query private var allEntries: [TimeEntry]
    @Query private var allMediaMoments: [MediaMoment]
    @Query private var allActionCompletions: [ActionCompletion]

    let entry: TimeEntry

    @State private var selectedProjectId: UUID
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var minimumStartAt: Date
    @State private var contentSession: ContentEditorSession?
    @State private var editingJournal: JournalEntry?
    @State private var showingAddThought = false
    @State private var pendingUnlinkedJournalIDs: Set<UUID> = []
    @State private var selectedThoughtMedia: MediaMoment?
    @State private var errorMessage: String?
    @State private var showingDeleteAlert = false
    @State private var showingCancelConfirmationAlert = false
    @State private var isSaving = false

    init(entry: TimeEntry) {
        self.entry = entry
        _selectedProjectId = State(initialValue: entry.projectId)
        _startAt = State(initialValue: entry.startAt)
        _endAt = State(initialValue: entry.endAt)
        _minimumStartAt = State(initialValue: entry.startAt)
    }

    var body: some View {
        Form {
            projectSection
            timeSection
            contentSection
            thoughtSection
            actionsSection
        }
        .navigationTitle("编辑记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    cancel()
                }
                .accessibilityIdentifier("timeEntry.edit.cancel")
                .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                }
                .accessibilityIdentifier("timeEntry.edit.save")
                .disabled(isSaving || !canSave)
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
        .alert("删除这条待确认记录？", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: deleteDraft)
        } message: {
            Text("若后面是待确认记录会向前贴紧；后面是已确认则留空档；最后一条会退回未记录光标。")
        }
        .alert("取消确认？", isPresented: $showingCancelConfirmationAlert) {
            Button("保留确认", role: .cancel) {}
            Button("取消确认", role: .destructive, action: cancelConfirmation)
        } message: {
            Text("这条记录会变回待确认，时间位置不会改变。")
        }
        .sheet(isPresented: $showingAddThought) {
            ThoughtComposerSheet(targetEntry: entry)
        }
        .sheet(item: $editingJournal) { journal in
            RichCardContentEditorSheet(target: .journal(journal), title: "编辑随记")
        }
    }

    private var projectSection: some View {
        Section("项目与时间") {
            if isDraft {
                Picker("项目", selection: $selectedProjectId) {
                    ForEach(selectableProjects) { project in
                        Text(project.name).tag(project.id)
                    }
                }
                .accessibilityIdentifier("timeEntry.edit.project")
            } else {
                LabeledContent("项目", value: entry.projectNameSnapshot)
                    .accessibilityIdentifier("timeEntry.edit.project.readOnly")
            }
        }
    }

    private var timeSection: some View {
        Section("时间") {
            if isDraft {
                DatePicker(
                    "开始",
                    selection: $startAt,
                    in: startPickerRange,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .accessibilityIdentifier("timeEntry.edit.start")

                DatePicker(
                    "结束",
                    selection: $endAt,
                    in: endPickerRange,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .accessibilityIdentifier("timeEntry.edit.end")
            } else {
                LabeledContent("开始", value: DateFormatterFactory.dateTime.string(from: entry.startAt))
                    .accessibilityIdentifier("timeEntry.edit.start.readOnly")
                LabeledContent("结束", value: DateFormatterFactory.dateTime.string(from: entry.endAt))
                    .accessibilityIdentifier("timeEntry.edit.end.readOnly")
            }
        }
    }

    private var contentSection: some View {
        Section("记录内容") {
            RichCardContentView(
                target: .timeEntry(entry),
                mode: .edit,
                onSessionReady: { session in
                    if contentSession == nil { contentSession = session }
                }
            )
        }
    }

    private var thoughtSection: some View {
        Section("关联随记") {
            Button {
                showingAddThought = true
            } label: {
                Label("添加随记", systemImage: "plus")
            }
            .accessibilityIdentifier("timeEntry.edit.addThought")

            let visibleJournals = linkedJournals.filter {
                !pendingUnlinkedJournalIDs.contains($0.id)
            }
            if visibleJournals.isEmpty {
                Text("暂无关联随记")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleJournals) { journal in
                    linkedJournalCard(journal)
                }
            }
        }
        .fullScreenCover(item: $selectedThoughtMedia) { moment in
            MediaViewer(moment: moment)
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        if isDraft {
            Section {
                Button("删除待确认记录", role: .destructive) {
                    showingDeleteAlert = true
                }
            }
        } else {
            Section {
                Button("取消确认", role: .destructive) {
                    showingCancelConfirmationAlert = true
                }
            } footer: {
                Text("取消确认后回到待确认，未记录光标位置不变。")
            }
        }
    }

    private var isDraft: Bool {
        entry.status == TimeEntryStatus.draft.rawValue
    }

    private var selectableProjects: [Project] {
        let real = projects.filter { !SystemProject.isUnknown($0) }
        if let current = projects.first(where: { $0.id == selectedProjectId }),
           SystemProject.isUnknown(current),
           !real.contains(where: { $0.id == current.id }) {
            return [current] + real
        }
        if SystemProject.isUnknownEntry(entry),
           !real.contains(where: { $0.id == entry.projectId }),
           let unknown = projects.first(where: { $0.id == entry.projectId }) {
            return [unknown] + real
        }
        return real
    }

    private var selectedProject: Project? {
        projects.first { $0.id == selectedProjectId }
            ?? selectableProjects.first { $0.id == selectedProjectId }
    }

    private var nextEntry: TimeEntry? {
        allEntries
            .filter { $0.id != entry.id && $0.startAt >= entry.endAt }
            .sorted { $0.startAt < $1.startAt }
            .first
            ?? allEntries
            .filter { $0.id != entry.id && $0.startAt > entry.startAt }
            .sorted { $0.startAt < $1.startAt }
            .first
    }

    private var endUpperBound: Date {
        let now = Date()
        guard let next = nextEntry else { return now }
        if next.status == TimeEntryStatus.draft.rawValue {
            let beforeNextEnd = next.endAt.addingTimeInterval(-1)
            return min(now, max(startAt.addingTimeInterval(1), beforeNextEnd))
        }
        return min(now, next.startAt)
    }

    private var startPickerRange: ClosedRange<Date> {
        let upper = max(minimumStartAt, endAt.addingTimeInterval(-60))
        return minimumStartAt...upper
    }

    private var endPickerRange: ClosedRange<Date> {
        let lower = min(startAt.addingTimeInterval(60), endUpperBound)
        return lower...max(lower, endUpperBound)
    }

    private var linkedJournals: [JournalEntry] {
        let ids = Set(allJournalLinks.filter { $0.timeEntryID == entry.id }.map(\.journalEntryID))
        return allJournals
            .filter { ids.contains($0.id) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private var linkedActionCompletions: [ActionCompletion] {
        allActionCompletions
            .filter { $0.linkedEntryId == entry.id }
            .sorted { $0.completedAt < $1.completedAt }
    }

    private var canSave: Bool {
        guard isDraft else { return true }
        guard selectedProject != nil else { return false }
        return endAt > startAt
    }

    private func linkedJournalCard(_ journal: JournalEntry) -> some View {
        let moments = mediaMoments(for: journal)
        let body = allDocuments.first {
            $0.ownerID == journal.id && $0.ownerKindEnum == .journalEntry
        }?.body ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: TimelineCardActionMetrics.spacing) {
                Text(DateFormatterFactory.timeOnly.string(from: journal.capturedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                VisibleEditButton(
                    accessibilityLabel: "编辑关联随记",
                    accessibilityIdentifier: "timeEntry.edit.thought.edit",
                    action: { editingJournal = journal }
                )
                Menu {
                    Button("取消关联", role: .destructive) {
                        pendingUnlinkedJournalIDs.insert(journal.id)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(
                            minWidth: TimelineCardActionMetrics.minTouch,
                            minHeight: TimelineCardActionMetrics.minTouch
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("更多操作")
                .accessibilityIdentifier("timeEntry.edit.thought.menu")
            }

            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("暂无文字内容")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                TimelineExpandableText(
                    text: body,
                    collapsedLineLimit: 6,
                    accessibilityPrefix: "timeEntry.edit.thought.body",
                    style: .thought
                )
            }

            if !moments.isEmpty {
                TimelineMediaGrid(moments: moments) { moment in
                    selectedThoughtMedia = moment
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TLTheme.cardRadius, style: .continuous)
                .fill(TLTheme.cardBackground)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeEntry.edit.thought.card")
    }

    private func mediaMoments(for journal: JournalEntry) -> [MediaMoment] {
        guard let documentID = allDocuments.first(where: {
            $0.ownerID == journal.id && $0.ownerKindEnum == .journalEntry
        })?.id else { return [] }
        let order = Dictionary(uniqueKeysWithValues: allContentAttachments
            .filter { $0.contentDocumentID == documentID }
            .map { ($0.mediaMomentID, $0.sortOrder) })
        return allMediaMoments.filter { order[$0.id] != nil }
            .sorted { order[$0.id, default: 0] < order[$1.id, default: 0] }
    }

    private func cancel() {
        Task {
            do {
                try await contentSession?.cancel()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        guard !isSaving, canSave, let contentSession else { return }
        let now = Date()
        if endAt > now {
            errorMessage = "结束时间不能晚于当前时间。"
            return
        }
        if let next = nextEntry {
            if next.status == TimeEntryStatus.draft.rawValue, endAt >= next.endAt {
                errorMessage = "结束时间会挤掉下一段待确认记录。"
                return
            }
            if next.status != TimeEntryStatus.draft.rawValue, endAt > next.startAt {
                errorMessage = "结束时间不能与后一段重叠。"
                return
            }
        }

        isSaving = true
        Task {
            do {
                let cursorService = TimeCursorService(modelContext: modelContext)
                if isDraft {
                    guard let selectedProject else {
                        throw ValidationError.missingProject
                    }
                    try cursorService.validateEntryUpdate(
                        entry,
                        project: selectedProject,
                        startAt: startAt,
                        endAt: endAt,
                        now: now
                    )
                }

                try await contentSession.save(discardDraft: false)
                if isDraft {
                    guard let selectedProject else {
                        throw ValidationError.missingProject
                    }
                    try cursorService.updateEntry(
                        entry,
                        project: selectedProject,
                        note: nil,
                        startAt: startAt,
                        endAt: endAt,
                        now: now
                    )
                }
                for journal in linkedJournals where pendingUnlinkedJournalIDs.contains(journal.id) {
                    try JournalContentService(modelContext: modelContext).unlink(journal)
                }
                try await contentSession.finishSuccessfulSave()
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteDraft() {
        do {
            try TimeCursorService(modelContext: modelContext).deleteDraftEntry(entry)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelConfirmation() {
        do {
            try TimeCursorService(modelContext: modelContext).cancelConfirmation(entry)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        TimeEntryEditView(entry: TimeEntry(
            projectId: UUID(),
            projectNameSnapshot: "写材料",
            categoryNameSnapshot: "工作",
            startAt: Date().addingTimeInterval(-1_800),
            endAt: Date(),
            note: "整理初稿"
        ))
    }
    .modelContainer(previewModelContainer)
}
