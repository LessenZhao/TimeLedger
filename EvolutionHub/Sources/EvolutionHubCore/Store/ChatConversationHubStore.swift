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
    case emptyCandidateTopicName
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
        case .emptyCandidateTopicName:
            return "候选主题名称不能为空。"
        }
    }
}

public struct ChatConversationConversationProjection: Identifiable, Sendable, Hashable {
    public var conversationId: String
    public var title: String
    public var segments: [ChatConversationSegment]
    public var findings: [ChatConversationFinding]

    public var id: String { conversationId }
}

public struct ChatConversationTopicProjection: Identifiable, Sendable, Hashable {
    public var topic: ChatConversationTopic
    public var segments: [ChatConversationSegment]
    public var findings: [ChatConversationFinding]

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
    @Published public private(set) var selectedCandidateJobID: String?
    @Published public private(set) var ledgerDocument: ChatConversationLedgerDocument

    private let ledger: ChatConversationLedger
    private let proposalInbox: ChatConversationProposalInbox
    private let jobIDGenerator: @Sendable () -> String
    private var archiveRoot: URL?
    private var messagesByReference: [ChatConversationMessageReference: ChatConversationMessage] = [:]

    public init(
        layout: EvolutionLedgerLayout = .defaultDocuments(),
        jobIDGenerator: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.ledger = ChatConversationLedger(layout: layout)
        self.proposalInbox = ChatConversationProposalInbox(layout: layout)
        self.jobIDGenerator = jobIDGenerator
        self.statusFilter = Set(ChatConversationProcessingStatus.allCases)
        self.dateRange = nil
        self.lastGeneratedTask = nil
        self.lastError = nil
        self.selectedCandidateJobID = nil
        self.ledgerDocument = .empty
    }

    public var visibleConversations: [ChatConversationArchiveSummary] {
        conversations.filter { conversation in
            guard statusFilter.contains(conversation.status) else { return false }
            guard let dateRange else { return true }
            guard let updatedAt = ISO8601Codec.date(from: conversation.updatedAt) else { return false }
            return dateRange.contains(updatedAt)
        }
    }

    public var lastGeneratedCommand: String? {
        lastGeneratedTask.map { "$chatgpt-ledger process \($0.jobId)" }
    }

    public var selectedCandidate: ChatConversationProposal? {
        guard let selectedCandidateJobID else { return nil }
        return candidates.first(where: { $0.jobId == selectedCandidateJobID })
    }

    public var conversationProjections: [ChatConversationConversationProjection] {
        conversations.map { conversation in
            ChatConversationConversationProjection(
                conversationId: conversation.conversationId,
                title: conversation.title,
                segments: ledgerDocument.segments.filter { $0.conversationId == conversation.conversationId },
                findings: ledgerDocument.findings.filter { finding in
                    finding.sourceMessages.contains(where: { $0.conversationId == conversation.conversationId })
                }
            )
        }
    }

    public var topicProjections: [ChatConversationTopicProjection] {
        ledgerDocument.topics.map { topic in
            ChatConversationTopicProjection(
                topic: topic,
                segments: ledgerDocument.segments.filter { $0.topicId == topic.id },
                findings: ledgerDocument.findings.filter { $0.topicId == topic.id }
            )
        }
    }

    public func refresh(archiveRoot: URL) throws {
        do {
            let summaries = try ledger.readArchiveSummaries(archiveRoot: archiveRoot)
            self.archiveRoot = archiveRoot
            conversations = summaries
            messagesByReference = Dictionary(
                uniqueKeysWithValues: summaries.flatMap { summary in
                    summary.messages.map {
                        (ChatConversationMessageReference(conversationId: summary.conversationId, messageId: $0.id), $0)
                    }
                }
            )
            selectedConversationIDs.formIntersection(Set(summaries.filter(isSelectable).map(\.conversationId)))
            try reloadLedgerAndCandidates()
            lastError = nil
        } catch {
            self.archiveRoot = archiveRoot
            conversations = []
            selectedConversationIDs = []
            messagesByReference = [:]
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
            proposal.findings = proposal.findings.map { finding in
                guard case .new(let targetID, _) = finding.topicTarget, targetID == id else { return finding }
                didUpdate = true
                var updated = finding
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

    public func confirmCandidate(jobID: String) throws -> ChatConversationReceipt {
        guard let candidate = candidates.first(where: { $0.jobId == jobID }) else {
            throw ChatConversationHubStoreError.candidateNotFound(jobID)
        }
        do {
            let receipt = try ledger.apply(candidate)
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

    public func setMark(findingID: String, isHighlighted: Bool, note: String?) throws {
        try updateLedgerPresentation {
            try ledger.setMark(findingID: findingID, isHighlighted: isHighlighted, note: note)
        }
    }

    public func sourceMessage(for reference: ChatConversationMessageReference) -> ChatConversationMessage? {
        messagesByReference[reference]
    }

    public func mark(for findingID: String) -> ChatConversationMark? {
        ledgerDocument.marks.first(where: { $0.findingId == findingID })
    }

    private func updateSelectedCandidate(
        _ update: (inout ChatConversationProposal) throws -> Void
    ) throws {
        guard let jobID = selectedCandidateJobID,
              let index = candidates.firstIndex(where: { $0.jobId == jobID }) else {
            throw ChatConversationHubStoreError.candidateNotFound(selectedCandidateJobID ?? "")
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

    private func isSelectable(_ conversation: ChatConversationArchiveSummary) -> Bool {
        conversation.issue == nil && conversation.pendingMessageCount > 0
    }
}

private extension ChatConversationProcessingStatus {
    static var allCases: [Self] {
        [.pending, .partiallyProcessed, .processed, .needsReexport]
    }
}
