import SwiftData
import SwiftUI

struct ConfirmedListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [TimeEntry]
    @Query private var allThoughts: [ThoughtNote]

    @State private var selectedDate = Date()

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
                            NavigationLink {
                                TimeEntryEditView(entry: entry)
                                    .toolbar(.visible, for: .navigationBar)
                            } label: {
                                confirmedRow(entry, thoughtCount: thoughtCount(for: entry))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
            }
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

    private func confirmedRow(_ entry: TimeEntry, thoughtCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.projectNameSnapshot)
                    .font(TLTheme.projectNameFont)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(DurationFormatter.compact(entry.durationSeconds))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }

            Text(timeAndNote(entry))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if thoughtCount > 0 {
                Text("思考 \(thoughtCount)")
                    .font(TLTheme.metaFont)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, TLTheme.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TLTheme.cardRadius)
                .fill(TLTheme.cardBackground)
        )
    }

    private func timeAndNote(_ entry: TimeEntry) -> String {
        let start = DateFormatterFactory.timeOnly.string(from: entry.startAt)
        let end = DateFormatterFactory.timeOnly.string(from: entry.endAt)
        let range = "\(start) – \(end)"
        let trimmed = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return range
        }
        return "\(range) · \(trimmed)"
    }

    private func thoughtCount(for entry: TimeEntry) -> Int {
        allThoughts.filter { $0.linkedEntryId == entry.id }.count
    }

    private func shiftDay(_ value: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: value, to: selectedDate) {
            selectedDate = next
        }
    }
}
