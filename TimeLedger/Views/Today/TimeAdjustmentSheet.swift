import SwiftData
import SwiftUI

struct TimeAdjustmentSheet: View {
    let project: Project
    let cursorAt: Date
    let defaultEndAt: Date
    let saveAction: (Date, Date, String) throws -> TimeEntry
    let skipAction: (Date) throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var startAt: Date
    @State private var endAt: Date
    @State private var isSkipping = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingSkipConfirmation = false
    @State private var contentSession: ContentEditorSession?

    private let initialNote: String
    private let timeRangeDraft: RichCardContentTimeEntryDraft
    private let draftStore: ThoughtComposerDraftStore

    init(
        project: Project,
        cursorAt: Date,
        defaultEndAt: Date,
        note: String = "",
        saveAction: @escaping (Date, Date, String) throws -> TimeEntry,
        skipAction: @escaping (Date) throws -> Void
    ) {
        self.project = project
        self.cursorAt = cursorAt
        self.defaultEndAt = defaultEndAt
        self.saveAction = saveAction
        self.skipAction = skipAction
        self.draftStore = ComposerDraftStoreFactory.newTimeEntry(projectID: project.id)
        let cappedEnd = min(defaultEndAt, Date())
        let initialStart = min(cursorAt, cappedEnd)
        let initialEnd = max(cappedEnd, initialStart.addingTimeInterval(60))
        _startAt = State(initialValue: initialStart)
        _endAt = State(initialValue: initialEnd)
        self.initialNote = note
        self.timeRangeDraft = RichCardContentTimeEntryDraft(
            startAt: initialStart,
            endAt: initialEnd
        )
    }

    private var nowBound: Date { Date() }

    private var pickerComponents: DatePickerComponents {
        Calendar.current.isDate(startAt, inSameDayAs: endAt)
            ? [.hourAndMinute]
            : [.date, .hourAndMinute]
    }

    private var durationText: String {
        let totalMinutes = max(0, Int(endAt.timeIntervalSince(startAt) / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            if hours > 0 { return "\(days)天\(hours)小时" }
            return "\(days)天"
        }
        if hours > 0 {
            if minutes > 0 { return "\(hours)小时\(minutes)分钟" }
            return "\(hours)小时"
        }
        return "\(max(1, minutes))分钟"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    timeRange
                    noteEditor

                    Button("不记录这段时间", role: .destructive) {
                        showingSkipConfirmation = true
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isSkipping)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(TLTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("记录时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        cancel()
                    }
                    .accessibilityIdentifier("timeEntry.create.cancel")
                    .disabled(isSaving || isSkipping)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .accessibilityIdentifier("timeEntry.create.save")
                    .disabled(isSaving || isSkipping || contentSession?.hasContent != true)
                }
            }
            .onChange(of: startAt) { _, newStart in
                if endAt <= newStart {
                    endAt = min(newStart.addingTimeInterval(60), nowBound)
                }
                if endAt > nowBound {
                    endAt = nowBound
                }
                timeRangeDraft.startAt = newStart
            }
            .onChange(of: endAt) { _, newEnd in
                if newEnd > nowBound {
                    endAt = nowBound
                }
                timeRangeDraft.endAt = newEnd
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                "不记录这段时间？",
                isPresented: $showingSkipConfirmation,
                titleVisibility: .visible
            ) {
                Button("不记录并丢弃本次内容", role: .destructive) {
                    performSkip(discardDraft: true)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会丢弃这次尚未保存的文字和媒体工作副本。")
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(project.name)
                .font(.headline)
            Spacer()
            Text(durationText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.top, 8)
    }

    private var timeRange: some View {
        HStack(spacing: 8) {
            DatePicker(
                "开始",
                selection: $startAt,
                in: cursorAt...nowBound,
                displayedComponents: pickerComponents
            )
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            DatePicker(
                "结束",
                selection: $endAt,
                in: startAt...nowBound,
                displayedComponents: pickerComponents
            )
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(TLTheme.cardBackground, in: RoundedRectangle(cornerRadius: TLTheme.cardRadius))
    }

    private var noteEditor: some View {
        RichCardContentView(
            target: .newTimeEntry(
                project: project,
                timeRange: timeRangeDraft,
                initialText: initialNote,
                save: saveNewEntry
            ),
            mode: .create,
            onSessionReady: { session in
                contentSession = session
            }
        )
    }

    private func saveNewEntry(
        startAt: Date,
        endAt: Date,
        note: String
    ) throws -> TimeEntry {
        let now = Date()
        guard endAt > startAt else {
            throw ValidationError.invalidTimeRange
        }
        guard startAt >= cursorAt else {
            throw TimeCursorError.startBeforeCursor
        }
        guard endAt <= now else {
            throw TimeCursorError.endAfterNow
        }
        return try saveAction(startAt, endAt, note)
    }

    private func performSkip(discardDraft: Bool = false) {
        guard !isSkipping else { return }
        isSkipping = true
        Task {
            do {
                if discardDraft {
                    try await draftStore.discard()
                }
                let skipTo = min(max(endAt, cursorAt.addingTimeInterval(60)), nowBound)
                try skipAction(skipTo)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSkipping = false
            }
        }
    }

    private func cancel() {
        Task {
            do {
                try await contentSession?.cancel()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        guard !isSaving, let contentSession else { return }
        isSaving = true
        Task {
            do {
                try await contentSession.save()
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    let project = Project(name: "写材料", categoryName: "工作")
    TimeAdjustmentSheet(
        project: project,
        cursorAt: Date(timeIntervalSinceNow: -1_800),
        defaultEndAt: Date(),
        saveAction: { startAt, endAt, note in
            TimeEntry(
                projectId: project.id,
                projectNameSnapshot: project.name,
                categoryNameSnapshot: project.categoryName,
                startAt: startAt,
                endAt: endAt,
                note: note
            )
        },
        skipAction: { _ in }
    )
    .modelContainer(previewModelContainer)
}
