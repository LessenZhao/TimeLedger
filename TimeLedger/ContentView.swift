//
//  ContentView.swift
//  TimeLedger
//
//  Created by Lessen Zhao on 2026/7/8.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem {
                    Label("今天", systemImage: "clock")
                }
                .tag(0)

            ActionListView()
                .tabItem {
                    Label("事项", systemImage: "checklist")
                }
                .tag(1)

            ThoughtStreamView()
                .tabItem {
                    Label("时间线", systemImage: "clock.arrow.circlepath")
                }
                .tag(2)

            ReviewView()
                .tabItem {
                    Label("复盘", systemImage: "chart.bar.xaxis")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(4)
        }
        .task {
#if DEBUG
            try? UITestFixtureService(modelContext: modelContext).seedIfRequested()
#endif
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(previewModelContainer)
}
