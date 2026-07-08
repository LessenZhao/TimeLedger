import SwiftData
import SwiftUI

struct ProjectEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let project: Project?

    @State private var name = ""
    @State private var categoryName = ""
    @State private var emoji = ""
    @State private var colorHex = ""
    @State private var sortOrder = 0
    @State private var isArchived = false
    @State private var errorMessage: String?

    var isEditing: Bool { project != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("项目名称", text: $name)
                    TextField("分类", text: $categoryName)
                    TextField("Emoji（可选）", text: $emoji)
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
        emoji = project.emoji ?? ""
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

        if let project {
            project.name = trimmedName
            project.categoryName = trimmedCategory.isEmpty ? "日常" : trimmedCategory
            project.emoji = emoji.isEmpty ? nil : emoji
            project.colorHex = colorHex.isEmpty ? nil : colorHex
            project.sortOrder = sortOrder
            project.isArchived = isArchived
            project.updatedAt = Date()
        } else {
            let newProject = Project(
                name: trimmedName,
                categoryName: trimmedCategory.isEmpty ? "日常" : trimmedCategory,
                emoji: emoji.isEmpty ? nil : emoji,
                colorHex: colorHex.isEmpty ? nil : colorHex,
                sortOrder: sortOrder
            )
            modelContext.insert(newProject)
        }

        do {
            try modelContext.save()
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
