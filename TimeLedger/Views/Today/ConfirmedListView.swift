import SwiftData
import SwiftUI

struct ConfirmedListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [TimeEntry]
    @Query private var allThoughts: [ThoughtNote]
    @Query private var allMediaMoments: [MediaMoment]
    @Query private var allThoughtMediaLinks: [ThoughtMediaLink]
    @Query private var allActionCompletions: [ActionCompletion]

    @State private var selectedDate = Date()
    @State private var editingEntry: TimeEntry?
    @State private var editingThought: ThoughtNote?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    shiftDay(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .font(TLTheme.statusFont)

                Spacer()

                DatePicker(
                    "",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Spacer()

                Button {
                    shiftDay(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .font(TLTheme.statusFont)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            HStack {
                Text(dayTitle)
                    .font(TLTheme.metaFont)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(DurationFormatter.compact(dayTotal))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            if dayEntries.isEmpty {
                ContentUnavailableView(
                    "这天没有已确认记录",
                    systemImage: "checkmark.circle",
                    description: Text("确认草稿后会出现在这里。")
                )
                .padding(.top, 24)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: TLTheme.listSpacing) {
                        ForEach(dayEntries) { entry in
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
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
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
    }

    private var dayTitle: String {
        DateFormatterFactory.dateTitle.string(from: selectedDate)
    }

    private var dayEntries: [TimeEntry] {
        let range = DateRangeService.naturalDayRange(for: selectedDate)
        return allEntries
            .filter { entry in
                entry.status == TimeEntryStatus.confirmed.rawValue
                && entry.startAt < range.upperBound
                && entry.endAt > range.lowerBound
            }
            .sorted { $0.startAt < $1.startAt } // 旧 → 新
    }

    private var dayTotal: TimeInterval {
        let range = DateRangeService.naturalDayRange(for: selectedDate)
        return dayEntries.reduce(0) { total, entry in
            total + DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                rangeStart: range.lowerBound,
                rangeEnd: range.upperBound
            )
        }
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

    private func shiftDay(_ value: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: value, to: selectedDate) {
            selectedDate = next
        }
    }
}
