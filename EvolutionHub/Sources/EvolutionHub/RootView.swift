import AppKit
import EvolutionCore
import EvolutionHubCore
import SwiftUI
import UniformTypeIdentifiers

/// Mac TimeLedger shell: mirror bookkeeping + Evolution modules.
///
/// Single-row chrome contract:
/// - one fixed top bar for the whole window
/// - left segment = window controls (traffic-light clearance + sidebar toggle)
/// - right segment = module-injected chrome (tabs / filters / actions)
/// - app sidebar width animates 0...208 under the left segment; never inserts a second top bar
struct RootView: View {
    @EnvironmentObject private var hubStore: HubStore
    @StateObject private var mirror = MirrorSessionController()
    @StateObject private var shellChrome = HubShellChrome()
    @State private var section: MacSection = .workEvolution
    @State private var showsSidebar = true

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)
                    .clipped()
                    .allowsHitTesting(showsSidebar)

                if showsSidebar {
                    Divider()
                }

                workspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(mirror)
        .environmentObject(shellChrome)
        .background(WindowChromeConfigurator())
        .animation(.easeInOut(duration: 0.15), value: showsSidebar)
        .onChange(of: section) { _, _ in
            // Drop previous module chrome immediately on section switch.
            shellChrome.clear()
        }
    }

    // MARK: - Single top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            topBarWindowLeading
                .frame(width: topBarLeadingWidth, alignment: .leading)

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
                .padding(.vertical, 8)

            shellChrome.content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
        }
        .frame(height: HubShellMetrics.topBarHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Traffic lights clearance + sidebar toggle. Width tracks the sidebar seam.
    private var topBarWindowLeading: some View {
        HStack(spacing: 8) {
            Button {
                showsSidebar.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20, height: 18)
            }
            .buttonStyle(.plain)
            .help(showsSidebar ? "隐藏侧边栏" : "显示侧边栏")
            .keyboardShortcut("s", modifiers: [.command, .control])

            if showsSidebar {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("TimeLedger")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, HubShellMetrics.trafficLightsPadding)
        .padding(.trailing, 10)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var topBarLeadingWidth: CGFloat {
        showsSidebar ? HubShellMetrics.sidebarWidth : HubShellMetrics.collapsedLeadingWidth
    }

    private var sidebarWidth: CGFloat {
        showsSidebar ? HubShellMetrics.sidebarWidth : 0
    }

    // MARK: - Sidebar / workspace

    private var sidebar: some View {
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
                Label("湖南省直遴选备考库", systemImage: "bubble.left.and.bubble.right")
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
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var workspace: some View {
        detailBody
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
    }

    private var connectionLabel: String {
        mirror.canBookkeep ? "已连接" : "连接 iPhone"
    }

    @ViewBuilder
    private var detailBody: some View {
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

/// Ensure native title label/toolbar cannot reappear above the workspace.
private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView) }
    }

    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }
}

private enum MacSection: Hashable {
    case connection, today, thoughts, reviewStats, workEvolution, chatConversations, context, evidenceReview, settings
}
