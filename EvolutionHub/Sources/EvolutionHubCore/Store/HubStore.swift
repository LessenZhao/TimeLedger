import Combine
import Foundation
import EvolutionCore

@MainActor
public final class HubStore: ObservableObject {
    @Published public var selectedDay: Date
    @Published public var projects: [ImportedProject] = []
    @Published public var timeEntries: [ImportedTimeEntry] = []
    @Published public var thoughtNotes: [ImportedThoughtNote] = []
    @Published public var contextThreads: [ContextThread] = []
    @Published public var contextMessages: [ContextMessage] = []
    @Published public var contextEvents: [ContextEvent] = []
    @Published public var evidenceLinks: [EvidenceLink] = []
    @Published public var dailyReviewDraft: DailyReview
    @Published public var reviewDraft: ReviewDraft?
    @Published public var settings: HubSettings
    @Published public var lastMessage: String = ""
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncResult: TodaySyncResult?
    @Published public var mergeConflicts: [SyncMergeLogEntry] = []
    @Published public var gitEvidence: [GitEvidenceSummary] = []
    @Published public var cwdMappings: [String: String] = [:]
    @Published public var yesterdayAdjustmentByDate: [String: String] = [:]
    @Published public var linkingConfig: LinkingConfig = .default
    /// entityType:id → revision tracking for SyncMerger
    public var revisionState: [String: RevisionedRecord] = [:]

    public var calendar: Calendar

    public init(
        selectedDay: Date = Date(),
        settings: HubSettings = HubSettings(),
        calendar: Calendar = .current
    ) {
        self.selectedDay = selectedDay
        self.settings = settings
        self.calendar = calendar
        let dayKey = Self.dayKey(for: selectedDay, calendar: calendar)
        self.dailyReviewDraft = DailyReview(date: dayKey)
    }

    public var dayWindow: NaturalDayWindow {
        NaturalDayWindow.forDate(selectedDay, calendar: calendar)
    }

    public var entriesForSelectedDay: [ImportedTimeEntry] {
        let window = dayWindow
        return timeEntries
            .filter { $0.startAt < window.end && $0.endAt > window.start }
            .sorted { $0.startAt < $1.startAt }
    }

