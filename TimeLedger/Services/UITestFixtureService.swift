import Foundation
import SwiftData

/// DEBUG 隔离的 UI 测试种子入口：只调用 TimeLedgerEngine 写入。
struct UITestFixtureService {
    let modelContext: ModelContext

    func seedIfRequested(now: Date = Date()) throws {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing") {
            let draftRoot = ThoughtComposerDraftStore().rootURL
            if FileManager.default.fileExists(atPath: draftRoot.path) {
                try FileManager.default.removeItem(at: draftRoot)
            }
            if !arguments.contains("-ui-keep-timeline-type-mode") {
                UserDefaults.standard.removeObject(forKey: "timeline.typeMode")
            }
        }

        let kind: UITestFixtureKind?
        if arguments.contains("-ui-draft-scroll-fixture") {
            kind = .draftScroll
        } else if arguments.contains("-ui-review-fixture") {
            kind = .review
        } else if arguments.contains("-ui-media-fixture")
                    || arguments.contains("-ui-unified-content-fixture") {
            kind = .main
        } else {
            kind = nil
        }
        guard let kind else { return }
        try TimeLedgerEngine(modelContext: modelContext).seedUITestFixtures(kind: kind, now: now)
    }
}
