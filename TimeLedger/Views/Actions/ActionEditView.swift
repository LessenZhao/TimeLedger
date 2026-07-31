import SwiftData
import SwiftUI

struct ActionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let item: ActionItem?
    let defaultSortOrder: Int

    @State private var title = ""
    @State private var sortOrder = 0
    @State private var isArchived = false
    @State private var errorMessage: String?

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
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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

}
