import SwiftData
import SwiftUI

struct TimeEntryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.sortOrder) private var projects: [Project]

    let entry: TimeEntry

    @State private var selectedProjectId: UUID
    @State private var note: String
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var errorMessage: String?
    @State private var showingDeleteAlert = false
    @State private var showingCancelConfirmationAlert = false

    init(entry: TimeEntry) {
        self.entry = entry
        _selectedProjectId = State(initialValue: entry.projectId)
        _note = State(initialValue: entry.note)
        _startAt = State(initialValue: entry.startAt)
        _endAt = State(initialValue: entry.endAt)
    }

    var body: some View {
        Form {
            Section("项目") {
                Picker("项目", selection: $selectedProjectId) {
                    ForEach(projects) { project in
                        Text(project.name).tag(project.id)
                    }
                }
            }

            Section("时间") {
                if isDraft {
                    DatePicker("开始", selection: $startAt, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("结束", selection: $endAt, displayedComponents: [.date, .hourAndMinute])
                } else {
                    LabeledContent("开始", value: DateFormatterFactory.dateTime.string(from: entry.startAt))
                    LabeledContent("结束", value: DateFormatterFactory.dateTime.string(from: entry.endAt))
                }
            }

            Section("备注") {
                TextField("备注", text: $note, axis: .vertical)
                    .lineLimit(3...6)
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
                    Text("取消确认后，这条记录会回到草稿状态，但不会改变当前未记录时间的位置。")
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
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("删除这条草稿？", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: deleteDraft)
        } message: {
            Text("删除后会移除这段时间记录。")
        }
        .alert("取消确认？", isPresented: $showingCancelConfirmationAlert) {
            Button("保留确认", role: .cancel) {}
            Button("取消确认", role: .destructive, action: cancelConfirmation)
        } message: {
            Text("这条记录会变回草稿，时间位置不会改变。")
        }
    }

    private var isDraft: Bool {
        entry.status == TimeEntryStatus.draft.rawValue
    }

    private var saveDisabled: Bool {
        selectedProject == nil || (isDraft && endAt <= startAt)
    }

    private var selectedProject: Project? {
        projects.first { $0.id == selectedProjectId }
    }

    private func save() {
        guard let project = selectedProject else {
            errorMessage = "请选择项目。"
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
