import SwiftData
import SwiftUI

struct TimeEntryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.sortOrder) private var projects: [Project]
    @Query private var allThoughts: [ThoughtNote]
    @Query private var allEntries: [TimeEntry]
    @Query private var allMediaMoments: [MediaMoment]
    @Query private var allThoughtMediaLinks: [ThoughtMediaLink]
    @Query private var allActionCompletions: [ActionCompletion]

    let entry: TimeEntry

    @State private var selectedProjectId: UUID
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var minimumStartAt: Date
    @State private var contentSession: RichCardContentSession?
    @State private var editingThought: ThoughtNote?
    @State private var showingAddThought = false
    @State private var pendingUnlinkedThoughtIDs: Set<UUID> = []
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
        .alert("删除这条草稿？", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: deleteDraft)
        } message: {
            Text("若后面是草稿会向前贴紧；后面是已确认则留空档；最后一条会退回未记录光标。")
        }
        .alert("取消确认？", isPresented: $showingCancelConfirmationAlert) {
            Button("保留确认", role: .cancel) {}
            Button("取消确认", role: .destructive, action: cancelConfirmation)
        } message: {
            Text("这条记录会变回草稿，时间位置不会改变。")
        }
        .sheet(isPresented: $showingAddThought) {
            ThoughtComposerSheet(targetEntry: entry)
        }
        .sheet(item: $editingThought) { thought in
            RichCardContentEditorSheet(target: .thought(thought), title: "编辑思考")
        }
    }

    private var projectSection: some View {
        Section("项目") {
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
        Section("备注与媒体") {
            if contentSession != nil {
                RichCardContentView(
                    target: .timeEntry(entry),
                    mode: .edit,
                    onSessionReady: { session in
                        contentSession = session
                    }
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .task {
                        loadContentSessionIfNeeded()
                    }
            }
        }
    }

    private var thoughtSection: some View {
        Section("思考关联") {
            Button {
                showingAddThought = true
            } label: {
                Label("添加思考", systemImage: "plus")
            }
            .accessibilityIdentifier("timeEntry.edit.addThought")

            let visibleThoughts = linkedThoughts.filter {
                !pendingUnlinkedThoughtIDs.contains($0.id)
            }
            if visibleThoughts.isEmpty {
                Text("暂无关联思考")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleThoughts) { thought in
                    linkedThoughtCard(thought)
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
                Button("删除草稿", role: .destructive) {
                    showingDeleteAlert = true
                }
            }
        } else {
            Section {
                Button("取消确认", role: .destructive) {
                    showingCancelConfirmationAlert = true
                }
            } footer: {
                Text("取消确认后回到草稿，未记录光标位置不变。")
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

    private var linkedThoughts: [ThoughtNote] {
        allThoughts
            .filter { $0.linkedEntryId == entry.id }
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

    private func linkedThoughtCard(_ thought: ThoughtNote) -> some View {
        let moments = mediaMoments(for: thought)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: TimelineCardActionMetrics.spacing) {
                Text(DateFormatterFactory.timeOnly.string(from: thought.capturedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                VisibleEditButton(
                    accessibilityLabel: "编辑关联思考",
                    accessibilityIdentifier: "timeEntry.edit.thought.edit",
                    action: { editingThought = thought }
                )
                Menu {
                    Button("取消关联", role: .destructive) {
                        pendingUnlinkedThoughtIDs.insert(thought.id)
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

            if thought.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("暂无文字内容")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                TimelineExpandableText(
                    text: thought.body,
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

    private func mediaMoments(for thought: ThoughtNote) -> [MediaMoment] {
        let order = Dictionary(
            uniqueKeysWithValues: allThoughtMediaLinks
                .filter { $0.thoughtId == thought.id }
                .map { ($0.mediaMomentId, $0.sortOrder) }
        )
        return allMediaMoments
            .filter { order[$0.id] != nil }
            .sorted { order[$0.id, default: 0] < order[$1.id, default: 0] }
    }

    private func loadContentSessionIfNeeded() {
        guard contentSession == nil else { return }
        do {
            contentSession = try RichCardContentSession(
                target: .timeEntry(entry),
                mode: .edit,
                modelContext: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
        }
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
        let note = contentSession.textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        if endAt > now {
            errorMessage = "结束时间不能晚于当前时间。"
            return
        }
        if let next = nextEntry {
            if next.status == TimeEntryStatus.draft.rawValue, endAt >= next.endAt {
                errorMessage = "结束时间会挤掉下一段草稿。"
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
                        note: note,
                        startAt: startAt,
                        endAt: endAt,
                        now: now
                    )
                }
                for thought in linkedThoughts where pendingUnlinkedThoughtIDs.contains(thought.id) {
                    try ThoughtLinkingService(modelContext: modelContext).unlinkThought(thought)
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
