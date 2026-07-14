import Foundation
import EvolutionCore

@MainActor
public final class TodayContextSyncService {
    public init() {}

    public func syncToday(store: HubStore) async -> TodaySyncResult {
        var result = TodaySyncResult()
        store.isSyncing = true
        defer { store.isSyncing = false }

        let window = store.dayWindow
        result.timeEntryCount = store.entriesForSelectedDay.count
        result.thoughtCount = store.thoughtsForSelectedDay.count

        // Ensure vault
        let vault = RawVaultLayout(rootURL: URL(fileURLWithPath: store.settings.rawVaultPath, isDirectory: true))
        do {
            try vault.ensureDirectories()
        } catch {
            result.failures.append("创建 Raw Vault 失败：\(error.localizedDescription)")
        }

        // Codex
        if !store.settings.agentSessionArchivePath.isEmpty {
            do {
                let client = SessionCollectorClient(archiveRepoPath: store.settings.agentSessionArchivePath)
                let codexRoot = vault.rawSourceURL(.codex).path
                let r = try client.run(source: .codex, startAt: window.start, endAt: window.end, outputRoot: codexRoot)
                if r.status == .failed {
                    result.failures.append("Codex：\((r.errors.first ?? "失败"))")
                } else {
                    let pkg = try CodexClaudeAdapter.normalize(
                        source: .codex,
                        outputRoot: URL(fileURLWithPath: codexRoot),
                        dayWindow: window
                    )
                    store.mergeNormalized(pkg)
                    result.codexThreads = pkg.threads.count
                }
            } catch {
                result.failures.append("Codex：\(error.localizedDescription)")
            }

            // Claude
            do {
                let client = SessionCollectorClient(archiveRepoPath: store.settings.agentSessionArchivePath)
                let claudeRoot = vault.rawSourceURL(.claude).path
                let r = try client.run(source: .claude, startAt: window.start, endAt: window.end, outputRoot: claudeRoot)
                if r.status == .failed {
                    result.failures.append("Claude：\((r.errors.first ?? "失败"))")
                } else {
                    let pkg = try CodexClaudeAdapter.normalize(
                        source: .claude,
                        outputRoot: URL(fileURLWithPath: claudeRoot),
                        dayWindow: window
                    )
                    store.mergeNormalized(pkg)
                    result.claudeThreads = pkg.threads.count
                }
            } catch {
                result.failures.append("Claude：\(error.localizedDescription)")
            }
        } else {
            result.warnings.append("未配置 agent-session-archive 路径，跳过 Codex/Claude")
        }

        // ChatGPT
        let chatgptRoot = vault.rawSourceURL(.chatgpt).path
        if !store.settings.chatgptArchiveRoot.isEmpty || FileManager.default.fileExists(atPath: chatgptRoot) {
            let archive = store.settings.chatgptArchiveRoot.isEmpty ? chatgptRoot : store.settings.chatgptArchiveRoot
            let client = ChatGPTCompanionClient()
            let requestId = UUID().uuidString
            let started = Date()
            do {
                let healthy = try await client.health()
                if healthy {
                    _ = try await client.createPEEJob(
                        archiveRoot: archive,
                        baselineDate: HubStore.dayKey(for: store.selectedDay, calendar: store.calendar),
                        requestId: requestId
                    )
                    if let job = try await client.currentJob() {
                        let mapped = client.mapToCollectorResult(job: job, requestId: requestId, startedAt: started)
                        if mapped.isNonBlockingWait {
                            result.chatgptWaiting = true
                            store.settings.companionStatus = "等待浏览器扩展"
                            result.warnings.append(contentsOf: mapped.warnings)
                        } else if mapped.status == .succeeded || mapped.status == .partial {
                            store.settings.companionStatus = "已连接"
                        }
                    }
                } else {
                    result.chatgptWaiting = true
                    store.settings.companionStatus = "companion 不可用"
                    result.warnings.append("ChatGPT 同步等待中：请启动 companion 并打开已登录 ChatGPT 的浏览器。")
                }
            } catch {
                result.chatgptWaiting = true
                result.warnings.append("ChatGPT：\(error.localizedDescription)")
            }

            // Always try normalize existing archive (even if waiting)
            if FileManager.default.fileExists(atPath: (archive as NSString).appendingPathComponent("_archive-index.json")) {
                do {
                    let pkg = try ChatGPTAdapter.normalize(
                        archiveRoot: URL(fileURLWithPath: archive),
                        dayWindow: window
                    )
                    store.mergeNormalized(pkg)
                    result.chatgptThreads = pkg.threads.count
                } catch {
                    result.warnings.append("ChatGPT 标准化：\(error.localizedDescription)")
                }
            }
        }

        // Linking
        store.runAutoLinking()
        result.autoLinks = store.evidenceLinks.filter { $0.userState == .confirmed && $0.method != .manual }.count
        result.suggestedLinks = store.evidenceLinks.filter { $0.userState == .suggested }.count
        result.inboxCount = store.inboxEvents.count

        // Git evidence (optional local repo = TimeLedger if path known)
        var git: [GitEvidenceSummary] = []
        let repoGuess = (store.settings.agentSessionArchivePath as NSString).deletingLastPathComponent
        let tl = (repoGuess as NSString).appendingPathComponent("TimeLedger")
        if FileManager.default.fileExists(atPath: (tl as NSString).appendingPathComponent(".git")) {
            git = (try? GitEvidenceAdapter(repoPath: tl).recentCommits(since: window.start)) ?? []
            store.gitEvidence = git
        }

        // Review
        let draft = DeterministicReviewBuilder.build(package: store.makeDailyPackage())
        store.applyReviewDraft(draft)
        result.reviewMarkdown = draft.deterministicMarkdown

        // Export next adjustment envelope for phone (file recovery path)
        store.writeNextAdjustmentExport(vault: vault)

        store.lastSyncResult = result
        store.lastMessage = result.summaryCard
        return result
    }
}
