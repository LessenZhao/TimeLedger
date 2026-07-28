import AppKit
import SwiftUI

/// Fixed shell geometry for the single top bar + collapsible module sidebar.
enum HubShellMetrics {
    /// One shared top bar (window leading + module chrome).
    static let topBarHeight: CGFloat = 40
    /// Expanded app-module sidebar width.
    static let sidebarWidth: CGFloat = 208
    /// Leading cluster when sidebar is collapsed: traffic-light safe area + toggle.
    static let collapsedLeadingWidth: CGFloat = 96
    /// Horizontal clearance so controls clear the traffic lights under fullSizeContentView.
    static let trafficLightsPadding: CGFloat = 72
}

/// Module-owned controls installed into the shell's single top bar (right of the sidebar seam).
@MainActor
final class HubShellChrome: ObservableObject {
    @Published private(set) var content: AnyView = AnyView(EmptyView())

    func install<V: View>(@ViewBuilder _ view: () -> V) {
        content = AnyView(
            view()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        )
    }

    func clear() {
        content = AnyView(EmptyView())
    }
}

/// Keeps shell chrome in sync with a module's controls without stacking a second title row.
struct HubChromeInstaller<Chrome: View>: View {
    @EnvironmentObject private var shellChrome: HubShellChrome
    /// Cheap equatable token; republish when module chrome inputs change.
    let dependency: String
    @ViewBuilder var chrome: () -> Chrome

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear { shellChrome.install(chrome) }
            .onChange(of: dependency) { _, _ in
                shellChrome.install(chrome)
            }
            .onDisappear {
                shellChrome.clear()
            }
    }
}