    public var thoughtsForSelectedDay: [ImportedThoughtNote] {
        let window = dayWindow
        return thoughtNotes
            .filter { window.contains($0.capturedAt) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    public var eventsForSelectedDay: [ContextEvent] {
        let window = dayWindow
        return contextEvents
            .filter { event in
                let end = event.endedAt ?? event.startedAt
                return event.startedAt < window.end && end > window.start
            }
            .sorted { $0.startedAt < $1.startedAt }
    }

    public var inboxEvents: [ContextEvent] {
        ManualLinkingService.unlinkedEvents(events: eventsForSelectedDay, links: evidenceLinks)
    }

    public var suggestedLinksForDay: [EvidenceLink] {
        let eventIds = Set(eventsForSelectedDay.map(\.id))
        return evidenceLinks.filter { $0.userState == .suggested && eventIds.contains($0.contextEventId) }
    }

    public func confirmedLinks(for entryId: String) -> [EvidenceLink] {
        evidenceLinks.filter { $0.timeEntryId == entryId && $0.userState == .confirmed }
    }

    public func event(id: String) -> ContextEvent? {
        contextEvents.first { $0.id == id }
    }

    public func importTimeLedgerJSON(from url: URL) throws {
        let result = try TimeLedgerJSONImporter.importFromFile(at: url)
        projects = result.projects
        timeEntries = result.entries
        thoughtNotes = result.thoughts
        settings.iPhoneSyncStatus = "已导入文件：\(url.lastPathComponent)"
        lastMessage = "已导入时间记录 \(result.entries.count) 条，思考 \(result.thoughts.count) 条"
    }

    public func importContextEventsJSON(from url: URL) throws {
        let events = try ContextEventJSONImporter.importFromFile(at: url)
        mergeContextEvents(events)
        lastMessage = "已导入上下文事件 \(events.count) 条"
    }

    public func importSyncBatch(from url: URL) throws {
        let batch = try SyncBatchImporter.importFile(at: url)
        _ = try SyncBatchImporter.applyToStore(batch: batch, store: self)
    }

    public func mergeContextEvents(_ events: [ContextEvent]) {
        var byId = Dictionary(uniqueKeysWithValues: contextEvents.map { ($0.id, $0) })
        for event in events {
            byId[event.id] = event
        }
        contextEvents = Array(byId.values).sorted { $0.startedAt < $1.startedAt }
    }

    public func mergeNormalized(_ pkg: NormalizedContextPackage) {
        var t = Dictionary(uniqueKeysWithValues: contextThreads.map { ($0.id, $0) })
        for thread in pkg.threads { t[thread.id] = thread }
        contextThreads = Array(t.values)

        var m = Dictionary(uniqueKeysWithValues: contextMessages.map { ($0.id, $0) })
        for message in pkg.messages { m[message.id] = message }
        contextMessages = Array(m.values)

        mergeContextEvents(pkg.events)

        // Auto cwd mapping hints
        for thread in pkg.threads {
            if let cwd = thread.cwd, let project = projects.first(where: { cwd.hasSuffix($0.name) || cwd.contains($0.name) }) {
                cwdMappings[cwd] = project.id
            }
        }
    }

    public func upsertTimeEntry(from p: TimeEntrySyncPayload) {
        if let idx = timeEntries.firstIndex(where: { $0.id == p.id }) {
            timeEntries[idx] = ImportedTimeEntry(
                id: p.id,
                projectId: p.projectId,
                projectNameSnapshot: p.projectNameSnapshot,
                categoryNameSnapshot: p.categoryNameSnapshot,
                startAt: p.startAt,
                endAt: p.endAt,
                note: p.note,
                status: p.status,
                createdAt: p.createdAt,
                updatedAt: p.updatedAt
            )
        } else {
            timeEntries.append(ImportedTimeEntry(
                id: p.id,
                projectId: p.projectId,
                projectNameSnapshot: p.projectNameSnapshot,
                categoryNameSnapshot: p.categoryNameSnapshot,
                startAt: p.startAt,
                endAt: p.endAt,
                note: p.note,
                status: p.status,
                createdAt: p.createdAt,
                updatedAt: p.updatedAt
            ))
        }
    }

    public func upsertThought(from p: ThoughtNoteSyncPayload) {
        let note = ImportedThoughtNote(
            id: p.id,
            body: p.body,
            capturedAt: p.capturedAt,
            anchorAt: p.anchorAt,
            linkedEntryId: p.linkedEntryId,
            linkSource: p.linkSource,
            createdAt: p.createdAt,
            updatedAt: p.updatedAt
        )
        if let idx = thoughtNotes.firstIndex(where: { $0.id == p.id }) {
            thoughtNotes[idx] = note
        } else {
            thoughtNotes.append(note)
        }
    }

    public func upsertProject(from p: ProjectSyncPayload) {
        let project = ImportedProject(id: p.id, name: p.name, categoryName: p.categoryName)
        if let idx = projects.firstIndex(where: { $0.id == p.id }) {
            projects[idx] = project
        } else {
            projects.append(project)
        }
    }

    public func manuallyLink(timeEntryId: String, contextEventId: String) throws {
        guard timeEntries.contains(where: { $0.id == timeEntryId }) else {
            throw ManualLinkError.entryNotFound
        }
        guard contextEvents.contains(where: { $0.id == contextEventId }) else {
            throw ManualLinkError.eventNotFound
        }
        let link = try ManualLinkingService.link(
            timeEntryId: timeEntryId,
            contextEventId: contextEventId,
            existing: evidenceLinks
        )
        evidenceLinks.removeAll {
            $0.timeEntryId == timeEntryId && $0.contextEventId == contextEventId
        }
        evidenceLinks.append(link)
        lastMessage = "已手动关联上下文到时间记录"
    }

    public func confirmSuggested(_ link: EvidenceLink) {
        if let idx = evidenceLinks.firstIndex(where: { $0.id == link.id }) {
            evidenceLinks[idx].userState = .confirmed
            evidenceLinks[idx].method = .manual
            evidenceLinks[idx].updatedAt = Date()
        }
    }

    public func rejectLink(timeEntryId: String, contextEventId: String) {
        ManualLinkingService.reject(
            timeEntryId: timeEntryId,
            contextEventId: contextEventId,
            existing: &evidenceLinks
        )
        lastMessage = "已拒绝该关联"
    }

    public func runAutoLinking() {
        let entries = entriesForSelectedDay.map {
            TimelineEntryLike(
                id: $0.id,
                projectId: $0.projectId,
                projectName: $0.projectNameSnapshot,
                startAt: $0.startAt,
                endAt: $0.endAt
            )
        }
        let result = LinkingEngine.suggest(
            entries: entries,
            events: eventsForSelectedDay,
            existingLinks: evidenceLinks,
            cwdMappings: cwdMappings,
            config: linkingConfig
        )
        // Keep user-locked
        let locked = evidenceLinks.filter(\.isUserLocked)
        var next = locked
        for link in result.auto + result.suggested {
            if locked.contains(where: { $0.contextEventId == link.contextEventId }) { continue }
            next.removeAll { $0.contextEventId == link.contextEventId && !$0.isUserLocked }
            next.append(link)
        }
        // preserve rejected
        let rejected = evidenceLinks.filter { $0.userState == .rejected }
        for r in rejected {
            if !next.contains(where: { $0.contextEventId == r.contextEventId && $0.userState == .rejected }) {
                next.append(r)
            }
        }
        evidenceLinks = next
    }

    public func makeDailyPackage() -> DailyContextPackage {
        let dateKey = Self.dayKey(for: selectedDay, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: selectedDay).map {
            yesterdayAdjustmentByDate[Self.dayKey(for: $0, calendar: calendar)]
        } ?? nil
        return DailyContextPackage(
            dateKey: dateKey,
            entries: entriesForSelectedDay.map {
                TimelineEntryLike(
                    id: $0.id,
                    projectId: $0.projectId,
                    projectName: $0.projectNameSnapshot,
                    startAt: $0.startAt,
                    endAt: $0.endAt
                )
            },
            thoughtBodies: thoughtsForSelectedDay.map(\.body),
            events: eventsForSelectedDay,
            links: evidenceLinks,
            gitEvidence: gitEvidence,
            yesterdayAdjustment: yesterday
        )
    }

    public func applyReviewDraft(_ draft: ReviewDraft) {
        reviewDraft = draft
        dailyReviewDraft.date = draft.date
        dailyReviewDraft.mainFocus = draft.mainFocus
        dailyReviewDraft.verifiedOutputs = draft.verifiedOutputs.map { "[\($0.level.rawValue)] \($0.text)" }.joined(separator: "\n")
        dailyReviewDraft.keyInsights = draft.keyInsights.map { "[\($0.level.rawValue)] \($0.text)" }.joined(separator: "\n")
        dailyReviewDraft.mainDeviation = draft.mainDeviation
        if dailyReviewDraft.nextAdjustment.isEmpty {
            dailyReviewDraft.nextAdjustment = draft.nextAdjustment
        }
        dailyReviewDraft.evidenceIds = draft.evidenceIds
        dailyReviewDraft.aiDraft = draft.aiDraft
    }

    public func confirmReview() {
        dailyReviewDraft.status = .confirmed
        dailyReviewDraft.confirmedAt = Date()
        dailyReviewDraft.updatedAt = Date()
        yesterdayAdjustmentByDate[dailyReviewDraft.date] = dailyReviewDraft.nextAdjustment
        lastMessage = "已确认今日复盘与明日调整"
    }

    public func writeNextAdjustmentExport(vault: RawVaultLayout) {
        let payload = DailyReviewSyncPayload(
            id: dailyReviewDraft.id,
            date: dailyReviewDraft.date,
            mainFocus: dailyReviewDraft.mainFocus,
            verifiedOutputs: dailyReviewDraft.verifiedOutputs,
            mainDeviation: dailyReviewDraft.mainDeviation,
            nextAdjustment: dailyReviewDraft.nextAdjustment,
            status: dailyReviewDraft.status.rawValue,
            confirmedAt: dailyReviewDraft.confirmedAt,
            updatedAt: Date()
        )
        guard let env = try? AnySyncEnvelope(
            deviceId: "mac-hub",
            entityType: .dailyReview,
            entityId: dailyReviewDraft.id,
            revision: 1,
            updatedAt: Date(),
            payload: payload
        ) else { return }
        let batch = SyncBatchFile(deviceId: "mac-hub", envelopes: [env])
        let url = vault.syncURL.appendingPathComponent("next-adjustment-\(dailyReviewDraft.date).json")
        if let data = try? ISO8601Codec.encoder.encode(batch) {
            try? FileManager.default.createDirectory(at: vault.syncURL, withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }

    public func refreshReviewDateKey() {
        dailyReviewDraft.date = Self.dayKey(for: selectedDay, calendar: calendar)
    }

    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
