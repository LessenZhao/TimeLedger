import Combine
import SwiftData
import SwiftUI
import UIKit

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \ActionItem.sortOrder) private var actionItems: [ActionItem]
    @Query private var actionCompletions: [ActionCompletion]

    @State private var now = Date()
    @State private var errorMessage: String?
    @State private var undoToast: UndoToastInfo?
    @State private var statusBarExpanded = false
    @State private var adjustmentProject: Project?
    @State private var selectedView = 0
    @State private var showingThoughtCapture = false
    @State private var composerFocusText = true
    @State private var showingAddProject = false
    @State private var showingCamera = false
    @State private var showingCameraFixture = false
    @State private var undoToastTask: Task<Void, Never>?
    @State private var expandTask: Task<Void, Never>?
    @State private var pendingCameraCapture: CameraCapture?
    @State private var cameraAccessResult: CameraAccessResult?
    @State private var actionItemAwaitingNewCycle: ActionItem?

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
        .alert("开始新一轮？", isPresented: Binding(
            get: { actionItemAwaitingNewCycle != nil },
            set: { if !$0 { actionItemAwaitingNewCycle = nil } }
        )) {
            Button("开始新一轮") {
                startNewActionCycle()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会保留之前的完成记录，并让这个事项恢复为待完成。")
        }
        .sheet(item: $adjustmentProject) { project in
            NavigationStack {
                TimeEntryEditorView(
                    mode: .create(project: project, cursorAt: currentCursorAt(), defaultEndAt: now),
                    saveAction: { startAt, endAt, note in
                        try saveAdjustedSegment(project: project, startAt: startAt, endAt: endAt, note: note)
                    },
                    skipAction: { endAt in
                        try skipSegment(to: endAt)
                    }
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingThoughtCapture) {
            ThoughtComposerSheet(focusTextOnAppear: composerFocusText)
        }
        .sheet(isPresented: $showingAddProject) {
            ProjectEditView(project: nil)
        }
        .fullScreenCover(
            isPresented: $showingCamera,
            onDismiss: handleCameraDismissal
        ) {
            SystemCameraPicker { result in
                guard let result else {
                    showingCamera = false
                    return
                }
                switch result {
                case .success(let capture):
                    pendingCameraCapture = capture
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
                showingCamera = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(
            isPresented: $showingCameraFixture,
            onDismiss: handleCameraDismissal
        ) {
            CameraBoundaryFixtureView { capture in
                pendingCameraCapture = capture
                showingCameraFixture = false
            }
        }
        .alert("无法打开相机", isPresented: Binding(
            get: { cameraAccessResult != nil },
            set: { if !$0 { cameraAccessResult = nil } }
        )) {
            if cameraAccessResult?.offersSettings == true {
                Button("去设置") { openSystemSettings() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(cameraAccessResult?.message ?? "")
        }
    }

   private var statusBar: some View {
       HStack(spacing: 0) {
            Color.clear
                .frame(width: 64, alignment: .leading)

            Spacer(minLength: 0)

            centerStatus
                .contentShape(Rectangle())
                .onTapGesture { handleStatusBarTap() }

            Spacer(minLength: 0)

            Group {
                if selectedView == 1 {
                    Button("确认", action: confirmDrafts)
                        .font(TLTheme.statusFont.weight(.semibold))
                } else {
                    QuickCaptureCameraControl(
                        tapAction: {
                            composerFocusText = true
                            showingThoughtCapture = true
                        },
                        cameraAction: { beginCameraFlow() }
                    )
                }
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12)
    }

   private var segmentBar: some View {
        Picker("视图", selection: $selectedView) {
            Text("项目").tag(0)
            Text("待确认").tag(1)
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
                    if !activeActionItems.isEmpty {
                        todayActions
                    }
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
        }
    }

    private var activeActionItems: [ActionItem] {
        actionItems.filter { !$0.isArchived }
    }

    private var todayActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日事项")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 116), spacing: 8)],
                spacing: 8
            ) {
                ForEach(activeActionItems) { item in
                    actionButton(item)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func actionButton(_ item: ActionItem) -> some View {
        let completed = isCompletedToday(item)

        return HStack(spacing: 7) {
            Text(actionDisplayTitle(for: item))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(completed ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(
            RoundedRectangle(cornerRadius: TLTheme.cardRadius)
                .fill(completed ? Color.accentColor : TLTheme.cardBackground)
        )
        .overlay {
            if !completed {
                RoundedRectangle(cornerRadius: TLTheme.cardRadius)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: 0.2, maximumDistance: 24)
                .exclusively(before: TapGesture())
                .onEnded { result in
                    switch result {
                    case .first:
                        if completed {
                            offerNewActionCycle(for: item)
                        } else {
                            completeAction(item)
                        }
                    case .second:
                        break
                    }
                }
        )
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(item.title)
        .accessibilityValue(actionAccessibilityValue(for: item))
        .accessibilityAction {
            guard !completed else { return }
            completeAction(item)
        }
        .accessibilityAction(named: Text("开始新一轮")) {
            offerNewActionCycle(for: item)
        }
        .accessibilityIdentifier("today.action.\(item.id.uuidString)")
    }

    private func isCompletedToday(_ item: ActionItem) -> Bool {
        item.activeCycleStartedAt == nil && todayCompletionCount(for: item) > 0
    }

    private func todayCompletionCount(for item: ActionItem) -> Int {
        let today = Calendar.current.startOfDay(for: now)
        return actionCompletions.count {
            $0.actionItemId == item.id && $0.dayStart == today
        }
    }

    private func actionDisplayTitle(for item: ActionItem) -> String {
        let count = todayCompletionCount(for: item)
        return "\(count)次  \(item.title)"
    }

    private func actionAccessibilityValue(for item: ActionItem) -> String {
        let count = todayCompletionCount(for: item)
        if item.activeCycleStartedAt != nil {
            return "第\(count + 1)轮未完成，今天已完成\(count)次"
        }
        return count > 0 ? "已完成，今天\(count)次" : "未完成，今天0次"
    }

    private func completeAction(_ item: ActionItem) {
        do {
            let completedAt = Date()
            _ = try ActionCompletionService(modelContext: modelContext).complete(item, now: completedAt)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            now = completedAt
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func offerNewActionCycle(for item: ActionItem) {
        guard isCompletedToday(item) else { return }
        actionItemAwaitingNewCycle = item
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func startNewActionCycle() {
        guard let item = actionItemAwaitingNewCycle else { return }
        do {
            let startedAt = Date()
            try ActionCompletionService(modelContext: modelContext).startNewCycle(for: item, now: startedAt)
            actionItemAwaitingNewCycle = nil
            now = startedAt
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            actionItemAwaitingNewCycle = nil
            errorMessage = error.localizedDescription
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

    @ViewBuilder
    private var centerStatus: some View {
        if let toast = undoToast {
            HStack(spacing: 5) {
                Text(toast.projectName)
                    .foregroundStyle(.primary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(DurationFormatter.compact(toast.duration))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("·")
                    .foregroundStyle(.secondary)
               Text("撤销")
                    .foregroundStyle(Color.accentColor)
                   .fontWeight(.semibold)
            }
            .font(TLTheme.statusFont)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else if statusBarExpanded {
            HStack(spacing: 5) {
                Text("从 \(DateFormatterFactory.timeOnly.string(from: cursorStartAt)) 起")
                    .foregroundStyle(.secondary)
                if let last = lastEntryBeforeCursor {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("上次\(last.projectNameSnapshot)\(DurationFormatter.compact(last.durationSeconds))")
                        .foregroundStyle(.primary)
                }
            }
            .font(TLTheme.statusFont)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
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
        }
    }

    private var cursorStartAt: Date {
        (try? TimeCursorService(modelContext: modelContext).getOrCreateCursor(now: now).cursorAt) ?? now
    }

    private var lastEntryBeforeCursor: TimeEntry? {
        try? TimeCursorService(modelContext: modelContext).lastEntryBeforeCursor()
    }

    private func todayDuration(for project: Project) -> TimeInterval {
        (try? TimeSummaryService(modelContext: modelContext).todayDuration(for: project.id, now: now)) ?? 0
    }

   private func bootstrap() {
       do {
           _ = try TimeCursorService(modelContext: modelContext).getOrCreateCursor(now: now)
           _ = try getOrCreateSettings()
           _ = try ActionCompletionService(modelContext: modelContext).reconcileAllLinks()
       } catch {
           errorMessage = error.localizedDescription
       }
   }

   private func quickRecord(_ project: Project) {
       do {
           let actionNow = Date()
           now = actionNow
           let settings = try getOrCreateSettings()
           let currentDuration = try TimeCursorService(modelContext: modelContext)
               .currentUnclassifiedDuration(now: actionNow)

           guard currentDuration <= TimeInterval(settings.longUnclassifiedThresholdMinutes * 60) else {
               openAdjustment(for: project)
               return
           }

            let entry = try TimeCursorService(modelContext: modelContext).quickRecord(project: project, now: actionNow)
           UIImpactFeedbackGenerator(style: .light).impactOccurred()
           now = Date()
            showUndoToast(for: entry)
       } catch {
           errorMessage = error.localizedDescription
       }
   }

   private func openAdjustment(for project: Project) {
       now = Date()
       adjustmentProject = project
   }

   private func saveAdjustedSegment(
       project: Project,
       startAt: Date,
       endAt: Date,
       note: String
   ) throws -> TimeEntry {
       let entry = try TimeCursorService(modelContext: modelContext).recordSegment(
           project: project,
           startAt: startAt,
           endAt: endAt,
           note: note,
           now: Date()
       )
       UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showUndoToast(for: entry)
       now = Date()
       return entry
   }

   private func skipSegment(to endAt: Date) throws {
       try TimeCursorService(modelContext: modelContext).skipSegment(to: endAt)
        cancelUndoToast()
       now = Date()
   }

    private func confirmDrafts() {
        do {
            let count = try ValidationService(modelContext: modelContext).confirmAllEligibleDrafts()
            if count == 0 {
                errorMessage = "没有可确认的记录。未知项目请先选择具体项目。"
                return
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Status bar state machine

    private func handleStatusBarTap() {
        if undoToast != nil {
            performUndo()
        } else if statusBarExpanded {
            collapseStatusBar()
        } else {
            expandStatusBar()
        }
    }

    private func showUndoToast(for entry: TimeEntry) {
        cancelUndoToast()
        collapseStatusBar()
        let duration = entry.endAt.timeIntervalSince(entry.startAt)
        undoToast = UndoToastInfo(
            entryId: entry.id,
            projectName: entry.projectNameSnapshot,
            duration: duration
        )
        undoToastTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { cancelUndoToast() }
            }
        }
    }

    private func cancelUndoToast() {
        undoToast = nil
        undoToastTask?.cancel()
        undoToastTask = nil
    }

    private func performUndo() {
        guard let toast = undoToast else { return }
        do {
            try TimeCursorService(modelContext: modelContext).undoLastEntry(expectedId: toast.entryId)
            cancelUndoToast()
            now = Date()
        } catch {
            cancelUndoToast()
        }
    }

    private func expandStatusBar() {
        statusBarExpanded = true
        expandTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { collapseStatusBar() }
            }
        }
    }

    private func collapseStatusBar() {
        statusBarExpanded = false
        expandTask?.cancel()
        expandTask = nil
    }

    private func getOrCreateSettings() throws -> AppSettings {
        try TimeLedgerEngine(modelContext: modelContext).getOrCreateAppSettings()
    }

    private func currentCursorAt() -> Date {
        (try? TimeCursorService(modelContext: modelContext).getOrCreateCursor(now: now).cursorAt) ?? now
    }

    private func beginCameraFlow() {
        if ProcessInfo.processInfo.arguments.contains("-ui-camera-fixture") {
            showingCameraFixture = true
            return
        }

        Task {
            let result = await CameraPermissionService().prepareForCamera()
            if result == .ready {
                showingCamera = true
            } else {
                cameraAccessResult = result
            }
        }
    }

    private func handleCameraDismissal() {
        guard let capture = pendingCameraCapture else { return }
        pendingCameraCapture = nil
        Task {
            do {
                _ = try await ThoughtComposerDraftStore().addCapture(capture)
                composerFocusText = false
                showingThoughtCapture = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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

private struct UndoToastInfo {
    let entryId: UUID
    let projectName: String
    let duration: TimeInterval
}
