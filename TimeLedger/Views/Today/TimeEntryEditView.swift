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
                    DatePicker(
                        "开始",
                        selection: $startAt,
                        in: minimumStartAt...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    DatePicker(
                        "结束",
                        selection: $endAt,
                        in: startAt...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
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
                    HStack(alignment: .top) {
                        Text("备注")
                        Spacer(minLength: 12)
                        Text(notePreview)
                            .foregroundStyle(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .tertiary : .secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                if SystemProject.isUnknownEntry(entry) {
                    Text("请选择具体项目后再确认。")
                } else if isDraft, let maxEnd = maximumEndAt {
                    Text("结束不能晚于下一段 \(DateFormatterFactory.timeOnly.string(from: maxEnd))")
                }
            }

            Section {
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
                Button {
                    showingAddThought = true
                } label: {
                    Label("添加思考", systemImage: "plus")
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
            Text("删除后后面的记录会向前贴紧；若是最后一条，未记录光标会退回。")
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
                endAt = newStart.addingTimeInterval(60)
            }
            if let maxEnd = maximumEndAt, endAt > maxEnd {
                endAt = maxEnd
            }
        }
        .onChange(of: endAt) { _, newEnd in
            if let maxEnd = maximumEndAt, newEnd > maxEnd {
                endAt = maxEnd
            }
        }
    }

    private var notePreview: String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "点击编写" : trimmed
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

    private var maximumEndAt: Date? {
        allEntries
            .filter { $0.id != entry.id && $0.startAt >= entry.endAt - 1 }
            .sorted { $0.startAt < $1.startAt }
            .first?
            .startAt
            ?? allEntries
            .filter { $0.id != entry.id && $0.startAt > entry.startAt }
            .sorted { $0.startAt < $1.startAt }
            .first?
            .startAt
    }

    private var linkedThoughts: [ThoughtNote] {
        allThoughts
            .filter { $0.linkedEntryId == entry.id }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private func thoughtRow(_ thought: ThoughtNote) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DateFormatterFactory.timeOnly.string(from: thought.capturedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(thought.body)
                .font(.footnote)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private func addThought(body: String) {
        do {
            _ = try ThoughtLinkingService(modelContext: modelContext).addThought(to: entry, body: body)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let project = selectedProject else {
            errorMessage = "请选择项目。"
            return
        }

        if let maxEnd = maximumEndAt, endAt > maxEnd {
            errorMessage = "结束时间不能与后一段重叠。"
            return
        }

        do {
            try TimeCursorService(modelContext: modelContext).updateEntry(
                entry,
                project: project,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                startAt: startAt,
                endAt: endAt
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
