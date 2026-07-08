import SwiftUI
import SwiftData

struct ThoughtDayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allThoughts: [ThoughtNote]

    let date: Date

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if thoughts.isEmpty {
                    ContentUnavailableView("今天还没有思考", systemImage: "lightbulb", description: Text("点击左上角灯泡按钮记录想法。"))
                        .padding(.top, 40)
                } else {
                    ForEach(thoughts) { thought in
                        ThoughtCardView(thought: thought, date: date)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .navigationTitle("今日思考")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var thoughts: [ThoughtNote] {
        let calendar = Calendar.current
        let dayRange = DateRangeService.naturalDayRange(for: date, calendar: calendar)
        return allThoughts
            .filter { $0.capturedAt >= dayRange.lowerBound && $0.capturedAt < dayRange.upperBound }
            .sorted { $0.capturedAt < $1.capturedAt }
    }
}

#Preview {
    NavigationStack {
        ThoughtDayView(date: Date())
    }
    .modelContainer(previewModelContainer)
}
