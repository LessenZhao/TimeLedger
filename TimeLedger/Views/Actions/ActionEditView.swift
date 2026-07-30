import SwiftData
import SwiftUI

struct ActionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var completions: [ActionCompletion]

    let item: ActionItem?
    let defaultSortOrder: Int

    @State private var title = ""
    @State private var sortOrder = 0
    @State private var isArchived = false
    @State private var errorMessage: String?
    @State private var showingUndoConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("事项") {
                    TextField("事项名称", text: $title)
                        .accessibilityIdentifier("action.title")
                    Stepper("排序：\(sortOrder)", value: $sortOrder, in: 0...999)
                    if item != nil {
                        Toggle("已归档", isOn: $isArchived)
                    }
                }

                if let item {
                    Section("今天") {
                        if let completion = todayCompletion(for: item) {
                            LabeledContent("状态", value: "已完成")
                            LabeledContent(
                                "完成时间",
                                value: DateFormatterFactory.dateTime.string(from: completion.completedAt)
                            )
                            if completion.linkedEntryId == nil {
                                Text("尚未找到覆盖这个时刻的时间项目，补录后会自动关联。")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Button("撤销今日完成", role: .destructive) {
                                showingUndoConfirmation = true
                            }
                            .accessibilityIdentifier("action.undo")
                        } else {
                            LabeledContent("状态", value: "未完成")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(item == nil ? "新增事项" : "编辑事项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("action.save")
                }
            }
            .onAppear(perform: load)
        }
        .alert("撤销今天的完成记录？", isPresented: $showingUndoConfirmation) {
            Button("保留", role: .cancel) {}
            Button("撤销完成", role: .destructive, action: undoToday)
        } message: {
            Text("只删除今天这一次完成事实，不影响事项和时间项目。")
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

    private func todayCompletion(for item: ActionItem) -> ActionCompletion? {
        let today = Calendar.current.startOfDay(for: Date())
        return completions.first {
            $0.actionItemId == item.id && $0.dayStart == today
        }
    }

    private func load() {
        guard let item else {
            sortOrder = defaultSortOrder
            return
        }
        title = item.title
        sortOrder = item.sortOrder
        isArchived = item.isArchived
    }

    private func save() {
        do {
            let service = ActionCompletionService(modelContext: modelContext)
            if let item {
                try service.updateItem(
                    item,
                    title: title,
                    sortOrder: sortOrder,
                    isArchived: isArchived
                )
            } else {
                _ = try service.createItem(title: title, sortOrder: sortOrder)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undoToday() {
        guard let item else { return }
        do {
            try ActionCompletionService(modelContext: modelContext).undoCompletion(for: item)
            showingUndoConfirmation = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
