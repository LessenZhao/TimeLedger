import Combine
import EvolutionCore
import Foundation

public struct ChatConversationDateRange: Sendable, Hashable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    func contains(_ date: Date) -> Bool {
        start <= date && date <= end
    }
}

public enum ChatConversationHubStoreError: Error, Sendable, Equatable {
    case archiveRootNotConfigured
    case noConversationsSelected
    case candidateNotFound(String)
    case candidateTopicNotFound(String)
    case candidateSegmentNotFound(String)
    case candidateAssetNotFound(String)
    case emptyCandidateTopicName
    case migrationRequired
    case migrationNotNeeded
    case readingNoteNotFound(String)
}

extension ChatConversationHubStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .archiveRootNotConfigured:
            return "请先在设置中配置 ChatGPT archive 根目录。"
        case .noConversationsSelected:
            return "请选择至少一个有待处理消息的会话。"
        case .candidateNotFound(let jobId):
            return "找不到待确认候选：\(jobId)。"
        case .candidateTopicNotFound(let id):
            return "找不到候选主题：\(id)。"
        case .candidateSegmentNotFound(let id):
            return "找不到候选片段：\(id)。"
        case .candidateAssetNotFound(let id):
            return "找不到候选资产：\(id)。"
        case .emptyCandidateTopicName:
            return "候选主题名称不能为空。"
        case .migrationRequired:
            return "正式账本仍是 schema v1，请先备份并升级备考库。"
        case .migrationNotNeeded:
            return "当前账本无需迁移。"
        case .readingNoteNotFound:
            return "找不到对应的阅读笔记。"
        }
    }
}

public struct ChatConversationConversationProjection: Identifiable, Sendable, Hashable {
    public var conversationId: String
    public var title: String
    public var segments: [ChatConversationSegment]
    public var assets: [ChatStudyAssetRef]

    public var id: String { conversationId }
}

public struct ChatConversationTopicProjection: Identifiable, Sendable, Hashable {
    public var topic: ChatConversationTopic
    public var segments: [ChatConversationSegment]
    public var assets: [ChatStudyAssetRef]

    public var id: String { topic.id }
}

/// Presentation store for the explicit ChatGPT processing workflow. It reads
/// archive summaries and creates immutable ledger tasks, but never applies a
/// candidate proposal automatically.
@MainActor
public final class ChatConversationHubStore: ObservableObject {
    @Published public private(set) var conversations: [ChatConversationArchiveSummary] = []
    @Published public private(set) var selectedConversationIDs: Set<String> = []
    @Published public var dateRange: ChatConversationDateRange?
    @Published public var statusFilter: Set<ChatConversationProcessingStatus>
    @Published public private(set) var lastGeneratedTask: ChatConversationProcessingTask?
    @Published public private(set) var lastError: String?
    @Published public private(set) var candidates: [ChatConversationProposal] = []
    @Published public private(set) var excludedCandidateAssetIDs: [String: Set<String>] = [:]
    @Published public private(set) var selectedCandidateJobID: String?
    @Published public private(set) var ledgerDocument: ChatConversationLedgerDocument
    @Published public private(set) var ledgerSchemaState: ChatConversationLedgerSchemaState = .missing
    @Published public private(set) var lastMigrationBackupURL: URL?
    @Published public private(set) var starredConversationIDs: Set<String> = []
    @Published public private(set) var starredTurnIDs: Set<String> = []
    @Published public private(set) var readingNotes: [ReadingNote] = []
    /// One-shot focus requested by 笔记库 jump-back.
    @Published public var pendingNotesFocusAssetID: String?
    @Published public var pendingNotesFocusConversationID: String?
    @Published public var showsOnlyStarredConversations = false

    private let ledger: ChatConversationLedger
    private let layout: EvolutionLedgerLayout
    private let proposalInbox: ChatConversationProposalInbox
    private let jobIDGenerator: @Sendable () -> String
    private var archiveRoot: URL?
    private var evidencePresentation = ChatConversationEvidencePresentation(conversations: [])

