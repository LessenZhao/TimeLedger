import Combine
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.sortOrder) private var projects: [Project]

    @State private var now = Date()
    @State private var searchText = ""
    @State private var newProjectName = ""
    @State private var newProjectCategory = "日常"
    @State private var errorMessage: String?
    @State private var canUndo = false
    @State private var adjustmentProject: Project?
    @State private var selectedView = 0

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init() {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                header
                if selectedView == 0 {
                    addProjectBar
                    projectList
                } else {
                    TimeListView(date: now, now: now, unclassifiedDuration: unclassifiedDuration)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .navigationTitle("TimeLedger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("撤销", action: undoLastEntry)
                        .disabled(!canUndo)
                }
            }
        }
        .task {
            bootstrap()
        }
        .onReceive(ticker) { value in
            now = value
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $adjustmentProject) { project in
            TimeAdjustmentSheet(
                project: project,
                cursorAt: currentCursorAt(),
                defaultEndAt: now,
                saveAction: { startAt, endAt, note in
                    saveAdjustedSegment(project: project, startAt: startAt, endAt: endAt, note: note)
                },
                skipAction: { endAt in
                    skipSegment(to: endAt)
                }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("当前未记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DurationFormatter.compact(unclassifiedDuration))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }

            Spacer()

            Picker("视图", selection: $selectedView) {
                Text("待办").tag(0)
                Text("时间").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
    }

    private var addProjectBar: some View {
        VStack(spacing: 8) {
            TextField("搜索项目", text: $searchText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                TextField("添加项目", text: $newProjectName)
                    .textFieldStyle(.roundedBorder)

                TextField("分类", text: $newProjectCategory)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 92)

                Button(action: addProject) {
                    Image(systemName: "plus")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if filteredProjects.isEmpty {
                    ContentUnavailableView("还没有项目", systemImage: "tray", description: Text("先添加一个常用项目。"))
                        .padding(.top, 40)
                } else {
                    ForEach(filteredProjects) { project in
                        ProjectRowView(
                            project: project,
                            todayDuration: todayDuration(for: project),
                            quickRecordAction: { quickRecord(project) },
                            adjustAction: { openAdjustment(for: project) }
                        )
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var filteredProjects: [Project] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            return projects
        }

        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(keyword)
            || project.categoryName.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var unclassifiedDuration: TimeInterval {
        (try? TimeCursorService(modelContext: modelContext).currentUnclassifiedDuration(now: now)) ?? 0
    }

    private func todayDuration(for project: Project) -> TimeInterval {
        (try? TimeSummaryService(modelContext: modelContext).todayDuration(for: project.id, now: now)) ?? 0
    }

    private func bootstrap() {
        do {
            _ = try TimeCursorService(modelContext: modelContext).getOrCreateCursor(now: now)
            _ = try getOrCreateSettings()
            refreshUndoState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = newProjectCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }

        let project = Project(
            name: name,
            categoryName: category.isEmpty ? "日常" : category,
            sortOrder: projects.count
        )
        modelContext.insert(project)

        do {
            try modelContext.save()
            newProjectName = ""
            newProjectCategory = "日常"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func quickRecord(_ project: Project) {
        do {
            let settings = try getOrCreateSettings()
            let currentDuration = try TimeCursorService(modelContext: modelContext).currentUnclassifiedDuration(now: now)

            guard currentDuration <= TimeInterval(settings.longUnclassifiedThresholdMinutes * 60) else {
                openAdjustment(for: project)
                return
            }

            _ = try TimeCursorService(modelContext: modelContext).quickRecord(project: project, now: now)
            refreshUndoState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openAdjustment(for project: Project) {
        now = Date()
        adjustmentProject = project
    }

    private func saveAdjustedSegment(project: Project, startAt: Date, endAt: Date, note: String) {
        do {
            _ = try TimeCursorService(modelContext: modelContext).recordSegment(
                project: project,
                startAt: startAt,
                endAt: endAt,
                note: note
            )
            refreshUndoState()
            now = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func skipSegment(to endAt: Date) {
        do {
            try TimeCursorService(modelContext: modelContext).skipSegment(to: endAt)
            refreshUndoState()
            now = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undoLastEntry() {
        do {
            try TimeCursorService(modelContext: modelContext).undoLastEntry()
            refreshUndoState()
            now = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshUndoState() {
        canUndo = ((try? TimeCursorService(modelContext: modelContext).canUndoLastEntry()) ?? false)
    }

    private func getOrCreateSettings() throws -> AppSettings {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1

        if let settings = try modelContext.fetch(descriptor).first {
            return settings
        }

        let settings = AppSettings()
        modelContext.insert(settings)
        try modelContext.save()
        return settings
    }

    private func currentCursorAt() -> Date {
        (try? TimeCursorService(modelContext: modelContext).getOrCreateCursor(now: now).cursorAt) ?? now
    }
}

#Preview {
    TodayView()
        .modelContainer(previewModelContainer)
}

let previewModelContainer: ModelContainer = {
    let schema = Schema(TimeLedgerModels.all)
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try! ModelContainer(for: schema, configurations: [configuration])
}()
