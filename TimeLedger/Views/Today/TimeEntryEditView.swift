import SwiftData
import SwiftUI

struct TimeEntryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.sortOrder) private var projects: [Project]
    @Query private var allThoughts: [ThoughtNote]
    @Query private var allEntries: [TimeEntry]

    let entry: TimeEntry

    @State private var selectedProjectId: UUID
    @State private var note: String
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var minimumStartAt: Date
    @State private var errorMessage: String?
    @State private var showingDeleteAlert = false
    @State private var showingCancelConfirmationAlert = false
    @State private var showingAddThought = false
    @State private var editingStart = false
    @State private var editingEnd = false

    init(entry: TimeEntry) {
        self.entry = entry
        _selectedProjectId = State(initialValue: entry.projectId)
        _note = State(initialValue: entry.note)
        _startAt = State(initialValue: entry.startAt)
        _endAt = State(initialValue: entry.endAt)
        _minimumStartAt = State(initialValue: entry.startAt)
    }

    var body: some View {
        Form {
            Section {
                Picker("项目", selection: $selectedProjectId) {
                    ForEach(selectableProjects) { project in
                        Text(project.name).tag(project.id)
                    }
                }

                if isDraft {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            editingStart.toggle()
                            if editingStart { editingEnd = false }
                        }
                    } label: {
                        LabeledContent("开始") {
                            Text(DateFormatterFactory.dateTime.string(from: startAt))
                                .foregroundStyle(editingStart ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if editingStart {
                        DatePicker(
                            "开始",
                            selection: $startAt,
                            in: startPickerRange,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            editingEnd.toggle()
                            if editingEnd { editingStart = false }
                        }
                    } label: {
                        LabeledContent("结束") {
                            Text(DateFormatterFactory.dateTime.string(from: endAt))
                                .foregroundStyle(editingEnd ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if editingEnd {
                        DatePicker(
                            "结束",
                            selection: $endAt,
                            in: endPickerRange,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    LabeledContent("开始") {
                        Text(DateFormatterFactory.dateTime.string(from: entry.startAt))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("结束") {
                        Text(DateFormatterFactory.dateTime.string(from: entry.endAt))
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    TimeEntryNoteEditView(note: $note)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("备注")
                            .foregroundStyle(.primary)
                        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("点击编写")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            } footer: {
                if SystemProject.isUnknownEntry(entry) {
                    Text("请选择具体项目后再确认。")
                }
            }

            Section {
                Button {
                    showingAddThought = true
                } label: {
                    Label("添加思考", systemImage: "plus")
                }

                if linkedThoughts.isEmpty {
                    Text("暂无关联思考")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(linkedThoughts) { thought in
                        NavigationLink {
                            ThoughtEditView(thought: thought, entry: entry)
                        } label: {
                            thoughtRow(thought)
                        }
                    }
                }
            } header: {
                Text("思考")
            }

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
        .navigationTitle(isDraft ? "编辑草稿" : "编辑记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存", action: save)
                    .disabled(saveDisabled)
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
            ThoughtAddSheet { newBody in
                addThought(body: newBody)
            }
        }
        .onChange(of: startAt) { _, newStart in
            if endAt <= newStart {
                endAt = min(newStart.addingTimeInterval(60), endUpperBound)
            }
            if endAt > endUpperBound {
                endAt = endUpperBound
            }
        }
        .onChange(of: endAt) { _, newEnd in
            if newEnd > endUpperBound {
                endAt = endUpperBound
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

    private var saveDisabled: Bool {
        selectedProject == nil || (isDraft && endAt <= startAt)
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

    private func thoughtRow(_ thought: ThoughtNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DateFormatterFactory.timeOnly.string(from: thought.capturedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(thought.body)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineSpacing(6)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
    }

    private func addThought(body: String) -> Bool {
        do {
            _ = try ThoughtLinkingService(modelContext: modelContext).addThought(to: entry, body: body)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func save() {
        guard let project = selectedProject else {
            errorMessage = "请选择项目。"
            return
        }

        let now = Date()
        if endAt > now {
            errorMessage = "结束时间不能晚于当前时间。"
            return
        }
        if let next = nextEntry {
            if next.status == TimeEntryStatus.draft.rawValue {
                if endAt >= next.endAt {
                    errorMessage = "结束时间会挤掉下一段草稿。"
                    return
                }
            } else if endAt > next.startAt {
                errorMessage = "结束时间不能与后一段重叠。"
                return
            }
        }

        do {
            try TimeCursorService(modelContext: modelContext).updateEntry(
                entry,
                project: project,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                startAt: startAt,
                endAt: endAt,
                now: now
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
