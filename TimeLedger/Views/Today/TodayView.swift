import Combine
import SwiftData
import SwiftUI
import UIKit

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.sortOrder) private var projects: [Project]

    @State private var now = Date()
    @State private var errorMessage: String?
    @State private var canUndo = false
    @State private var adjustmentProject: Project?
    @State private var selectedView = 0
    @State private var showingThoughtCapture = false
    @State private var showingAddProject = false

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init() {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                    .frame(height: 44)
                segmentBar
                    .frame(height: 42)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(TLTheme.pageBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
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
            Button("好", role: .cancel) {}
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
        .sheet(isPresented: $showingThoughtCapture) {
            ThoughtQuickCaptureSheet()
        }
        .sheet(isPresented: $showingAddProject) {
            ProjectEditView(project: nil)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 0) {
            Button("撤销", action: undoLastEntry)
                .font(TLTheme.statusFont)
                .disabled(!canUndo)
                .frame(width: 64, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Text("未记录")
                    .foregroundStyle(.secondary)
                Text(DurationFormatter.compact(unclassifiedDuration))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .font(TLTheme.statusFont)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Group {
                if selectedView == 1 {
                    Button("确认", action: confirmDrafts)
                        .font(TLTheme.statusFont.weight(.semibold))
                } else {
                    Button {
                        showingThoughtCapture = true
                    } label: {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: TLTheme.statusIconSize, weight: .medium))
                    }
                    .accessibilityLabel("快速想法")
                }
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12)
    }

    private var segmentBar: some View {
        Picker("视图", selection: $selectedView) {
            Text("项目").tag(0)
            Text("草稿").tag(1)
            Text("已确认").tag(2)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        // Keep all panes mounted so chrome above does not reflow when switching.
        ZStack(alignment: .top) {
            projectList
                .opacity(selectedView == 0 ? 1 : 0)
                .allowsHitTesting(selectedView == 0)

            DraftListView()
                .padding(.horizontal, 12)
                .opacity(selectedView == 1 ? 1 : 0)
                .allowsHitTesting(selectedView == 1)

            ConfirmedListView()
                .opacity(selectedView == 2 ? 1 : 0)
                .allowsHitTesting(selectedView == 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var activeProjects: [Project] {
        projects.filter { !SystemProject.isUnknown($0) }
    }

    private var projectList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("点 ＋ 归档")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink {
                    ProjectManageView()
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    Text("管理")
                        .font(.system(size: 15, weight: .medium))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: TLTheme.listSpacing) {
                    if activeProjects.isEmpty {
                        emptyProjects
                    } else {
                        ForEach(activeProjects) { project in
                            ProjectRowView(
                                project: project,
                                todayDuration: todayDuration(for: project),
                                quickRecordAction: { quickRecord(project) },
                                adjustAction: { openAdjustment(for: project) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            if !activeProjects.isEmpty {
                Text("轻点归档 · 长按调整")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 6)
            }
        }
    }

    private var emptyProjects: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "还没有项目",
                systemImage: "tray",
                description: Text("先添加几个常用项目，之后一键归档时间。")
            )
            Button("添加项目") {
                showingAddProject = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 32)
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

    private func quickRecord(_ project: Project) {
        do {
            let settings = try getOrCreateSettings()
            let currentDuration = try TimeCursorService(modelContext: modelContext).currentUnclassifiedDuration(now: now)

            guard currentDuration <= TimeInterval(settings.longUnclassifiedThresholdMinutes * 60) else {
                openAdjustment(for: project)
                return
            }

            _ = try TimeCursorService(modelContext: modelContext).quickRecord(project: project, now: now)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            now = Date()
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    private func confirmDrafts() {
        do {
            let count = try ValidationService(modelContext: modelContext).confirmAllEligibleDrafts()
            if count == 0 {
                errorMessage = "没有可确认的草稿。未知项目请先选择具体项目。"
                return
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