    public init(
        layout: EvolutionLedgerLayout = .defaultDocuments(),
        jobIDGenerator: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.layout = layout
        self.ledger = ChatConversationLedger(layout: layout)
        self.proposalInbox = ChatConversationProposalInbox(layout: layout)
        self.jobIDGenerator = jobIDGenerator
        self.statusFilter = Set(ChatConversationProcessingStatus.allCases)
        self.dateRange = nil
        self.lastGeneratedTask = nil
        self.lastError = nil
        self.selectedCandidateJobID = nil
        self.ledgerDocument = .empty
        let marks = Self.loadUserMarks(layout: layout)
        self.starredConversationIDs = Set(marks.starredConversationIDs)
        self.starredTurnIDs = Set(marks.starredTurnIDs)
        self.readingNotes = ReadingNotesFileStore.load(
            from: layout.chatConversationReadingNotesFileURL
        ).notes
    }

    public var visibleConversations: [ChatConversationArchiveSummary] {
        conversations.filter { conversation in
            guard statusFilter.contains(conversation.status) else { return false }
            if showsOnlyStarredConversations,
               !starredConversationIDs.contains(conversation.conversationId) {
                return false
            }
            guard let dateRange else { return true }
            guard let updatedAt = ISO8601Codec.date(from: conversation.updatedAt) else { return false }
            return dateRange.contains(updatedAt)
        }
    }

    public var visibleConversationDayGroups: [ChatConversationDayGroup] {
        ChatConversationDayGrouping.groups(
            from: visibleConversations,
            starredConversationIDs: starredConversationIDs
        )
    }

    public func isConversationStarred(_ conversationID: String) -> Bool {
        starredConversationIDs.contains(conversationID)
    }

    public func isTurnStarred(_ turnID: String) -> Bool {
        starredTurnIDs.contains(turnID)
    }

    public func toggleConversationStar(conversationID: String) {
        if starredConversationIDs.contains(conversationID) {
            starredConversationIDs.remove(conversationID)
        } else {
            starredConversationIDs.insert(conversationID)
        }
        persistUserMarks()
    }

    public func toggleTurnStar(turnID: String) {
        if starredTurnIDs.contains(turnID) {
            starredTurnIDs.remove(turnID)
        } else {
            starredTurnIDs.insert(turnID)
        }
        persistUserMarks()
    }

    public var lastGeneratedCommand: String? {
        guard let task = lastGeneratedTask,
              !candidates.contains(where: { $0.jobId == task.jobId }),
              !ledgerDocument.receipts.contains(where: {
                  $0.jobId == task.jobId && Self.isTerminal($0.status)
              }) else {
            return nil
        }
        return "$chatgpt-ledger process \(task.jobId)"
    }

    public var hasPendingCandidates: Bool {
        !candidates.isEmpty
    }

    public var selectedCandidate: ChatConversationProposal? {
        guard let selectedCandidateJobID else { return nil }
        return candidates.first(where: { $0.jobId == selectedCandidateJobID })
    }

    public var conversationProjections: [ChatConversationConversationProjection] {
        let refs = ChatStudyAssetPresentation.refs(from: ledgerDocument)
        return conversations.map { conversation in
            let segments = ledgerDocument.segments.filter { $0.conversationId == conversation.conversationId }
            return ChatConversationConversationProjection(
                conversationId: conversation.conversationId,
                title: conversation.title,
                segments: segments,
                assets: refs.filter { $0.conversationID == conversation.conversationId }
            )
        }
    }

    public var formalConversationProjections: [ChatConversationConversationProjection] {
        conversationProjections.filter { !$0.segments.isEmpty || !$0.assets.isEmpty }
    }

    public var topicProjections: [ChatConversationTopicProjection] {
        let refs = ChatStudyAssetPresentation.refs(from: ledgerDocument)
        return ledgerDocument.topics.map { topic in
            ChatConversationTopicProjection(
                topic: topic,
                segments: ledgerDocument.segments.filter { $0.topicId == topic.id },
                assets: refs.filter { $0.topicID == topic.id }
            )
        }
    }

    public var kindProjections: [ChatConversationKindProjection] {
        ChatStudyAssetPresentation.kindProjections(from: ledgerDocument)
    }

