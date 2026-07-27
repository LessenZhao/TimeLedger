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
}

extension ChatConversationHubStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .archiveRootNotConfigured:
            return "请先在设置中配置 ChatGPT archive 根目录。"
        case .noConversationsSelected:
            return "请选择至少一个有待处理消息的会话。"
        }
    }
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

    private let ledger: ChatConversationLedger
    private let jobIDGenerator: @Sendable () -> String
    private var archiveRoot: URL?

    public init(
        layout: EvolutionLedgerLayout = .defaultDocuments(),
        jobIDGenerator: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.ledger = ChatConversationLedger(layout: layout)
        self.jobIDGenerator = jobIDGenerator
        self.statusFilter = Set(ChatConversationProcessingStatus.allCases)
        self.dateRange = nil
        self.lastGeneratedTask = nil
        self.lastError = nil
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

    public func refresh(archiveRoot: URL) throws {
        do {
            let summaries = try ledger.readArchiveSummaries(archiveRoot: archiveRoot)
            self.archiveRoot = archiveRoot
            conversations = summaries
            selectedConversationIDs.formIntersection(Set(summaries.filter(isSelectable).map(\.conversationId)))
            lastError = nil
        } catch {
            self.archiveRoot = archiveRoot
            conversations = []
            selectedConversationIDs = []
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

    private func isSelectable(_ conversation: ChatConversationArchiveSummary) -> Bool {
        conversation.issue == nil && conversation.pendingMessageCount > 0
    }
}

private extension ChatConversationProcessingStatus {
    static var allCases: [Self] {
        [.pending, .partiallyProcessed, .processed, .needsReexport]
    }
}
