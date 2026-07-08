import SwiftUI
import SwiftData

struct ReviewView: View {
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("复盘视图", selection: $selectedTab) {
                    Text("日").tag(0)
                    Text("周").tag(1)
                    Text("月").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch selectedTab {
                case 0:
                    DailyReviewView()
                case 1:
                    WeeklyReviewView()
                case 2:
                    MonthlyReviewView()
                default:
                    EmptyView()
                }
            }
        }
    }
}

#Preview {
    ReviewView()
        .modelContainer(previewModelContainer)
}