    public func refresh(archiveRoot: URL) throws {
        do {
            ledgerSchemaState = try ledger.inspectSchemaState()
            if ledgerSchemaState == .requiresV1Migration {
                self.archiveRoot = archiveRoot
                conversations = []
                selectedConversationIDs = []
                evidencePresentation = ChatConversationEvidencePresentation(conversations: [])
                candidates = []
                selectedCandidateJobID = nil
                lastError = ChatConversationHubStoreError.migrationRequired.localizedDescription
                return
            }
            let summaries = try ledger.readArchiveSummaries(archiveRoot: archiveRoot)
            self.archiveRoot = archiveRoot
            conversations = summaries
            evidencePresentation = ChatConversationEvidencePresentation(conversations: summaries)
            selectedConversationIDs.formIntersection(Set(summaries.filter(isSelectable).map(\.conversationId)))
            try reloadLedgerAndCandidates()
            lastError = nil
        } catch {
            self.archiveRoot = archiveRoot
            conversations = []
            selectedConversationIDs = []
            evidencePresentation = ChatConversationEvidencePresentation(conversations: [])
            candidates = []
            selectedCandidateJobID = nil
            lastError = "读取 ChatGPT 归档失败：\(error.localizedDescription)"
            throw error
        }
    }

    public func refresh(archiveRootPath: String) {
        let path = archiveRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            archiveRoot = nil
            conversations = []
            selectedConversationIDs = []
            lastError = ChatConversationHubStoreError.archiveRootNotConfigured.localizedDescription
            return
        }
        do {
            try refresh(archiveRoot: URL(fileURLWithPath: path, isDirectory: true))
        } catch {
            // refresh(archiveRoot:) already captures an actionable error for the UI.
        }
    }

    public func setSelectedConversationIDs(_ ids: Set<String>) {
        let selectableIDs = Set(conversations.filter(isSelectable).map(\.conversationId))
        selectedConversationIDs = ids.intersection(selectableIDs)
    }

    public func toggleSelection(conversationID: String) {
        guard isSelectable(conversationID: conversationID) else { return }
        if selectedConversationIDs.contains(conversationID) {
            selectedConversationIDs.remove(conversationID)
        } else {
            selectedConversationIDs.insert(conversationID)
        }
    }

    public func isSelectable(conversationID: String) -> Bool {
        conversations.first(where: { $0.conversationId == conversationID }).map(isSelectable) ?? false
    }

    public func generateTask() throws -> ChatConversationProcessingTask {
        guard ledgerSchemaState != .requiresV1Migration else {
            let error = ChatConversationHubStoreError.migrationRequired
            lastError = error.localizedDescription
            throw error
        }
        guard let archiveRoot else {
            let error = ChatConversationHubStoreError.archiveRootNotConfigured
            lastError = error.localizedDescription
            throw error
        }
        guard !selectedConversationIDs.isEmpty else {
            let error = ChatConversationHubStoreError.noConversationsSelected
            lastError = error.localizedDescription
            throw error
        }
        do {
            let task = try ledger.createTask(
                jobId: jobIDGenerator(),
                selectedConversationIDs: selectedConversationIDs.sorted(),
                archiveRoot: archiveRoot
            )
            lastGeneratedTask = task
            lastError = nil
            return task
        } catch {
            lastError = "生成 ChatGPT 处理任务失败：\(error.localizedDescription)"
            throw error
        }
    }

    public func selectCandidate(jobID: String?) {
        guard let jobID else {
            selectedCandidateJobID = nil
            return
        }
        selectedCandidateJobID = candidates.contains(where: { $0.jobId == jobID }) ? jobID : nil
    }

    public func renameCandidateTopic(id: String, name: String) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw ChatConversationHubStoreError.emptyCandidateTopicName }
        try updateSelectedCandidate { proposal in
            var didUpdate = false
            proposal.segments = proposal.segments.map { segment in
                guard case .new(let targetID, _) = segment.topicTarget, targetID == id else { return segment }
                didUpdate = true
                var updated = segment
                updated.topicTarget = .new(id: targetID, name: normalizedName)
                return updated
            }
            guard didUpdate else { throw ChatConversationHubStoreError.candidateTopicNotFound(id) }
        }
    }

    public func setCandidateSegmentTopic(
        segmentID: String,
        target: ChatConversationTopicTarget
    ) throws {
        try updateSelectedCandidate { proposal in
            guard let index = proposal.segments.firstIndex(where: { $0.id == segmentID }) else {
                throw ChatConversationHubStoreError.candidateSegmentNotFound(segmentID)
            }
            proposal.segments[index].topicTarget = target
        }
    }

    public func setCandidateSegmentMetadata(
        jobID: String,
        segmentID: String,
        title: String,
        summary: String
    ) throws {
        try updateCandidate(jobID: jobID) { proposal in
            guard let index = proposal.segments.firstIndex(where: { $0.id == segmentID }) else {
                throw ChatConversationHubStoreError.candidateSegmentNotFound(segmentID)
            }
            proposal.segments[index].title = title
            proposal.segments[index].summary = summary
        }
    }

    public func setCandidateAssetIncluded(
        jobID: String,
        assetID: String,
        isIncluded: Bool
    ) throws {
        guard candidates.contains(where: { $0.jobId == jobID }) else {
            throw ChatConversationHubStoreError.candidateNotFound(jobID)
        }
        guard let candidate = candidates.first(where: { $0.jobId == jobID }),
              candidate.assets.contains(where: { $0.id == assetID }) else {
            throw ChatConversationHubStoreError.candidateAssetNotFound(assetID)
        }
        var excluded = excludedCandidateAssetIDs[jobID] ?? []
        if isIncluded {
            excluded.remove(assetID)
        } else {
            excluded.insert(assetID)
        }
        excludedCandidateAssetIDs[jobID] = excluded
    }

    public func updateCandidateAsset(
        jobID: String,
        assetID: String,
        title: String,
        kind: ChatStudyAssetKind,
        subtype: String,
        uses: Set<ChatStudyAssetUse>,
        draftText: String?
    ) throws {
        try updateCandidate(jobID: jobID) { proposal in
            guard let index = proposal.assets.firstIndex(where: { $0.id == assetID }) else {
                throw ChatConversationHubStoreError.candidateAssetNotFound(assetID)
            }
            proposal.assets[index].title = title
            proposal.assets[index].kind = kind
            proposal.assets[index].subtype = subtype
            proposal.assets[index].uses = uses
            if proposal.assets[index].preservation == .distilled {
                if let draftText, draftText != proposal.assets[index].draftText {
                    proposal.assets[index].draftText = draftText
                    proposal.assets[index].origin = .userEdited
                }
            }
        }
    }

    public func confirmCandidate(jobID: String) throws -> ChatConversationReceipt {
        guard var candidate = candidates.first(where: { $0.jobId == jobID }) else {
            throw ChatConversationHubStoreError.candidateNotFound(jobID)
        }
        let excluded = excludedCandidateAssetIDs[jobID] ?? []
        candidate.assets = candidate.assets.filter { !excluded.contains($0.id) }
        do {
            let receipt = try ledger.apply(candidate)
            excludedCandidateAssetIDs[jobID] = nil
            try reloadLedgerAndCandidates()
            lastError = nil
            return receipt
        } catch {
            lastError = "确认 ChatGPT 候选失败：\(error.localizedDescription)"
            throw error
        }
    }

    public func rejectCandidate(jobID: String, reason: String) throws -> ChatConversationReceipt {
        guard candidates.contains(where: { $0.jobId == jobID }) else {
            throw ChatConversationHubStoreError.candidateNotFound(jobID)
        }
        do {
            let receipt = try ledger.reject(jobId: jobID, reason: reason)
            excludedCandidateAssetIDs[jobID] = nil
            if let archiveRoot {
                try refresh(archiveRoot: archiveRoot)
            } else {
                try reloadLedgerAndCandidates()
            }
            lastError = nil
            return receipt
        } catch {
            lastError = "拒绝 ChatGPT 候选失败：\(error.localizedDescription)"
            throw error
        }
    }

    public func renameTopic(id: String, name: String) throws {
        try updateLedgerPresentation { try ledger.renameTopic(id: id, name: name) }
    }

    public func mergeTopic(id: String, intoTopicID: String) throws {
        try updateLedgerPresentation { try ledger.mergeTopic(id: id, intoTopicID: intoTopicID) }
    }

    public func moveSegment(id: String, toTopicID: String) throws {
        try updateLedgerPresentation { try ledger.moveSegment(id: id, toTopicID: toTopicID) }
    }

    public func setMark(assetID: String, isHighlighted: Bool, note: String?) throws {
        try updateLedgerPresentation {
            try ledger.setMark(assetID: assetID, isHighlighted: isHighlighted, note: note)
        }
    }

    public func appendUserEditedVersion(assetID: String, text: String) throws {
        guard let asset = ledgerDocument.assets.first(where: { $0.id == assetID }),
              let current = asset.currentVersion else {
            throw ChatConversationHubStoreError.candidateAssetNotFound(assetID)
        }
        try updateLedgerPresentation {
            try ledger.appendUserVersion(
                assetID: assetID,
                text: text,
                sourceMessages: current.sourceMessages,
                sourceSpans: current.sourceSpans,
                preservation: current.preservation
            )
        }
    }

    public func addManualCandidateAsset(
        jobID: String,
        segmentID: String,
        selection: ChatConversationTextSelection,
        title: String,
        kind: ChatStudyAssetKind,
        subtype: String,
        uses: Set<ChatStudyAssetUse>
    ) throws {
        try updateCandidate(jobID: jobID) { proposal in
            guard proposal.segments.contains(where: { $0.id == segmentID }) else {
                throw ChatConversationHubStoreError.candidateSegmentNotFound(segmentID)
            }
            let asset = ChatConversationProposalAsset(
                id: "\(jobID)-manual-\(UUID().uuidString.lowercased())",
                segmentId: segmentID,
                title: title,
                kind: kind,
                subtype: subtype,
                uses: uses,
                preservation: .verbatim,
                draftText: nil,
                sourceBlockIDs: [],
                sourceSpans: [selection.span],
                replacesAssetID: nil,
                origin: .userSelection
            )
            proposal.assets.append(asset)
        }
    }

    public func addManualFormalAsset(
        segmentID: String,
        selection: ChatConversationTextSelection,
        title: String,
        kind: ChatStudyAssetKind,
        subtype: String,
        uses: Set<ChatStudyAssetUse>
    ) throws {
        let version = ChatStudyAssetVersion(
            id: "manual-\(UUID().uuidString.lowercased())-v1",
            textSnapshot: selection.textSnapshot,
            textHash: ContentHasher.hash(selection.textSnapshot),
            preservation: .verbatim,
            origin: .userSelection,
            sourceMessages: [selection.span.message],
            sourceSpans: [selection.span],
            supersedesVersionId: nil,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        let asset = ChatStudyAsset(
            id: version.id.replacingOccurrences(of: "-v1", with: ""),
            segmentId: segmentID,
            title: title,
            kind: kind,
            subtype: subtype,
            uses: uses,
            versions: [version],
            currentVersionId: version.id,
            isUserLocked: true
        )
        try updateLedgerPresentation {
            try ledger.appendUserAsset(asset)
        }
    }

    @discardableResult
    public func performLegacyLedgerMigration() throws -> URL {
        guard ledgerSchemaState == .requiresV1Migration else {
            throw ChatConversationHubStoreError.migrationNotNeeded
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let backupURL = layout.recordsDirectoryURL
            .appendingPathComponent("chatgpt-ledger.v1-backup-\(stamp).json")
        do {
            _ = try ledger.migrateLegacyLedger(backupURL: backupURL)
            lastMigrationBackupURL = backupURL
            ledgerSchemaState = try ledger.inspectSchemaState()
            if let archiveRoot {
                try refresh(archiveRoot: archiveRoot)
            } else {
                try reloadLedgerAndCandidates()
            }
            lastError = nil
            return backupURL
        } catch {
            lastError = "迁移备考库失败：\(error.localizedDescription)"
            throw error
        }
    }

    public func sourceMessage(for reference: ChatConversationMessageReference) -> ChatConversationMessage? {
        evidencePresentation.sourceMessage(for: reference)
    }

    public func sourceSummary(for references: [ChatConversationMessageReference]) -> ChatConversationSourceSummary {
        evidencePresentation.summary(for: references)
    }

    public func sourceTurns(for references: [ChatConversationMessageReference]) -> [ChatConversationSourceTurn] {
        evidencePresentation.turns(for: references)
    }

    public func conversationTitle(for conversationID: String) -> String {
        evidencePresentation.conversationTitle(for: conversationID)
    }

    /// All message references for a conversation, archive order. Used by the
    /// session stage and excerpt selection wiring.
    public func messageReferences(forConversationID conversationID: String) -> [ChatConversationMessageReference] {
        guard let conversation = conversations.first(where: { $0.conversationId == conversationID }) else {
            return []
        }
        return conversation.messages.map {
            ChatConversationMessageReference(
                conversationId: conversationID,
                messageId: $0.id
            )
        }
    }

    public func conversation(id conversationID: String) -> ChatConversationArchiveSummary? {
        conversations.first(where: { $0.conversationId == conversationID })
    }

    /// Prefer a formal segment already linked to this conversation so session
    /// excerpts can call addManualFormalAsset without a schema migration.
    public func preferredFormalSegmentID(forConversationID conversationID: String) -> String? {
        if let exact = ledgerDocument.segments.first(where: { segment in
            segment.sourceMessages.contains(where: { $0.conversationId == conversationID })
        }) {
            return exact.id
        }
        return ledgerDocument.segments.first?.id
    }


    public func sourceStatus(for asset: ChatStudyAsset) -> ChatConversationSourceStatus {
        guard let version = asset.currentVersion else { return .unavailable }
        return evidencePresentation.sourceStatus(for: version)
    }

    public func candidateSourceContext(
        for asset: ChatConversationProposalAsset,
        in candidate: ChatConversationProposal
    ) -> ChatConversationAssetSourceContext? {
        ChatConversationEvidencePresentation.sourceContext(for: asset, in: candidate)
    }

    public func formalSourceContext(
        for asset: ChatStudyAsset
    ) -> ChatConversationAssetSourceContext? {
        ChatConversationEvidencePresentation.sourceContext(for: asset)
    }

    public func candidateSupportingSegmentIDs(
        for asset: ChatConversationProposalAsset,
        in candidate: ChatConversationProposal
    ) -> [String] {
        ChatConversationEvidencePresentation.segmentIDs(for: asset, in: candidate.segments)
    }

    public func formalSupportingSegmentIDs(for asset: ChatStudyAsset) -> [String] {
        ChatConversationEvidencePresentation.segmentIDs(for: asset, in: ledgerDocument.segments)
    }

    public func isCandidateAssetIncluded(jobID: String, assetID: String) -> Bool {
        !(excludedCandidateAssetIDs[jobID] ?? []).contains(assetID)
    }

    public func asset(id: String) -> ChatStudyAsset? {
        ledgerDocument.assets.first(where: { $0.id == id })
    }


    // MARK: - Reading notes (parallel to formal ledger)

    public var allNotes: [ReadingNote] {
        readingNotes.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt { return lhs.id > rhs.id }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func notes(forConversationID conversationID: String) -> [ReadingNote] {
        allNotes.filter { note in
            if case .sourceMessageSpan(let span) = note.anchor {
                return span.conversationId == conversationID
            }
            return false
        }
    }

    public func notes(forAssetID assetID: String) -> [ReadingNote] {
        allNotes.filter { note in
            if case .formalAssetSpan(let span) = note.anchor {
                return span.assetId == assetID
            }
            return false
        }
    }

    public func notes(forMessageID messageID: String) -> [ReadingNote] {
        allNotes.filter { note in
            if case .sourceMessageSpan(let span) = note.anchor {
                return span.messageId == messageID
            }
            return false
        }
    }

    @discardableResult
    public func addHighlight(
        quoteSnapshot: String,
        anchor: ReadingNoteAnchor,
        id: String = UUID().uuidString.lowercased()
    ) throws -> ReadingNote {
        let note = try ReadingNote.make(
            id: id,
            body: nil,
            isHighlight: true,
            quoteSnapshot: quoteSnapshot,
            anchor: anchor
        )
        readingNotes.append(note)
        persistReadingNotes()
        return note
    }

    @discardableResult
    public func addNote(
        body: String?,
        quoteSnapshot: String,
        anchor: ReadingNoteAnchor,
        isHighlight: Bool = false,
        id: String = UUID().uuidString.lowercased()
    ) throws -> ReadingNote {
        let note = try ReadingNote.make(
            id: id,
            body: body,
            isHighlight: isHighlight,
            quoteSnapshot: quoteSnapshot,
            anchor: anchor
        )
        readingNotes.append(note)
        persistReadingNotes()
        return note
    }

    public func updateReadingNote(id: String, body: String?, isHighlight: Bool? = nil) throws {
        guard let index = readingNotes.firstIndex(where: { $0.id == id }) else {
            throw ChatConversationHubStoreError.readingNoteNotFound(id)
        }
        var note = readingNotes[index]
        if let body {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            note.body = trimmed.isEmpty ? nil : trimmed
        } else {
            note.body = nil
        }
        if let isHighlight {
            note.isHighlight = isHighlight
        }
        note.updatedAt = ISO8601Codec.string(from: Date())
        readingNotes[index] = note
        persistReadingNotes()
    }

    public func deleteReadingNote(id: String) {
        let before = readingNotes.count
        readingNotes.removeAll { $0.id == id }
        if readingNotes.count != before {
            persistReadingNotes()
        }
    }

    private func updateSelectedCandidate(
        _ update: (inout ChatConversationProposal) throws -> Void
    ) throws {
        guard let jobID = selectedCandidateJobID else {
            throw ChatConversationHubStoreError.candidateNotFound("")
        }
        try updateCandidate(jobID: jobID, update)
    }

    private func updateCandidate(
        jobID: String,
        _ update: (inout ChatConversationProposal) throws -> Void
    ) throws {
        guard let index = candidates.firstIndex(where: { $0.jobId == jobID }) else {
            throw ChatConversationHubStoreError.candidateNotFound(jobID)
        }
        var candidate = candidates[index]
        try update(&candidate)
        candidates[index] = candidate
    }

    private func updateLedgerPresentation(
        _ update: () throws -> ChatConversationLedgerDocument
    ) throws {
        do {
            ledgerDocument = try update()
            try reloadLedgerAndCandidates()
            lastError = nil
        } catch {
            lastError = "更新 ChatGPT 账本失败：\(error.localizedDescription)"
            throw error
        }
    }

    private func reloadLedgerAndCandidates() throws {
        ledgerSchemaState = try ledger.inspectSchemaState()
        if ledgerSchemaState == .requiresV1Migration {
            candidates = []
            selectedCandidateJobID = nil
            return
        }
        let document = try ledger.load()
        ledgerDocument = document
        let terminalJobIDs = Set(document.receipts.compactMap { receipt -> String? in
            switch receipt.status {
            case .accepted, .rejected, .noOp:
                return receipt.jobId
            case .pending:
                return nil
            }
        })
        candidates = try proposalInbox.readPending().filter { !terminalJobIDs.contains($0.jobId) }
        if let selectedCandidateJobID,
           !candidates.contains(where: { $0.jobId == selectedCandidateJobID }) {
            self.selectedCandidateJobID = nil
        }
    }

    private func persistUserMarks() {
        do {
            try layout.ensureDirectories()
            let document = ChatConversationUserMarksDocument(
                schemaVersion: ChatConversationUserMarksDocument.currentSchemaVersion,
                starredConversationIDs: starredConversationIDs.sorted(),
                starredTurnIDs: starredTurnIDs.sorted()
            )
            let data = try JSONEncoder().encode(document)
            try data.write(to: layout.chatConversationUserMarksFileURL, options: .atomic)
        } catch {
            lastError = "保存星标失败：\(error.localizedDescription)"
        }
    }

    private static func loadUserMarks(layout: EvolutionLedgerLayout) -> ChatConversationUserMarksDocument {
        let url = layout.chatConversationUserMarksFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ChatConversationUserMarksDocument.self, from: data)
        } catch {
            return .empty
        }
    }

    private func persistReadingNotes() {
        do {
            try layout.ensureDirectories()
            let document = ReadingNotesDocument(
                schemaVersion: ReadingNotesDocument.currentSchemaVersion,
                notes: readingNotes
            )
            try ReadingNotesFileStore.save(document, to: layout.chatConversationReadingNotesFileURL)
        } catch {
            lastError = "保存阅读笔记失败：\(error.localizedDescription)"
        }
    }

    private func isSelectable(_ conversation: ChatConversationArchiveSummary) -> Bool {
        conversation.issue == nil && conversation.pendingMessageCount > 0
    }

    private static func isTerminal(_ status: ChatConversationReceiptStatus) -> Bool {
        switch status {
        case .accepted, .rejected, .noOp:
            return true
        case .pending:
            return false
        }
    }
}

private extension ChatConversationProcessingStatus {
    static var allCases: [Self] {
        [.pending, .partiallyProcessed, .processed, .needsReexport]
    }
}
