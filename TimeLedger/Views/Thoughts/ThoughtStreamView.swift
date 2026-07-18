import SwiftData
import SwiftUI

struct ThoughtStreamView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ThoughtNote.capturedAt, order: .reverse) private var thoughts: [ThoughtNote]
    @Query private var entries: [TimeEntry]

    @State private var showingThoughtCapture = false

    var body: some View {
        NavigationStack {
            Group {
                if thoughts.isEmpty {
                    ContentUnavailableView(
                        "还没有思考",
                        systemImage: "lightbulb",
                        description: Text("点右上角灯泡记下想法，会以卡片形式留在这里。")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                            ForEach(daySections) { section in
                                Section {
                                    LazyVStack(spacing: 10) {
                                        ForEach(section.thoughts) { thought in
                                            ThoughtCardView(
                                                thought: thought,
                                                linkedEntry: linkedEntry(for: thought)
                                            )
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
            .navigationTitle("思考")
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
                ThoughtQuickCaptureSheet()
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

    private var daySections: [ThoughtDaySection] {
        let calendar = Calendar.current
        var buckets: [(dayStart: Date, thoughts: [ThoughtNote])] = []
        var indexByDayStart: [Date: Int] = [:]

        for thought in thoughts {
            let dayStart = calendar.startOfDay(for: thought.capturedAt)
            if let index = indexByDayStart[dayStart] {
                buckets[index].thoughts.append(thought)
            } else {
                indexByDayStart[dayStart] = buckets.count
                buckets.append((dayStart, [thought]))
            }
        }

        return buckets.map { bucket in
            ThoughtDaySection(
                id: bucket.dayStart,
                title: dayTitle(for: bucket.dayStart, calendar: calendar),
                thoughts: bucket.thoughts
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

private struct ThoughtDaySection: Identifiable {
    let id: Date
    let title: String
    let thoughts: [ThoughtNote]
}

#Preview {
    ThoughtStreamView()
        .modelContainer(previewModelContainer)
}
