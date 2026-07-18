//
//  ContentView.swift
//  TimeLedger
//
//  Created by Lessen Zhao on 2026/7/8.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem {
                    Label("今天", systemImage: "clock")
                }
                .tag(0)

            ThoughtStreamView()
                .tabItem {
                    Label("思考", systemImage: "lightbulb")
                }
                .tag(1)

            ReviewView()
                .tabItem {
                    Label("复盘", systemImage: "chart.bar.xaxis")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(3)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(previewModelContainer)
}
