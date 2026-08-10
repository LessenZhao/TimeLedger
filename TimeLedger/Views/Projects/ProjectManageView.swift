import SwiftData
import SwiftUI

struct ProjectManageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.sortOrder) private var allProjects: [Project]

    @State private var showAddSheet = false
    @State private var editingProject: Project?
    @State private var deleteTarget: Project?
    @State private var deleteError: String?

    private var activeProjects: [Project] {
        allProjects.filter { !$0.isArchived && !SystemProject.isUnknown($0) }
    }

    private var archivedProjects: [Project] {
        allProjects.filter { $0.isArchived && !SystemProject.isUnknown($0) }
    }

    var body: some View {
        List {
            Section("活跃项目") {
                if activeProjects.isEmpty {
                    Text("暂无活跃项目")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeProjects) { project in
                        projectRow(project)
                    }
                }
            }

            if !archivedProjects.isEmpty {
                Section("已归档") {
                    ForEach(archivedProjects) { project in
                        projectRow(project)
                    }
                }
            }
        }
        .navigationTitle("项目管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ProjectEditView(project: nil)
        }
        .sheet(item: $editingProject) { project in
            ProjectEditView(project: project)
        }
        .alert("删除项目", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                deleteProject(deleteTarget)
            }
        } message: {
            Text("确定删除该项目吗？关联的时间记录将保留项目快照。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func projectRow(_ project: Project) -> some View {
        Button {
            editingProject = project
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: project.colorHex))
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let emoji = project.emoji, !emoji.isEmpty {
                            Text(emoji)
                        }
                        Text(project.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    Text(project.categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if project.isArchived {
                    Text("已归档")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.gray.opacity(0.12)))
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteTarget = project
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func deleteProject(_ project: Project?) {
        guard let project else { return }
        do {
            try TimeLedgerEngine(modelContext: modelContext).deleteProject(project)
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

#Preview {
    ProjectManageView()
        .modelContainer(previewModelContainer)
}
