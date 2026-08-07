import SwiftData
import SwiftUI
import UIKit

struct DraftListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<TimeEntry> { entry in
            entry.status == "draft"
        },
        sort: \TimeEntry.startAt
    ) private var drafts: [TimeEntry]
    @Query private var allThoughts: [ThoughtNote]
    @Query private var allMediaMoments: [MediaMoment]
    @Query private var allThoughtMediaLinks: [ThoughtMediaLink]
    @Query private var allActionCompletions: [ActionCompletion]

    @State private var errorMessage: String?
    @State private var deleteTarget: TimeEntry?
    @State private var editingEntry: TimeEntry?
    @State private var editingThought: ThoughtNote?

    var body: some View {
        Group {
            if drafts.isEmpty {
                ContentUnavailableView(
                    "没有草稿",
                    systemImage: "tray",
                    description: Text("从项目页归档时间后，未确认的记录会出现在这里。")
                )
                .padding(.top, 40)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(daySections, id: \.dayStart) { section in
                            Section {
                                LazyVStack(spacing: TLTheme.listSpacing) {
                                    ForEach(section.entries) { entry in
                                        DraftSwipeRow {
                                            TimeEntryExpandableCard(
                                                entry: entry,
                                                thoughts: thoughts(for: entry),
                                                mediaMoments: mediaMoments(for: entry),
                                                thoughtMediaLinks: allThoughtMediaLinks,
                                                actionTitles: actionTitles(for: entry),
                                                onEditThought: { thought in
                                                    editingThought = thought
                                                },
                                                onEdit: {
                                                    editingEntry = entry
                                                }
                                            )
                                        } onDelete: {
                                            deleteTarget = entry
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                deleteTarget = entry
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                .padding(.bottom, 8)
                            } header: {
                                Text(sectionTitle(for: section.dayStart))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 44)
                                    .padding(.vertical, 8)
                                    .background(TLTheme.pageBackground.opacity(0.95))
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
                .accessibilityIdentifier("draft.scroll")
            }
        }
        .sheet(item: $editingEntry) { entry in
            NavigationStack {
                TimeEntryEditView(entry: entry)
            }
        }
        .sheet(item: $editingThought) { thought in
            RichCardContentEditorSheet(target: .thought(thought), title: "编辑思考")
        }
        .alert("删除这条草稿？", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let entry = deleteTarget {
                    deleteDraft(entry)
                }
            }
        } message: {
            Text("若后面是草稿会向前贴紧；后面是已确认则留空档；最后一条会退回未记录光标。")
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

    private struct DaySection {
        let dayStart: Date
        let entries: [TimeEntry]
    }

    private var daySections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: drafts) { entry in
            calendar.startOfDay(for: entry.startAt)
        }
        return grouped
            .map { DaySection(dayStart: $0.key, entries: $0.value.sorted { $0.startAt < $1.startAt }) }
            .sorted { $0.dayStart < $1.dayStart }
    }

    private func sectionTitle(for dayStart: Date) -> String {
        let calendar = Calendar.current
        let weekday = weekdayLabel(for: dayStart)
        let monthDay = monthDayLabel(for: dayStart)
        if calendar.isDateInToday(dayStart) {
            return "今天 · \(monthDay) · \(weekday)"
        }
        if calendar.isDateInYesterday(dayStart) {
            return "昨天 · \(monthDay) · \(weekday)"
        }
        return "\(monthDay) · \(weekday)"
    }

    private func monthDayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func weekdayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func thoughts(for entry: TimeEntry) -> [ThoughtNote] {
        allThoughts
            .filter { $0.linkedEntryId == entry.id }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private func mediaMoments(for entry: TimeEntry) -> [MediaMoment] {
        allMediaMoments
            .filter { $0.linkedEntryId == entry.id }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private func actionTitles(for entry: TimeEntry) -> [String] {
        allActionCompletions
            .filter { $0.linkedEntryId == entry.id }
            .sorted { $0.completedAt < $1.completedAt }
            .map(\.actionTitleSnapshot)
    }

    private func deleteDraft(_ entry: TimeEntry) {
        do {
            try TimeCursorService(modelContext: modelContext).deleteDraftEntry(entry)
            deleteTarget = nil
        } catch {
            errorMessage = error.localizedDescription
            deleteTarget = nil
        }
    }
}

private struct DraftSwipeRow<Content: View>: View {
    private let actionWidth: CGFloat = 76
    private let content: Content
    private let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var settledOffset: CGFloat = 0

    init(
        @ViewBuilder content: () -> Content,
        onDelete: @escaping () -> Void
    ) {
        self.content = content()
        self.onDelete = onDelete
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                close()
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .background(Color.red)
            .accessibilityHidden(offset > -1)

            content
                .offset(x: offset)
        }
        .clipShape(RoundedRectangle(cornerRadius: TLTheme.cardRadius))
        .gesture(
            HorizontalPanGesture(
                onChanged: { translation in
                    offset = min(
                        0,
                        max(-actionWidth, settledOffset + translation)
                    )
                },
                onEnded: { translation, velocity in
                    let projectedOffset = settledOffset + translation + velocity * 0.2
                    let target = projectedOffset < -actionWidth / 2 ? -actionWidth : 0
                    withAnimation(.easeOut(duration: 0.18)) {
                        offset = target
                        settledOffset = target
                    }
                }
            )
        )
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) {
            offset = 0
            settledOffset = 0
        }
    }
}

private struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.cancelsTouchesInView = false
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .changed:
            context.coordinator.onChanged(translation)
        case .ended:
            let velocity = recognizer.velocity(in: recognizer.view).x
            context.coordinator.onEnded(translation, velocity)
        case .cancelled, .failed:
            context.coordinator.onEnded(translation, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat, CGFloat) -> Void

        init(
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping (CGFloat, CGFloat) -> Void
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let recognizer = gestureRecognizer as? UIPanGestureRecognizer else {
                return false
            }
            let velocity = recognizer.velocity(in: recognizer.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
