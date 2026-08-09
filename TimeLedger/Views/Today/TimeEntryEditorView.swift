import SwiftData
import SwiftUI

// MARK: - Mode

enum TimeEntryEditorMode {
    case create(project: Project, cursorAt: Date, defaultEndAt: Date)
    case edit(entry: TimeEntry)
}

// MARK: - View

struct TimeEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.sortOrder) private var projects: [Project]
    @Query private var allJournals: [JournalEntry]
    @Query private var allDocuments: [ContentDocument]
    @Query private var allContentAttachments: [ContentAttachment]
    @Query private var allJournalLinks: [JournalTimeLink]
    @Query private var allEntries: [TimeEntry]
    @Query private var allMediaMoments: [MediaMoment]

    let mode: TimeEntryEditorMode
    let saveAction: ((Date, Date, String) throws -> TimeEntry)?
    let skipAction: ((Date) throws -> Void)?

    // MARK: State

    @State private var startAt: Date
    @State private var endAt: Date
    @State private var selectedProjectID: UUID?
    @State private var cursorAt: Date
    @State private var createdEntryID: UUID?
    @State private var contentSession: ContentEditorSession?
    @State private var editingJournal: JournalEntry?
    @State private var showingAddThought = false
    @State private var pendingUnlinkedJournalIDs: Set<UUID> = []
    @State private var selectedThoughtMedia: MediaMoment?
    @State private var errorMessage: String?
    @State private var showingDeleteAlert = false
    @State private var showingCancelConfirmationAlert = false
    @State private var showingSkipConfirmation = false
    @State private var isSaving = false

    private var draftStore: ThoughtComposerDraftStore {
        if case .create(let project, _, _) = mode {
            return ComposerDraftStoreFactory.newTimeEntry(projectID: project.id)
        }
        return ComposerDraftStoreFactory.newTimeEntry(projectID: UUID())
    }

    init(
        mode: TimeEntryEditorMode,
        saveAction: ((Date, Date, String) throws -> TimeEntry)? = nil,
        skipAction: ((Date) throws -> Void)? = nil
    ) {
        self.mode = mode
        self.saveAction = saveAction
        self.skipAction = skipAction

        switch mode {
        case .create(let project, let cursor, let defaultEnd):
            let cappedEnd = min(defaultEnd, Date())
            let initialStart = min(cursor, cappedEnd)
            let initialEnd = max(cappedEnd, initialStart.addingTimeInterval(60))
            _selectedProjectID = State(initialValue: project.id)
            _startAt = State(initialValue: initialStart)
            _endAt = State(initialValue: initialEnd)
            _cursorAt = State(initialValue: cursor)

        case .edit(let entry):
            _selectedProjectID = State(initialValue: entry.projectId)
            _startAt = State(initialValue: entry.startAt)
            _endAt = State(initialValue: entry.endAt)
            _cursorAt = State(initialValue: entry.startAt)
            _createdEntryID = State(initialValue: entry.id)
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow
                Divider()
                timeRangeRow
                Divider()
                contentEditor
                thoughtSection
                dangerAction
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(TLTheme.pageBackground.ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    cancel()
                }
                .accessibilityIdentifier("timeEntry.editor.cancel")
                .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                }
                .accessibilityIdentifier("timeEntry.editor.save")
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
        .confirmationDialog(
            "不记录这段时间？",
            isPresented: $showingSkipConfirmation,
            titleVisibility: .visible
        ) {
            Button("不记录并丢弃本次内容", role: .destructive) {
                performSkip()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会丢弃这次尚未保存的文字和媒体工作副本。")
        }
        .sheet(isPresented: $showingAddThought) {
            if let entryID = createdEntryID,
               let entry = allEntries.first(where: { $0.id == entryID }) {
                ThoughtComposerSheet(targetEntry: entry)
            } else {
                ThoughtComposerSheet()
            }
        }
        .sheet(item: $editingJournal) { journal in
            RichCardContentEditorSheet(target: .journal(journal), title: "编辑随记")
        }
        .fullScreenCover(item: $selectedThoughtMedia) { moment in
            MediaViewer(moment: moment)
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
            if newEnd > nowBound { endAt = nowBound }
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            if isCreateMode {
                Text(createProject?.name ?? "")
                    .font(.headline)
            } else if let entry = editEntry {
                if isDraft {
                    Picker("项目", selection: Binding(
                        get: { selectedProjectID ?? UUID() },
                        set: { selectedProjectID = $0 }
                    )) {
                        ForEach(selectableProjects) { project in
                            Text(project.name).tag(project.id)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("timeEntry.editor.project")
                } else {
                    Text(entry.projectNameSnapshot)
                        .font(.headline)
                }
            }
            Spacer()
            Text(durationText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.top, 8)
    }

    // MARK: Time Range

    private var timeRangeRow: some View {
        Group {
            if let entry = editEntry, !isDraft {
                LabeledContent("时间") {
                    Text("\(DateFormatterFactory.dateTime.string(from: entry.startAt)) – \(DateFormatterFactory.dateTime.string(from: entry.endAt))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            } else {
                HStack(spacing: 8) {
                    DatePicker("开始", selection: $startAt,
                               in: startPickerRange,
                               displayedComponents: pickerComponents)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)

                    DatePicker("结束", selection: $endAt,
                               in: endPickerRange,
                               displayedComponents: pickerComponents)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: TLTheme.cardRadius, style: .continuous)
                        .fill(TLTheme.cardBackground)
                )
            }
        }
    }

    // MARK: Content Editor

    private var contentEditor: some View {
        RichCardContentView(
            target: richCardTarget,
            mode: richCardMode,
            onSessionReady: { session in
                if contentSession == nil { contentSession = session }
            }
        )
        .id(richCardID)
    }

    // MARK: Thought Section

    private var thoughtSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("关联随记")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    handleAddThought()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("timeEntry.editor.addThought")
            }

            let visibleJournals = linkedJournals.filter { !pendingUnlinkedJournalIDs.contains($0.id) }
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
    }

    // MARK: Danger Action

    @ViewBuilder
    private var dangerAction: some View {
        if isCreateMode {
            Button("不记录这段时间", role: .destructive) {
                showingSkipConfirmation = true
            }
            .frame(maxWidth: .infinity)
        } else if isDraft {
            Button("删除待确认记录", role: .destructive) {
                showingDeleteAlert = true
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
            Text("这条记录已保存为待确认。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        } else {
            Button("取消确认", role: .destructive) {
                showingCancelConfirmationAlert = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Computed Properties

    private var navigationTitle: String {
        if isCreateMode { return "记录时间" }
        return "编辑记录"
    }

    private var isCreateMode: Bool {
        if case .create = mode { return true }
        return false
    }

    private var createProject: Project? {
        if case .create(let project, _, _) = mode { return project }
        return nil
    }

    private var createCursorAt: Date? {
        if case .create(_, let cursor, _) = mode { return cursor }
        return nil
    }

    private var createDefaultEndAt: Date? {
        if case .create(_, _, let defaultEnd) = mode { return defaultEnd }
        return nil
    }

    private var editEntry: TimeEntry? {
        if case .edit(let entry) = mode { return entry }
        return nil
    }

    private var isDraft: Bool {
        editEntry?.status == TimeEntryStatus.draft.rawValue
    }

    private var nowBound: Date { Date() }

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

    private var pickerComponents: DatePickerComponents {
        Calendar.current.isDate(startAt, inSameDayAs: endAt)
            ? [.hourAndMinute]
            : [.date, .hourAndMinute]
    }

    private var canSave: Bool {
        guard !isSaving else { return false }
        if editEntry != nil, isDraft {
            guard selectedProject != nil else { return false }
            return endAt > startAt
        }
        if isCreateMode {
            guard contentSession?.hasContent == true else { return false }
            return endAt > startAt
        }
        return contentSession?.hasContent == true
    }

    private var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
    }

    private var selectableProjects: [Project] {
        let real = projects.filter { !SystemProject.isUnknown($0) }
        guard let entry = editEntry else { return real }
        if let current = projects.first(where: { $0.id == selectedProjectID }),
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

    private var linkedJournals: [JournalEntry] {
        guard let entryID = createdEntryID ?? editEntry?.id else { return [] }
        let ids = Set(allJournalLinks.filter { $0.timeEntryID == entryID }.map(\.journalEntryID))
        return allJournals
            .filter { ids.contains($0.id) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private var startPickerRange: ClosedRange<Date> {
        let minimum: Date
        if let cursor = createCursorAt { minimum = cursor }
        else { minimum = editEntry?.startAt ?? startAt }
        let upper = max(minimum, endAt.addingTimeInterval(-60))
        return minimum...upper
    }

    private var endPickerRange: ClosedRange<Date> {
        let lower = min(startAt.addingTimeInterval(60), nowBound)
        if let next = nextEntry {
            if next.status == TimeEntryStatus.draft.rawValue {
                let beforeNextEnd = next.endAt.addingTimeInterval(-1)
                return lower...min(nowBound, max(lower, beforeNextEnd))
            }
            return lower...min(nowBound, next.startAt)
        }
        return lower...nowBound
    }

    private var nextEntry: TimeEntry? {
        guard let entryID = editEntry?.id ?? createdEntryID else { return nil }
        let currentEnd = endAt
        return allEntries
            .filter { $0.id != entryID && $0.startAt >= currentEnd }
            .sorted { $0.startAt < $1.startAt }
            .first
            ?? allEntries
            .filter { $0.id != entryID && $0.startAt > startAt }
            .sorted { $0.startAt < $1.startAt }
            .first
    }

    private var richCardTarget: RichCardContentTarget {
        if case .create(let project, _, _) = mode, createdEntryID == nil {
            let range = RichCardContentTimeEntryDraft(startAt: startAt, endAt: endAt)
            return .newTimeEntry(
                project: project,
                timeRange: range,
                initialText: "",
                save: { startAt, endAt, _ in try self.saveNewEntry(startAt: startAt, endAt: endAt) }
            )
        }
        if let entry = editEntry {
            return .timeEntry(entry)
        }
        if let entryID = createdEntryID, let entry = allEntries.first(where: { $0.id == entryID }) {
            return .timeEntry(entry)
        }
        if case .create(let project, _, _) = mode {
            let range = RichCardContentTimeEntryDraft(startAt: startAt, endAt: endAt)
            return .newTimeEntry(
                project: project,
                timeRange: range,
                initialText: "",
                save: { startAt, endAt, _ in try self.saveNewEntry(startAt: startAt, endAt: endAt) }
            )
        }
        fatalError("Invalid editor state")
    }

    private var richCardMode: RichCardContentMode {
        if isCreateMode, createdEntryID == nil { return .create }
        return .edit
    }

    private var richCardID: String {
        if isCreateMode, let id = createdEntryID {
            return "edit-\(id.uuidString)"
        }
        if isCreateMode { return "create" }
        return "edit-\(editEntry?.id.uuidString ?? "nil")"
    }

    // MARK: Linked Journal Card

    private func linkedJournalCard(_ journal: JournalEntry) -> some View {
        let moments = mediaMoments(for: journal)
        let body = allDocuments.first {
            $0.ownerID == journal.id && $0.ownerKindEnum == .journalEntry
        }?.body ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(DateFormatterFactory.timeOnly.string(from: journal.capturedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    editingJournal = journal
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityLabel("编辑关联随记")
                .accessibilityIdentifier("timeEntry.editor.thought.edit")
                Menu {
                    Button("取消关联", role: .destructive) {
                        pendingUnlinkedJournalIDs.insert(journal.id)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: TimelineCardActionMetrics.minTouch, height: TimelineCardActionMetrics.minTouch)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("更多操作")
                .accessibilityIdentifier("timeEntry.editor.thought.menu")
            }

            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("暂无文字内容")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                TimelineExpandableText(
                    text: body,
                    collapsedLineLimit: 6,
                    accessibilityPrefix: "timeEntry.editor.thought.body",
                    style: .thought
                )
            }

            if !moments.isEmpty {
                TimelineMediaGrid(moments: moments) { moment in
                    selectedThoughtMedia = moment
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TLTheme.cardRadius, style: .continuous)
                .fill(TLTheme.cardBackground)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeEntry.editor.thought.card")
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

    // MARK: Actions

    private func saveNewEntry(startAt: Date, endAt: Date) throws -> TimeEntry {
        guard let action = saveAction else {
            throw ValidationError.missingProject
        }
        let entry = try action(startAt, endAt, "")
        createdEntryID = entry.id
        return entry
    }

    private func save() {
        guard !isSaving, let contentSession else { return }
        let now = Date()

        if isCreateMode {
            guard endAt > startAt else {
                errorMessage = "结束时间必须晚于开始时间。"
                return
            }
            guard endAt <= now else {
                errorMessage = "结束时间不能晚于当前时间。"
                return
            }
        }

        isSaving = true
        Task {
            do {
                if isCreateMode {
                    try await contentSession.save()
                } else if let entry = editEntry, isDraft {
                    let cursorService = TimeCursorService(modelContext: modelContext)
                    guard let selectedProject else {
                        throw ValidationError.missingProject
                    }
                    try cursorService.validateEntryUpdate(entry, project: selectedProject, startAt: startAt, endAt: endAt, now: now)
                    if endAt > now {
                        errorMessage = "结束时间不能晚于当前时间。"
                        isSaving = false; return
                    }

                    if let next = nextEntry {
                        if next.status == TimeEntryStatus.draft.rawValue, endAt >= next.endAt {
                            errorMessage = "结束时间会挤掉下一段待确认记录。"
                            isSaving = false; return
                        }
                        if next.status != TimeEntryStatus.draft.rawValue, endAt > next.startAt {
                            errorMessage = "结束时间不能与后一段重叠。"
                            isSaving = false; return
                        }
                    }

                    try await contentSession.save(discardDraft: false)
                    try cursorService.updateEntry(entry, project: selectedProject, note: nil, startAt: startAt, endAt: endAt, now: now)
                    for journal in linkedJournals where pendingUnlinkedJournalIDs.contains(journal.id) {
                        try JournalContentService(modelContext: modelContext).unlink(journal)
                    }
                    try await contentSession.finishSuccessfulSave()
                } else {
                    try await contentSession.save(discardDraft: false)
                    for journal in linkedJournals where pendingUnlinkedJournalIDs.contains(journal.id) {
                        try JournalContentService(modelContext: modelContext).unlink(journal)
                    }
                    try await contentSession.finishSuccessfulSave()
                }
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleAddThought() {
        if isCreateMode, createdEntryID == nil {
            Task {
                guard let session = contentSession else { return }
                do {
                    guard endAt > startAt else {
                        errorMessage = "结束时间必须晚于开始时间。"
                        return
                    }
                    try await session.save()
                    // Find the created entry via content document
                    let docs = try modelContext.fetch(FetchDescriptor<ContentDocument>())
                    guard let doc = docs.first(where: { $0.id == session.contentID }),
                          let entry = allEntries.first(where: { $0.id == doc.ownerID })
                    else { return }
                    createdEntryID = entry.id
                    self.contentSession = nil  // force reload with .timeEntry target
                    showingAddThought = true
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } else {
            showingAddThought = true
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

    private func deleteDraft() {
        guard let entry = editEntry else { return }
        do {
            try TimeCursorService(modelContext: modelContext).deleteDraftEntry(entry)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelConfirmation() {
        guard let entry = editEntry else { return }
        do {
            try TimeCursorService(modelContext: modelContext).cancelConfirmation(entry)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performSkip() {
        guard let skipAction else { return }
        Task {
            do {
                try await contentSession?.cancel()
                let skipTo = min(max(endAt, (createCursorAt ?? Date()).addingTimeInterval(60)), nowBound)
                try skipAction(skipTo)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    let project = Project(name: "写材料", categoryName: "工作")
    NavigationStack {
        TimeEntryEditorView(
            mode: .create(project: project, cursorAt: Date(timeIntervalSinceNow: -1_800), defaultEndAt: Date()),
            saveAction: { startAt, endAt, note in
                TimeEntry(projectId: project.id, projectNameSnapshot: project.name, categoryNameSnapshot: project.categoryName, startAt: startAt, endAt: endAt, note: note)
            },
            skipAction: { _ in }
        )
    }
    .modelContainer(previewModelContainer)
}
