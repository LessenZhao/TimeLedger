import SwiftData
import SwiftUI

struct ThoughtStreamView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ThoughtNote.capturedAt, order: .reverse) private var thoughts: [ThoughtNote]
    @Query(sort: \MediaMoment.capturedAt, order: .reverse) private var mediaMoments: [MediaMoment]
    @Query private var thoughtMediaLinks: [ThoughtMediaLink]
    @Query private var entries: [TimeEntry]

    @State private var showingThoughtCapture = false
    @State private var filter = TimelineFilter.all

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("筛选", selection: $filter) {
                    ForEach(TimelineFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityIdentifier("timeline.filter")

                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        filter.emptyTitle,
                        systemImage: filter.emptyIcon,
                        description: Text(filter.emptyDescription)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                            ForEach(daySections) { section in
                                Section {
                                    LazyVStack(spacing: 10) {
                                        ForEach(section.items) { item in
                                            timelineCard(item)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                } header: {
                                    dayHeader(section.title)
                                }
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
            }
            .background(TLTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("时间线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingThoughtCapture = true
                    } label: {
                        Image(systemName: "lightbulb.fill")
                    }
                    .accessibilityLabel("快速想法")
                }
            }
            .sheet(isPresented: $showingThoughtCapture) {
                ThoughtComposerSheet()
            }
        }
    }

    private var entryById: [UUID: TimeEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    private func linkedEntry(for thought: ThoughtNote) -> TimeEntry? {
        guard let id = thought.linkedEntryId else { return nil }
        return entryById[id]
    }

    private func linkedEntry(for moment: MediaMoment) -> TimeEntry? {
        guard let id = moment.linkedEntryId else { return nil }
        return entryById[id]
    }

    @ViewBuilder
    private func timelineCard(_ item: TimelineItem) -> some View {
        switch item {
        case .thought(let thought):
            ThoughtCardView(
                thought: thought,
                linkedEntry: linkedEntry(for: thought),
                mediaMoments: mediaMoments(for: thought)
            )
        case .media(let moment):
            MediaMomentCard(
                moment: moment,
                linkedEntry: linkedEntry(for: moment)
            )
        }
    }

    private var filteredItems: [TimelineItem] {
        let thoughtItems = thoughts.map(TimelineItem.thought)
        let mediaItems = mediaMoments
            .filter { moment in
                guard filter.includes(moment.kind) else { return false }
                return filter != .all || !attachedMediaIDs.contains(moment.id)
            }
            .map(TimelineItem.media)
        let items = filter == .thoughts ? thoughtItems
            : filter == .photos || filter == .videos ? mediaItems
            : thoughtItems + mediaItems
        return items.sorted { $0.capturedAt > $1.capturedAt }
    }

    private var attachedMediaIDs: Set<UUID> {
        Set(thoughtMediaLinks.map(\.mediaMomentId))
    }

    private func mediaMoments(for thought: ThoughtNote) -> [MediaMoment] {
        (try? ThoughtMediaLinkService(modelContext: modelContext).mediaMoments(
            for: thought,
            links: thoughtMediaLinks,
            moments: mediaMoments
        )) ?? []
    }

    private var daySections: [TimelineDaySection] {
        let calendar = Calendar.current
        var buckets: [(dayStart: Date, items: [TimelineItem])] = []
        var indexByDayStart: [Date: Int] = [:]

        for item in filteredItems {
            let dayStart = calendar.startOfDay(for: item.capturedAt)
            if let index = indexByDayStart[dayStart] {
                buckets[index].items.append(item)
            } else {
                indexByDayStart[dayStart] = buckets.count
                buckets.append((dayStart, [item]))
            }
        }

        return buckets.map { bucket in
            TimelineDaySection(
                id: bucket.dayStart,
                title: dayTitle(for: bucket.dayStart, calendar: calendar),
                items: bucket.items
            )
        }
    }

    private func dayTitle(for dayStart: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(dayStart) {
            return "今天"
        }
        if calendar.isDateInYesterday(dayStart) {
            return "昨天"
        }
        return DateFormatterFactory.dateTitle.string(from: dayStart)
    }

    private func dayHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(TLTheme.pageBackground.opacity(0.95))
    }
}

private enum TimelineFilter: String, CaseIterable, Identifiable {
    case all
    case thoughts
    case photos
    case videos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .thoughts: "思考"
        case .photos: "照片"
        case .videos: "视频"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: "还没有时间点"
        case .thoughts: "还没有思考"
        case .photos: "还没有照片"
        case .videos: "还没有视频"
        }
    }

    var emptyIcon: String {
        switch self {
        case .all: "clock"
        case .thoughts: "lightbulb"
        case .photos: "photo"
        case .videos: "video"
        }
    }

    var emptyDescription: String {
        switch self {
        case .all:
            "快速想法和拍摄媒体会按时间混排在这里。"
        case .thoughts:
            "点右上角灯泡记下想法。"
        case .photos:
            "在今天页按住灯泡 0.2 秒进入系统相机拍照。"
        case .videos:
            "在今天页按住灯泡 0.2 秒进入系统相机录像。"
        }
    }

    func includes(_ kind: MediaKind) -> Bool {
        switch self {
        case .all:
            true
        case .thoughts:
            false
        case .photos:
            kind == .photo
        case .videos:
            kind == .video
        }
    }
}

private enum TimelineItem: Identifiable {
    case thought(ThoughtNote)
    case media(MediaMoment)

    var id: String {
        switch self {
        case .thought(let thought):
            "thought-\(thought.id.uuidString)"
        case .media(let moment):
            "media-\(moment.id.uuidString)"
        }
    }

    var capturedAt: Date {
        switch self {
        case .thought(let thought):
            thought.capturedAt
        case .media(let moment):
            moment.capturedAt
        }
    }
}

private struct TimelineDaySection: Identifiable {
    let id: Date
    let title: String
    let items: [TimelineItem]
}

#Preview {
    ThoughtStreamView()
        .modelContainer(previewModelContainer)
}
