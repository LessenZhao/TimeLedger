import SwiftData
import SwiftUI

struct ProjectEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let project: Project?

    @State private var name = ""
    @State private var categoryName = ""
    @State private var colorHex = ""
    @State private var sortOrder = 0
    @State private var isArchived = false
    @State private var errorMessage: String?

    var isEditing: Bool { project != nil }

    private var suggestedEmoji: String {
        ProjectEmojiMatcher.emoji(for: name, categoryName: categoryName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("项目名称", text: $name)
                    TextField("分类", text: $categoryName)
                    LabeledContent("图标") {
                        Text(suggestedEmoji)
                            .font(.title2)
                    }
                    TextField("颜色 Hex（可选，如 #FF6B6B）", text: $colorHex)
                }

                Section("排序") {
                    Stepper("排序：\(sortOrder)", value: $sortOrder, in: 0...999, step: 1)
                }

                if isEditing {
                    Section {
                        Toggle("已归档", isOn: $isArchived)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑项目" : "新增项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { loadProject() }
        }
    }

    private func loadProject() {
        guard let project else { return }
        name = project.name
        categoryName = project.categoryName
        colorHex = project.colorHex ?? ""
        sortOrder = project.sortOrder
        isArchived = project.isArchived
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "项目名称不能为空"
            return
        }

        let resolvedCategory = trimmedCategory.isEmpty ? "日常" : trimmedCategory
        let emoji = ProjectEmojiMatcher.emoji(for: trimmedName, categoryName: resolvedCategory)

        do {
            try TimeLedgerEngine(modelContext: modelContext).saveProject(
                project: project,
                name: trimmedName,
                categoryName: resolvedCategory,
                emoji: emoji,
                colorHex: colorHex.isEmpty ? nil : colorHex,
                sortOrder: sortOrder,
                isArchived: isArchived
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ProjectEditView(project: nil)
        .modelContainer(previewModelContainer)
}
