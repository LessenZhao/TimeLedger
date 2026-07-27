import AppKit
import EvolutionHubCore
import SwiftUI

@main
struct EvolutionHubApp: App {
    @AppStorage("chatgptArchiveRoot") private var storedChatGPTArchiveRoot = ""
    @StateObject private var hubStore = HubStore()
    @StateObject private var workEvolutionStore = WorkEvolutionHubStore()
    @StateObject private var chatConversationStore = ChatConversationHubStore()
    @NSApplicationDelegateAdaptor(HubAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("TimeLedger") {
            RootView()
                .environmentObject(hubStore)
                .environmentObject(workEvolutionStore)
                .environmentObject(chatConversationStore)
                .frame(minWidth: 1000, minHeight: 680)
                .task {
                    synchronizeChatGPTArchiveRoot()
                    await workEvolutionStore.refresh()
                    chatConversationStore.refresh(archiveRootPath: hubStore.settings.chatgptArchiveRoot)
                }
                .onChange(of: hubStore.settings.chatgptArchiveRoot) { _, path in
                    storedChatGPTArchiveRoot = path
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await workEvolutionStore.refresh()
                        chatConversationStore.refresh(archiveRootPath: hubStore.settings.chatgptArchiveRoot)
                    }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("同步") {
                Button("同步今日上下文（进化）") {
                    NotificationCenter.default.post(name: .hubSyncToday, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }

    private func synchronizeChatGPTArchiveRoot() {
        guard hubStore.settings.chatgptArchiveRoot != storedChatGPTArchiveRoot else { return }
        hubStore.settings.chatgptArchiveRoot = storedChatGPTArchiveRoot
    }
}

final class HubAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

extension Notification.Name {
    static let hubSyncToday = Notification.Name("hubSyncToday")
}
