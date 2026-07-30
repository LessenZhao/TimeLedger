import SwiftData
import SwiftUI

struct ActionListView: View {
    @Query(sort: \ActionItem.sortOrder) private var items: [ActionItem]
    @Query private var completions: [ActionCompletion]

    @State private var showingAdd = false
    @State private var editingItem: ActionItem?

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
                    } else if let completion = todayCompletion(for: item) {
                        Text("今天 \(DateFormatterFactory.timeOnly.string(from: completion.completedAt)) 完成")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("今天未完成")
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

    private func todayCompletion(for item: ActionItem) -> ActionCompletion? {
        let today = Calendar.current.startOfDay(for: Date())
        return completions.first {
            $0.actionItemId == item.id && $0.dayStart == today
        }
    }

    private func statusIcon(for item: ActionItem) -> String {
        if item.isArchived {
            return "archivebox"
        }
        return todayCompletion(for: item) == nil ? "circle" : "checkmark.circle.fill"
    }

    private func statusColor(for item: ActionItem) -> Color {
        if item.isArchived {
            return .secondary
        }
        return todayCompletion(for: item) == nil ? .secondary : .accentColor
    }
}

#Preview {
    ActionListView()
        .modelContainer(previewModelContainer)
}
