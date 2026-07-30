import SwiftData
import SwiftUI

struct MediaManualLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let moment: MediaMoment
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if recentEntries.isEmpty {
                    ContentUnavailableView("没有可选的时间记录", systemImage: "clock")
                } else {
                    ForEach(recentEntries) { entry in
                        Button {
                            link(to: entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.projectNameSnapshot)
                                    .font(.body.weight(.medium))
                                Text("\(DateFormatterFactory.dateTime.string(from: entry.startAt)) - \(DateFormatterFactory.dateTime.string(from: entry.endAt))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("选择时间段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
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
    }

    private var recentEntries: [TimeEntry] {
        let calendar = Calendar.current
        let threeDaysAgo = calendar.date(
            byAdding: .day,
            value: -3,
            to: calendar.startOfDay(for: moment.capturedAt)
        )!
        let descriptor = FetchDescriptor<TimeEntry>(
            sortBy: [SortDescriptor(\.startAt, order: .reverse)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).filter {
            $0.endAt > threeDaysAgo
        }
    }

    private func link(to entry: TimeEntry) {
        do {
            try MediaLinkingService(modelContext: modelContext).manuallyLink(moment, to: entry)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
