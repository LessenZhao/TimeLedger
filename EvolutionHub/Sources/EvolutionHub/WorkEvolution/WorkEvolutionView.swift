import EvolutionCore
import EvolutionHubCore
import SwiftUI

enum WorkEvolutionMode: String, CaseIterable, Identifiable {
    case day = "按天"
    case project = "按项目"

    var id: Self { self }
}

struct WorkEvolutionView: View {
    @EnvironmentObject private var store: WorkEvolutionHubStore
    @State private var mode: WorkEvolutionMode = .day

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("查看方式", selection: $mode) {
                    ForEach(WorkEvolutionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Spacer()

                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }

                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            GeometryReader { geometry in
                HSplitView {
                    navigation
                        .frame(
                            minWidth: 150,
                            idealWidth: 180,
                            maxWidth: 320,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )

                    mainContent
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)

                    SourceConversationInspector(dateKey: selectedDayKey)
                        .frame(
                            minWidth: 240,
                            idealWidth: 280,
                            maxWidth: 520,
                            maxHeight: .infinity
                        )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("工作沉淀")
        .onAppear {
            selectFallbackDayIfNeeded()
            selectFallbackProjectIfNeeded()
        }
        .onChange(of: availableDayKeys) { _, _ in
            selectFallbackDayIfNeeded()
        }
        .onChange(of: store.snapshot.projects.map(\.id)) { _, _ in
            selectFallbackProjectIfNeeded()
        }
    }

    @ViewBuilder
    private var navigation: some View {
        switch mode {
        case .day:
            VStack(alignment: .leading, spacing: 8) {
                Text("日期")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                if availableDayKeys.isEmpty {
                    ContentUnavailableView(
                        "还没有沉淀记录",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("导入历史提炼结果后会按日期显示。")
                    )
                } else {
                    List(selection: daySelection) {
                        ForEach(availableDayKeys, id: \.self) { key in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(key)
                                if workDayKeys.contains(key) == false {
                                    Text("后来认识")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(Optional(key))
                        }
                    }
                    .listStyle(.sidebar)
                }
            }

        case .project:
            VStack(alignment: .leading, spacing: 8) {
                Text("项目")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                if store.snapshot.projects.isEmpty {
                    ContentUnavailableView("还没有项目", systemImage: "square.stack.3d.up.slash")
                } else {
                    List(selection: projectSelection) {
                        ForEach(store.snapshot.projects.sorted(by: projectOrdering)) { project in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name)
                                Text(project.goal)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .tag(Optional(project.id))
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch mode {
        case .day:
            if let selectedDayKey {
                WorkEvolutionDayView(dateKey: selectedDayKey)
            } else {
                ContentUnavailableView("选择日期", systemImage: "calendar")
            }
        case .project:
            if let projectId = store.selectedProjectId {
                WorkEvolutionProjectView(projectId: projectId)
            } else {
                ContentUnavailableView("选择项目", systemImage: "square.stack.3d.up")
            }
        }
    }

    private var availableDayKeys: [String] {
        var keys = Set(store.snapshot.days.map(\.date))
        keys.formUnion(store.snapshot.nodes.map { EvolutionUIDate.dayKey($0.recognizedAt) })
        keys.formUnion(store.snapshot.annotations.map { EvolutionUIDate.dayKey($0.recognizedAt) })
        return keys.sorted(by: >)
    }

    private var workDayKeys: Set<String> {
        Set(store.snapshot.days.map(\.date))
    }

    private var selectedDayKey: String? {
        let current = EvolutionUIDate.dayKey(store.selectedDay)
        return availableDayKeys.contains(current) ? current : availableDayKeys.first
    }

    private var daySelection: Binding<String?> {
        Binding(
            get: { selectedDayKey },
            set: { key in
                guard let key, let date = EvolutionUIDate.date(from: key) else { return }
                store.selectedDay = date
                store.selectedSourceSessionId = nil
            }
        )
    }

    private var projectSelection: Binding<String?> {
        Binding(
            get: { store.selectedProjectId },
            set: { projectId in
                store.selectedProjectId = projectId
                store.selectedSourceSessionId = nil
            }
        )
    }

    private func selectFallbackDayIfNeeded() {
        guard !availableDayKeys.isEmpty else { return }
        let current = EvolutionUIDate.dayKey(store.selectedDay)
        guard !availableDayKeys.contains(current),
              let first = availableDayKeys.first,
              let date = EvolutionUIDate.date(from: first) else { return }
        store.selectedDay = date
        store.selectedSourceSessionId = nil
    }

    private func selectFallbackProjectIfNeeded() {
        let available = store.snapshot.projects.sorted(by: projectOrdering)
        guard !available.isEmpty else {
            store.selectedProjectId = nil
            return
        }
        if let selected = store.selectedProjectId,
           available.contains(where: { $0.id == selected }) {
            return
        }
        store.selectedProjectId = available.first?.id
    }

    private func projectOrdering(_ lhs: EvolutionProject, _ rhs: EvolutionProject) -> Bool {
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.id < rhs.id
    }
}

enum EvolutionUIDate {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_Hans_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }()

    static func dayKey(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(from key: String) -> Date? {
        let pieces = key.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: pieces[0],
            month: pieces[1],
            day: pieces[2],
            hour: 12
        ))
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
