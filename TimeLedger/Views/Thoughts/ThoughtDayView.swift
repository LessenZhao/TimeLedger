import SwiftData
import SwiftUI

struct ThoughtDayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allJournals: [JournalEntry]
    @Query private var documents: [ContentDocument]
    @Query private var journalLinks: [JournalTimeLink]
    @Query private var entries: [TimeEntry]

    let date: Date

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if journals.isEmpty {
                    ContentUnavailableView(
                        "今天还没有随记",
                        systemImage: "lightbulb",
                        description: Text("点击右上角灯泡记录想法。")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(journals) { journal in
                        ThoughtCardView(
                            journal: journal,
                            body: body(for: journal),
                            linkedEntry: linkedEntry(for: journal)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .navigationTitle("今日随记")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var journals: [JournalEntry] {
        let calendar = Calendar.current
        let dayRange = DateRangeService.naturalDayRange(for: date, calendar: calendar)
        return allJournals
            .filter { $0.capturedAt >= dayRange.lowerBound && $0.capturedAt < dayRange.upperBound }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private var entryById: [UUID: TimeEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    private func linkedEntry(for journal: JournalEntry) -> TimeEntry? {
        guard let id = journalLinks.first(where: { $0.journalEntryID == journal.id })?.timeEntryID else {
            return nil
        }
        return entryById[id]
    }

    private func body(for journal: JournalEntry) -> String {
        documents.first {
            $0.ownerID == journal.id && $0.ownerKindEnum == .journalEntry
        }?.body ?? ""
    }
}

#Preview {
    NavigationStack {
        ThoughtDayView(date: Date())
    }
    .modelContainer(previewModelContainer)
}
