import Foundation

public protocol ChatConversationLedgerDocumentStore: Sendable {
    func load() throws -> ChatConversationLedgerDocument
    func save(_ document: ChatConversationLedgerDocument) throws
}

public struct JSONChatConversationLedgerStore: ChatConversationLedgerDocumentStore, @unchecked Sendable {
    public let layout: EvolutionLedgerLayout
    private let fileManager: FileManager

    public init(layout: EvolutionLedgerLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public func load() throws -> ChatConversationLedgerDocument {
        guard fileManager.fileExists(atPath: layout.chatConversationLedgerFileURL.path) else {
            return .empty
        }
        return try JSONDecoder().decode(
            ChatConversationLedgerDocument.self,
            from: Data(contentsOf: layout.chatConversationLedgerFileURL)
        )
    }

    public func save(_ document: ChatConversationLedgerDocument) throws {
        try layout.ensureDirectories(fileManager: fileManager)
        let data = try encoded(document)
        try data.write(to: layout.chatConversationLedgerFileURL, options: .atomic)
    }

    private func encoded(_ document: ChatConversationLedgerDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }
}

public enum ChatConversationLedgerError: Error, Sendable, Equatable {
    case emptyJobId
    case invalidJobId
    case taskAlreadyExists(String)
    case missingTask(String)
    case noPendingMessages
    case staleSource
    case staleLedger
    case incompleteInputCoverage
    case invalidSourceReference
    case invalidTopicTarget
    case duplicateRecordID
    case jobAlreadyRejected
}

public final class ChatConversationLedger: @unchecked Sendable {
    private let layout: EvolutionLedgerLayout
    private let store: any ChatConversationLedgerDocumentStore
    private let archiveReader: ChatConversationArchiveReader
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(
        layout: EvolutionLedgerLayout,
        store: (any ChatConversationLedgerDocumentStore)? = nil,
        archiveReader: ChatConversationArchiveReader = ChatConversationArchiveReader(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.layout = layout
        self.store = store ?? JSONChatConversationLedgerStore(layout: layout)
        self.archiveReader = archiveReader
        self.now = now
    }

    public func load() throws -> ChatConversationLedgerDocument {
        lock.lock()
        defer { lock.unlock() }
        return try store.load()
    }

    public func createTask(
        jobId: String,
        selectedConversationIDs: [String],
        archiveRoot: URL
    ) throws -> ChatConversationProcessingTask {
        let normalizedJobID = try normalizedJobID(jobId)

        lock.lock()
        defer { lock.unlock() }
        let taskURL = layout.chatConversationJobURL(jobId: normalizedJobID)
        guard !FileManager.default.fileExists(atPath: taskURL.path) else {
            throw ChatConversationLedgerError.taskAlreadyExists(normalizedJobID)
        }

        let document = try store.load()
        let summaries = try archiveReader.read(
            archiveRoot: archiveRoot,
            processedRevisions: document.processedRevisions
        )
        let selectedIDs = Array(Set(selectedConversationIDs)).sorted()
        let selected = summaries.filter { selectedIDs.contains($0.conversationId) }
        let inputMessages = selected.flatMap(taskMessages(for:))
        guard inputMessages.contains(where: { !$0.contextOnly }) else {
            throw ChatConversationLedgerError.noPendingMessages
        }

        let task = ChatConversationProcessingTask(
            jobId: normalizedJobID,
            createdAt: timestamp(now()),
            selectedConversationIDs: selectedIDs,
            inputMessages: inputMessages,
            existingTopics: document.topics.map { ChatConversationTaskTopic(id: $0.id, name: $0.name) },
            existingFindings: document.findings.map { ChatConversationTaskFinding(id: $0.id, topicId: $0.topicId, body: $0.body) },
            sourceDigest: sourceDigest(for: inputMessages),
            baseLedgerDigest: try ledgerDigest(document)
        )
        try writeAtomically(task, to: taskURL)
        return task
    }

    public func apply(_ proposal: ChatConversationProposal) throws -> ChatConversationReceipt {
        lock.lock()
        defer { lock.unlock() }

        let task = try loadTask(jobId: proposal.jobId)
        var document = try store.load()
        let proposalDigest = try digest(proposal)
        if let existing = document.receipts.first(where: { $0.jobId == proposal.jobId }) {
            if existing.status == .accepted, existing.proposalDigest == proposalDigest {
                try writeAtomically(existing, to: layout.chatConversationReceiptURL(jobId: existing.jobId))
                return ChatConversationReceipt(
                    jobId: existing.jobId,
                    proposalDigest: existing.proposalDigest,
                    status: .noOp,
                    recordedAt: timestamp(now()),
                    reason: nil
                )
            }
            throw ChatConversationLedgerError.jobAlreadyRejected
        }
        guard proposal.sourceDigest == task.sourceDigest else { throw ChatConversationLedgerError.staleSource }
        guard proposal.baseLedgerDigest == task.baseLedgerDigest,
              try ledgerDigest(document) == task.baseLedgerDigest else {
            throw ChatConversationLedgerError.staleLedger
        }
        try validate(proposal, against: task, document: document)

        var targetIDs: [ChatConversationTopicTarget: String] = [:]
        for target in proposal.segments.map(\.topicTarget) + proposal.findings.map(\.topicTarget) {
            targetIDs[target] = try resolveTopic(target, in: &document)
        }
        for segment in proposal.segments {
            guard let topicID = targetIDs[segment.topicTarget] else { throw ChatConversationLedgerError.invalidTopicTarget }
            let conversationIDs = Set(segment.sourceMessages.map(\.conversationId))
            guard conversationIDs.count == 1, let conversationId = conversationIDs.first else {
                throw ChatConversationLedgerError.invalidSourceReference
            }
            document.segments.append(ChatConversationSegment(
                id: segment.id,
                conversationId: conversationId,
                topicId: topicID,
                sourceMessages: segment.sourceMessages
            ))
        }
        for finding in proposal.findings {
            guard let topicID = targetIDs[finding.topicTarget] else { throw ChatConversationLedgerError.invalidTopicTarget }
            document.findings.append(ChatConversationFinding(
                id: finding.id,
                topicId: topicID,
                body: finding.body,
                sourceMessages: finding.sourceMessages
            ))
        }
        document.processedRevisions.append(contentsOf: task.inputMessages.compactMap { message in
            guard !message.contextOnly else { return nil }
            return ChatConversationProcessedRevision(
                conversationId: message.conversationId,
                messageId: message.messageId,
                contentHash: message.contentHash,
                taskId: task.jobId
            )
        })
        let receipt = ChatConversationReceipt(
            jobId: task.jobId,
            proposalDigest: proposalDigest,
            status: .accepted,
            recordedAt: timestamp(now())
        )
        document.receipts.append(receipt)
        document.updatedAt = timestamp(now())
        try store.save(document)
        try writeAtomically(receipt, to: layout.chatConversationReceiptURL(jobId: receipt.jobId))
        return receipt
    }

    public func reject(jobId: String, reason: String) throws -> ChatConversationReceipt {
        lock.lock()
        defer { lock.unlock() }
        let task = try loadTask(jobId: jobId)
        var document = try store.load()
        if let existing = document.receipts.first(where: { $0.jobId == jobId }) {
            return existing
        }
        let receipt = ChatConversationReceipt(
            jobId: task.jobId,
            proposalDigest: "",
            status: .rejected,
            recordedAt: timestamp(now()),
            reason: reason
        )
        document.receipts.append(receipt)
        document.updatedAt = timestamp(now())
        try store.save(document)
        try writeAtomically(receipt, to: layout.chatConversationReceiptURL(jobId: receipt.jobId))
        return receipt
    }

    private func taskMessages(for summary: ChatConversationArchiveSummary) -> [ChatConversationTaskMessage] {
        guard summary.issue == nil else { return [] }
        let pendingIDs = Set(summary.pendingMessageIDs)
        guard let firstPendingIndex = summary.messages.firstIndex(where: { pendingIDs.contains($0.id) }) else {
            return []
        }
        let contextCandidates = Array(summary.messages[max(0, firstPendingIndex - 2)..<firstPendingIndex])
        let hasQuestionAnswerContext = contextCandidates.map(\.role) == [.user, .assistant]
        let context = hasQuestionAnswerContext
            ? contextCandidates.map { ChatConversationTaskMessage(conversationId: summary.conversationId, message: $0, contextOnly: true) }
            : []
        let pending = summary.messages.compactMap { message -> ChatConversationTaskMessage? in
            guard pendingIDs.contains(message.id) else { return nil }
            return ChatConversationTaskMessage(conversationId: summary.conversationId, message: message, contextOnly: false)
        }
        return context + pending
    }

    private func validate(
        _ proposal: ChatConversationProposal,
        against task: ChatConversationProcessingTask,
        document: ChatConversationLedgerDocument
    ) throws {
        let input = Set(task.inputMessages.filter { !$0.contextOnly }.map(\.reference))
        let segmentSources = proposal.segments.flatMap(\.sourceMessages)
        let ignoredSources = proposal.ignoredMessages.map(\.sourceMessage)
        let coverage = segmentSources + ignoredSources
        guard Set(coverage) == input, Set(coverage).count == coverage.count else {
            throw ChatConversationLedgerError.incompleteInputCoverage
        }
        guard proposal.findings.flatMap(\.sourceMessages).allSatisfy({ input.contains($0) }),
              proposal.segments.flatMap(\.sourceMessages).allSatisfy({ input.contains($0) }),
              proposal.ignoredMessages.allSatisfy({ !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ChatConversationLedgerError.invalidSourceReference
        }
        let newSegmentIDs = proposal.segments.map(\.id)
        let newFindingIDs = proposal.findings.map(\.id)
        guard Set(newSegmentIDs).count == newSegmentIDs.count,
              Set(newFindingIDs).count == newFindingIDs.count,
              !newSegmentIDs.contains(where: { segmentID in
                  document.segments.contains(where: { existing in existing.id == segmentID })
              }),
              !newFindingIDs.contains(where: { findingID in
                  document.findings.contains(where: { existing in existing.id == findingID })
              }) else {
            throw ChatConversationLedgerError.duplicateRecordID
        }
        for target in proposal.segments.map(\.topicTarget) + proposal.findings.map(\.topicTarget) {
            switch target {
            case .existing(let id):
                guard document.topics.contains(where: { $0.id == id }) else {
                    throw ChatConversationLedgerError.invalidTopicTarget
                }
            case .new(let id, let name):
                guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ChatConversationLedgerError.invalidTopicTarget
                }
            }
        }
    }

    private func resolveTopic(
        _ target: ChatConversationTopicTarget,
        in document: inout ChatConversationLedgerDocument
    ) throws -> String {
        switch target {
        case .existing(let id):
            guard document.topics.contains(where: { $0.id == id }) else {
                throw ChatConversationLedgerError.invalidTopicTarget
            }
            return id
        case .new(let id, let name):
            if let existing = document.topics.first(where: { $0.id == id }) {
                guard existing.name == name else { throw ChatConversationLedgerError.invalidTopicTarget }
                return existing.id
            }
            document.topics.append(ChatConversationTopic(id: id, name: name))
            return id
        }
    }

    private func loadTask(jobId: String) throws -> ChatConversationProcessingTask {
        let normalizedJobID = try normalizedJobID(jobId)
        let url = layout.chatConversationJobURL(jobId: normalizedJobID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ChatConversationLedgerError.missingTask(normalizedJobID)
        }
        return try JSONDecoder().decode(ChatConversationProcessingTask.self, from: Data(contentsOf: url))
    }

    private func normalizedJobID(_ jobId: String) throws -> String {
        let normalized = jobId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw ChatConversationLedgerError.emptyJobId }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard normalized.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ChatConversationLedgerError.invalidJobId
        }
        return normalized
    }

    private func sourceDigest(for messages: [ChatConversationTaskMessage]) -> String {
        ContentHasher.hashParts(messages.map {
            "\($0.conversationId)|\($0.messageId)|\($0.contentHash)|\($0.contextOnly)"
        })
    }

    private func ledgerDigest(_ document: ChatConversationLedgerDocument) throws -> String {
        try digest(document)
    }

    private func digest<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return ContentHasher.hash(String(decoding: try encoder.encode(value), as: UTF8.self))
    }

    private func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func writeAtomically<T: Encodable>(_ value: T, to url: URL) throws {
        try layout.ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
