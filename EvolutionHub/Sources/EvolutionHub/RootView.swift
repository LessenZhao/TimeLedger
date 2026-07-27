import AppKit
import EvolutionCore
import EvolutionHubCore
import SwiftUI
import UniformTypeIdentifiers

/// Mac TimeLedger shell: mirror bookkeeping + Evolution modules.
struct RootView: View {
    @EnvironmentObject private var hubStore: HubStore
    @StateObject private var mirror = MirrorSessionController()
    @State private var section: MacSection = .workEvolution

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("账本（镜像）") {
                    Label(connectionLabel, systemImage: mirror.canBookkeep ? "link" : "link.badge.plus")
                        .tag(MacSection.connection)
                    Label("今天", systemImage: "sun.max")
                        .tag(MacSection.today)
                    Label("思考", systemImage: "lightbulb")
                        .tag(MacSection.thoughts)
                    Label("复盘", systemImage: "chart.bar")
                        .tag(MacSection.reviewStats)
                }
                Section("进化（Mac）") {
                    Label("工作沉淀", systemImage: "point.3.connected.trianglepath.dotted")
                        .tag(MacSection.workEvolution)
                    Label("ChatGPT 对话", systemImage: "bubble.left.and.bubble.right")
                        .tag(MacSection.chatConversations)
                    Label("上下文", systemImage: "tray")
                        .tag(MacSection.context)
                    Label("证据复盘", systemImage: "text.book.closed")
                        .tag(MacSection.evidenceReview)
                }
                Section {
                    Label("设置", systemImage: "gearshape")
                        .tag(MacSection.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 320)
            .navigationTitle("TimeLedger")
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(mirror)
        .onChange(of: section) { _, new in
            if !mirror.canBookkeep && (new == .today || new == .thoughts) {
                // allow viewing gate inside pages
            }
        }
    }

    private var connectionLabel: String {
        mirror.canBookkeep ? "已连接" : "连接 iPhone"
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .connection:
            ConnectionPane()
        case .today:
            TodayMirrorPane()
        case .thoughts:
            ThoughtsMirrorPane()
        case .reviewStats:
            ReviewStatsPane()
        case .workEvolution:
            WorkEvolutionView()
        case .chatConversations:
            ChatConversationView()
                .environmentObject(hubStore)
        case .context:
            InboxView()
                .environmentObject(hubStore)
        case .evidenceReview:
            DailyReviewHubView()
                .environmentObject(hubStore)
        case .settings:
            SettingsCombinedPane()
                .environmentObject(hubStore)
        }
    }
}

private enum MacSection: Hashable {
    case connection, today, thoughts, reviewStats, workEvolution, chatConversations, context, evidenceReview, settings
}
