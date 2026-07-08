import SwiftData
import SwiftUI

struct TimeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [TimeEntry]
    @Query private var allThoughts: [ThoughtNote]
    @State private var errorMessage: String?

    let date: Date
    let now: Date
    let unclassifiedDuration: TimeInterval

    init(date: Date, now: Date, unclassifiedDuration: TimeInterval) {
        self.date = date
        self.now = now
        self.unclassifiedDuration = unclassifiedDuration
        let range = DateRangeService.naturalDayRange(for: date)
        _allEntries = Query(
            filter: #Predicate<TimeEntry> { entry in
                entry.startAt < range.upperBound && entry.endAt > range.lowerBound
            },
            sort: \TimeEntry.startAt
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if entries.isEmpty {
                        ContentUnavailableView("今天还没有记录", systemImage: "clock", description: Text("从待办页快速记录一段时间。"))
                            .padding(.top, 40)
                    } else {
                        ForEach(entries) { entry in
                            NavigationLink {
                                TimeEntryEditView(entry: entry)
                            } label: {
                                entryRow(entry, thoughtCount: thoughtCount(for: entry))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 16)
            }

            Divider()
            statusBar
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("确认转换", action: confirmDrafts)
            }
        }
        .alert("确认失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var entries: [TimeEntry] {
        allEntries
    }

    private var totalDuration: TimeInterval {
        let range = DateRangeService.naturalDayRange(for: date)
        return allEntries.reduce(0) { total, entry in
            total + DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                rangeStart: range.lowerBound,
                rangeEnd: range.upperBound
            )
        }
    }

    private var remainingToday: TimeInterval {
        let endOfDay = DateRangeService.endOfNaturalDay(for: now)
        return max(0, endOfDay.timeIntervalSince(now))
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            statusItem("未记录", DurationFormatter.compact(unclassifiedDuration))
            statusItem("已记录", DurationFormatter.compact(totalDuration))
            statusItem("现在", DateFormatterFactory.timeOnly.string(from: now))
            statusItem("剩余", DurationFormatter.compact(remainingToday))
        }
        .font(.caption)
        .padding(.vertical, 10)
    }

    private func entryRow(_ entry: TimeEntry, thoughtCount: Int) -> some View {
        let isDraft = entry.status == TimeEntryStatus.draft.rawValue

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.projectNameSnapshot)
                    .font(.body.weight(.medium))
                Text("\(DateFormatterFactory.timeOnly.string(from: entry.startAt)) - \(DateFormatterFactory.timeOnly.string(from: entry.endAt))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if thoughtCount > 0 {
                    Label("思考 \(thoughtCount) 条", systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(DurationFormatter.compact(entry.durationSeconds))
                    .font(.footnote.weight(.semibold))
                Text(isDraft ? "草稿" : "已确认")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isDraft ? .secondary : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(isDraft ? Color.gray.opacity(0.12) : Color.accentColor.opacity(0.12)))
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .foregroundStyle(isDraft ? .secondary : .primary)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func thoughtCount(for entry: TimeEntry) -> Int {
        allThoughts.filter { $0.linkedEntryId == entry.id }.count
    }

    private func statusItem(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func confirmDrafts() {
        do {
            _ = try ValidationService(modelContext: modelContext).confirmDraftsForDate(date)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    TimeListView(date: Date(), now: Date(), unclassifiedDuration: 1_200)
        .modelContainer(previewModelContainer)
}
