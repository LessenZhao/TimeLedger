import SwiftData
import SwiftUI

struct WeeklyReviewView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedDate = Date()
    @State private var includeDraft = false

    var body: some View {
        VStack(spacing: 0) {
            datePickerBar
            ScrollView {
                LazyVStack(spacing: 16) {
                    totalCard
                    dailyBreakdownSection
                    projectSection
                }
                .padding(16)
            }
        }
        .navigationTitle("每周复盘")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var datePickerBar: some View {
        HStack {
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
            Spacer()
            Toggle("含草稿", isOn: $includeDraft)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var totalCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(weekRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DurationFormatter.compact(totalDuration))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
    }

    private var dailyBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("每日明细")
                .font(.headline)
            if dailyDurations.isEmpty {
                Text("无数据")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dailyDurations, id: \.0) { dateStr, duration in
                    HStack {
                        Text(dateStr)
                            .font(.subheadline)
                        Spacer()
                        Text(DurationFormatter.compact(duration))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("项目汇总")
                .font(.headline)
            if projectSummary.isEmpty {
                Text("无数据")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(projectSummary.sorted(by: { $0.value > $1.value }), id: \.key) { name, duration in
                    HStack {
                        Text(name)
                            .font(.subheadline)
                        Spacer()
                        Text(DurationFormatter.compact(duration))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
    }

    private var weekRangeText: String {
        let range = DateRangeService.weekRange(for: selectedDate)
        return "\(DateFormatterFactory.dateTitle.string(from: range.lowerBound)) - \(DateFormatterFactory.dateTitle.string(from: range.upperBound.addingTimeInterval(-1)))"
    }

    private var totalDuration: TimeInterval {
        dailyDurations.reduce(0) { $0 + $1.1 }
    }

    private var dailyDurations: [(String, TimeInterval)] {
        let range = DateRangeService.weekRange(for: selectedDate)
        var result: [(String, TimeInterval)] = []
        var current = range.lowerBound
        let calendar = Calendar.current

        while current < range.upperBound {
            let duration = (try? TimeSummaryService(modelContext: modelContext).totalDurationForDate(current, includeDraft: includeDraft)) ?? 0
            let dateStr = DateFormatterFactory.dateTitle.string(from: current)
            result.append((dateStr, duration))
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }

        return result
    }

    private var projectSummary: [String: TimeInterval] {
        let range = DateRangeService.weekRange(for: selectedDate)
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { entry in
                entry.startAt < range.upperBound && entry.endAt > range.lowerBound
            },
            sortBy: [SortDescriptor(\.startAt)]
        )

        let entries = ((try? modelContext.fetch(descriptor)) ?? []).filter { entry in
            includeDraft || entry.status == TimeEntryStatus.confirmed.rawValue
        }

        return entries.reduce(into: [String: TimeInterval]()) { result, entry in
            let overlap = DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                rangeStart: range.lowerBound,
                rangeEnd: range.upperBound
            )
            result[entry.projectNameSnapshot, default: 0] += overlap
        }
    }
}
