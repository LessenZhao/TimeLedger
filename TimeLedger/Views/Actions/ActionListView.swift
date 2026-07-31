import SwiftData
import SwiftUI

struct ActionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActionItem.sortOrder) private var items: [ActionItem]
    @Query private var completions: [ActionCompletion]

    @State private var showingAdd = false
    @State private var editingItem: ActionItem?
    @State private var pendingCompletionDeletion: ActionCompletion?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("每日事项") {
                    if activeItems.isEmpty {
                        Text("还没有每日事项")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeItems) { item in
                            itemRow(item)
                        }
                    }
                }

                if !archivedItems.isEmpty {
                    Section("已归档") {
                        ForEach(archivedItems) { item in
                            itemRow(item)
                        }
                    }
                }

                Section("执行记录") {
                    if sortedCompletions.isEmpty {
                        Text("还没有执行记录")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedCompletions) { completion in
                            completionRow(completion)
                        }
                    }
                }
            }
            .navigationTitle("事项")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增事项")
                    .accessibilityIdentifier("action.add")
                }
            }
            .sheet(isPresented: $showingAdd) {
                ActionEditView(item: nil, defaultSortOrder: nextSortOrder)
            }
            .sheet(item: $editingItem) { item in
                ActionEditView(item: item, defaultSortOrder: item.sortOrder)
            }
        }
        .accessibilityIdentifier("actions.tab.root")
        .alert("删除这次完成记录？", isPresented: Binding(
            get: { pendingCompletionDeletion != nil },
            set: { if !$0 { pendingCompletionDeletion = nil } }
        )) {
            Button("保留", role: .cancel) {}
            Button("删除", role: .destructive, action: deletePendingCompletion)
        } message: {
            if let completion = pendingCompletionDeletion {
                Text(
                    "\(completion.actionTitleSnapshot) · "
                        + DateFormatterFactory.dateTime.string(from: completion.completedAt)
                        + "\n完成时间不会修改，只会删除这一条记录。"
                )
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
    }

    private var activeItems: [ActionItem] {
        items.filter { !$0.isArchived }
    }

    private var archivedItems: [ActionItem] {
        items.filter(\.isArchived)
    }

    private var nextSortOrder: Int {
        (items.map(\.sortOrder).max() ?? -1) + 1
    }

    private var sortedCompletions: [ActionCompletion] {
        completions.sorted { $0.completedAt > $1.completedAt }
    }

    private func itemRow(_ item: ActionItem) -> some View {
        Button {
            editingItem = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: statusIcon(for: item))
                    .foregroundStyle(statusColor(for: item))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .foregroundStyle(.primary)
                    if item.isArchived {
                        Text("已归档")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if item.activeCycleStartedAt != nil {
                        Text("新一轮进行中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("在首页按住0.2秒记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("action.item.\(item.id.uuidString)")
    }

    private func completionRow(_ completion: ActionCompletion) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(completion.actionTitleSnapshot)
                    .foregroundStyle(.primary)
                Text(DateFormatterFactory.dateTime.string(from: completion.completedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                pendingCompletionDeletion = completion
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除 \(completion.actionTitleSnapshot) 记录")
        }
        .accessibilityIdentifier("action.completion.row")
    }

    private func deletePendingCompletion() {
        guard let completion = pendingCompletionDeletion else { return }
        do {
            try ActionCompletionService(modelContext: modelContext).deleteCompletion(completion)
            pendingCompletionDeletion = nil
        } catch {
            pendingCompletionDeletion = nil
            errorMessage = error.localizedDescription
        }
    }

    private func todayCompletions(for item: ActionItem) -> [ActionCompletion] {
        let today = Calendar.current.startOfDay(for: Date())
        return completions.filter {
            $0.actionItemId == item.id && $0.dayStart == today
        }
        .sorted { $0.completedAt < $1.completedAt }
    }

    private func statusIcon(for item: ActionItem) -> String {
        if item.isArchived {
            return "archivebox"
        }
        return todayCompletions(for: item).isEmpty || item.activeCycleStartedAt != nil
            ? "circle"
            : "checkmark.circle.fill"
    }

    private func statusColor(for item: ActionItem) -> Color {
        if item.isArchived {
            return .secondary
        }
        return todayCompletions(for: item).isEmpty || item.activeCycleStartedAt != nil
            ? .secondary
            : .accentColor
    }
}

#Preview {
    ActionListView()
        .modelContainer(previewModelContainer)
}
