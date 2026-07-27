import Foundation
import Darwin

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
    case pendingFinalization(String)
    case taskAlreadyExists(String)
    case missingTask(String)
    case noPendingMessages
    case staleSource
    case staleLedger
    case incompleteInputCoverage
    case invalidSourceReference
    case assetSegmentMismatch
    case invalidTopicTarget
    case duplicateRecordID
    case jobAlreadyRejected
    case missingTopic(String)
    case missingSegment(String)
    case missingAsset(String)
    case emptyTopicName
    case identicalTopicMerge
    case lockedAsset(String)
    case invalidAssetMaterialization(String)
}

public final class ChatConversationLedger: @unchecked Sendable {
    private let layout: EvolutionLedgerLayout
    private let store: any ChatConversationLedgerDocumentStore
    private let archiveReader: ChatConversationArchiveReader
    private let now: @Sendable () -> Date
    private let receiptWriter: @Sendable (ChatConversationReceipt, URL) throws -> Void
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
        self.receiptWriter = Self.defaultReceiptWriter
    }

    init(
        layout: EvolutionLedgerLayout,
        store: (any ChatConversationLedgerDocumentStore)? = nil,
        archiveReader: ChatConversationArchiveReader = ChatConversationArchiveReader(),
        now: @escaping @Sendable () -> Date = { Date() },
        receiptWriter: @escaping @Sendable (ChatConversationReceipt, URL) throws -> Void
    ) {
        self.layout = layout
        self.store = store ?? JSONChatConversationLedgerStore(layout: layout)
        self.archiveReader = archiveReader
        self.now = now
        self.receiptWriter = receiptWriter
    }

    public func load() throws -> ChatConversationLedgerDocument {
        lock.lock()
        defer { lock.unlock() }
        return try store.load()
    }

    public func inspectSchemaState() throws -> ChatConversationLedgerSchemaState {
        lock.lock()
        defer { lock.unlock() }
        let url = layout.chatConversationLedgerFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        let data = try Data(contentsOf: url)
        return try ChatConversationLedgerMigrator().inspect(data: data)
    }

    @discardableResult
    public func migrateLegacyLedger(backupURL: URL) throws -> ChatConversationLedgerDocument {
        lock.lock()
        defer { lock.unlock() }
        return try withExclusiveLedgerLock {
            let ledgerURL = layout.chatConversationLedgerFileURL
            guard FileManager.default.fileExists(atPath: ledgerURL.path) else {
                throw ChatConversationLedgerMigrationError.missingLedger
            }
            let originalData = try Data(contentsOf: ledgerURL)
            let state = try ChatConversationLedgerMigrator().inspect(data: originalData)
            guard state == .requiresV1Migration else {
                if case .unsupported(let version) = state {
                    throw ChatConversationLedgerMigrationError.unsupportedSchema(version)
                }
                throw ChatConversationLedgerMigrationError.notV1
            }

            try originalData.write(to: backupURL, options: .atomic)
            let backupData = try Data(contentsOf: backupURL)
            let originalHash = ContentHasher.hash(String(decoding: originalData, as: UTF8.self))
            let backupHash = ContentHasher.hash(String(decoding: backupData, as: UTF8.self))
            guard originalHash == backupHash else {
                throw ChatConversationLedgerMigrationError.backupHashMismatch
            }

            let migrated = try ChatConversationLedgerMigrator().migrateV1(
                data: backupData,
                migratedAt: timestamp(now())
            )
            let legacy = try JSONDecoder().decode(LegacyCountProbe.self, from: originalData)
            guard migrated.topics.count == legacy.topics.count,
                  migrated.segments.count == legacy.segments.count,
                  migrated.assets.count == legacy.findings.count,
                  migrated.processedRevisions.count == legacy.processedRevisions.count,
                  migrated.receipts.count == legacy.receipts.count else {
                throw ChatConversationLedgerMigrationError.conservationFailed("count mismatch")
            }

            try store.save(migrated)
            let reloaded = try store.load()
            guard reloaded.schemaVersion == 2,
                  reloaded.topics.count == legacy.topics.count,
                  reloaded.segments.count == legacy.segments.count,
                  reloaded.assets.count == legacy.findings.count,
                  reloaded.processedRevisions.count == legacy.processedRevisions.count,
                  reloaded.receipts.count == legacy.receipts.count else {
                throw ChatConversationLedgerMigrationError.conservationFailed("reload mismatch")
            }
            return reloaded
        }
    }

    public func appendUserVersion(
        assetID: String,
        text: String,
        sourceMessages: [ChatConversationMessageReference],
        sourceSpans: [ChatConversationSourceSpan],
        preservation: ChatStudyAssetPreservation = .distilled
    ) throws -> ChatConversationLedgerDocument {
        try updateDocument { document in
            guard let index = document.assets.firstIndex(where: { $0.id == assetID }) else {
                throw ChatConversationLedgerError.missingAsset(assetID)
            }
            guard !text.isEmpty else {
                throw ChatConversationLedgerError.invalidAssetMaterialization("empty user version text")
            }
            let current = document.assets[index]
            let version = ChatStudyAssetVersion(
                id: "\(assetID)-v\(current.versions.count + 1)",
                textSnapshot: text,
                textHash: ContentHasher.hash(text),
                preservation: preservation,
                origin: .userEdited,
                sourceMessages: sourceMessages,
                sourceSpans: sourceSpans,
                supersedesVersionId: current.currentVersionId,
                createdAt: timestamp(now())
            )
            document.assets[index].versions.append(version)
            document.assets[index].currentVersionId = version.id
            document.assets[index].isUserLocked = true
        }
    }

    public func appendUserAsset(_ asset: ChatStudyAsset) throws -> ChatConversationLedgerDocument {
        try updateDocument { document in
            guard document.segments.contains(where: { $0.id == asset.segmentId }) else {
                throw ChatConversationLedgerError.missingSegment(asset.segmentId)
            }
            guard !document.assets.contains(where: { $0.id == asset.id }) else {
                throw ChatConversationLedgerError.duplicateRecordID
            }
            document.assets.append(asset)
        }
    }

    public func readArchiveSummaries(archiveRoot: URL) throws -> [ChatConversationArchiveSummary] {
        lock.lock()
        defer { lock.unlock() }
        return try withExclusiveLedgerLock {
            let document = try store.load()
            return try archiveReader.read(
                archiveRoot: archiveRoot,
                processedRevisions: effectiveProcessedRevisions(in: document)
            )
        }
    }

    public func createTask(
        jobId: String,
        selectedConversationIDs: [String],
        archiveRoot: URL
    ) throws -> ChatConversationProcessingTask {
        let normalizedJobID = try normalizedJobID(jobId)

        lock.lock()
        defer { lock.unlock() }
        return try withExclusiveLedgerLock {
            let taskURL = layout.chatConversationJobURL(jobId: normalizedJobID)
            guard !FileManager.default.fileExists(atPath: taskURL.path) else {
                throw ChatConversationLedgerError.taskAlreadyExists(normalizedJobID)
            }

            let document = try store.load()
            if let unfinalized = firstUnfinalizedReceipt(in: document) {
                throw ChatConversationLedgerError.pendingFinalization(unfinalized.jobId)
            }
            let summaries = try archiveReader.read(
                archiveRoot: archiveRoot,
                processedRevisions: effectiveProcessedRevisions(in: document)
            )
            let selectedIDs = Array(Set(selectedConversationIDs)).sorted()
            let selected = summaries.filter { selectedIDs.contains($0.conversationId) }
            let inputMessages = selected.flatMap(taskMessages(for:))
            guard inputMessages.contains(where: { !$0.contextOnly }) else {
                throw ChatConversationLedgerError.noPendingMessages
            }

            let task = ChatConversationProcessingTask(
                schemaVersion: 2,
                jobId: normalizedJobID,
                createdAt: timestamp(now()),
                selectedConversationIDs: selectedIDs,
                inputMessages: inputMessages,
                existingTopics: document.topics.map { ChatConversationTaskTopic(id: $0.id, name: $0.name) },
                existingAssets: document.assets.map { asset in
                    ChatConversationTaskAsset(
                        id: asset.id,
                        segmentId: asset.segmentId,
                        title: asset.title,
                        kind: asset.kind,
                        subtype: asset.subtype,
                        uses: asset.uses,
                        currentText: asset.currentVersion?.textSnapshot ?? "",
                        isUserLocked: asset.isUserLocked
                    )
                },
                sourceDigest: sourceDigest(for: inputMessages),
                baseLedgerDigest: try ledgerDigest(document)
            )
            try writeAtomically(task, to: taskURL)
            return task
        }
    }

    public func apply(_ proposal: ChatConversationProposal) throws -> ChatConversationReceipt {
        lock.lock()
        defer { lock.unlock() }
        return try withExclusiveLedgerLock {
            let task = try loadTask(jobId: proposal.jobId)
            var document = try store.load()
            let proposalDigest = try digest(proposal)
            if let existingIndex = document.receipts.firstIndex(where: { $0.jobId == task.jobId }) {
                let existing = document.receipts[existingIndex]
                guard existing.proposalDigest == proposalDigest else {
                    throw ChatConversationLedgerError.jobAlreadyRejected
                }
                switch existing.status {
                case .accepted:
                    try receiptWriter(existing, layout.chatConversationReceiptURL(jobId: existing.jobId))
                    return ChatConversationReceipt(
                        jobId: existing.jobId,
                        proposalDigest: existing.proposalDigest,
                        status: .noOp,
                        recordedAt: timestamp(now()),
                        reason: nil
                    )
                case .pending:
                    guard proposal.sourceDigest == task.sourceDigest else {
                        throw ChatConversationLedgerError.staleSource
                    }
                    return try finalizeAcceptance(
                        proposal,
                        task: task,
                        document: &document,
                        proposalDigest: proposalDigest,
                        receiptIndex: existingIndex
                    )
                case .rejected, .noOp:
                    throw ChatConversationLedgerError.jobAlreadyRejected
                }
            }
            guard proposal.sourceDigest == task.sourceDigest else { throw ChatConversationLedgerError.staleSource }
            guard proposal.baseLedgerDigest == task.baseLedgerDigest,
                  try ledgerDigest(document) == task.baseLedgerDigest else {
                throw ChatConversationLedgerError.staleLedger
            }
            try validate(proposal, against: task, document: document)

            document.receipts.append(ChatConversationReceipt(
                jobId: task.jobId,
                proposalDigest: proposalDigest,
                status: .pending,
                recordedAt: timestamp(now())
            ))
            document.updatedAt = timestamp(now())
            try store.save(document)
            return try finalizeAcceptance(
                proposal,
                task: task,
                document: &document,
                proposalDigest: proposalDigest,
                receiptIndex: document.receipts.index(before: document.receipts.endIndex)
            )
        }
    }

    public func renameTopic(id: String, name: String) throws -> ChatConversationLedgerDocument {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw ChatConversationLedgerError.emptyTopicName }
        return try updateDocument { document in
            guard let index = document.topics.firstIndex(where: { $0.id == id }) else {
                throw ChatConversationLedgerError.missingTopic(id)
            }
            document.topics[index].name = normalizedName
            document.topics[index].isUserLocked = true
        }
    }

    public func mergeTopic(id: String, intoTopicID: String) throws -> ChatConversationLedgerDocument {
        guard id != intoTopicID else { throw ChatConversationLedgerError.identicalTopicMerge }
        return try updateDocument { document in
            guard let sourceIndex = document.topics.firstIndex(where: { $0.id == id }) else {
                throw ChatConversationLedgerError.missingTopic(id)
            }
            guard let targetIndex = document.topics.firstIndex(where: { $0.id == intoTopicID }) else {
                throw ChatConversationLedgerError.missingTopic(intoTopicID)
            }
            document.topics[targetIndex].isUserLocked = true
            for index in document.segments.indices where document.segments[index].topicId == id {
                document.segments[index].topicId = intoTopicID
                document.segments[index].isUserLocked = true
            }
            document.topics.remove(at: sourceIndex)
        }
    }

    public func moveSegment(id: String, toTopicID: String) throws -> ChatConversationLedgerDocument {
        try updateDocument { document in
            guard document.topics.contains(where: { $0.id == toTopicID }) else {
                throw ChatConversationLedgerError.missingTopic(toTopicID)
            }
            guard let segmentIndex = document.segments.firstIndex(where: { $0.id == id }) else {
                throw ChatConversationLedgerError.missingSegment(id)
            }
            document.segments[segmentIndex].topicId = toTopicID
            document.segments[segmentIndex].isUserLocked = true
        }
    }

    public func setMark(
        assetID: String,
        isHighlighted: Bool,
        note: String?
    ) throws -> ChatConversationLedgerDocument {
        try updateDocument { document in
            guard let index = document.assets.firstIndex(where: { $0.id == assetID }) else {
                throw ChatConversationLedgerError.missingAsset(assetID)
            }
            let normalizedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            document.assets[index].isHighlighted = isHighlighted
            document.assets[index].note = normalizedNote
        }
    }

    public func reject(jobId: String, reason: String) throws -> ChatConversationReceipt {
        let normalizedJobID = try normalizedJobID(jobId)
        lock.lock()
        defer { lock.unlock() }
        return try withExclusiveLedgerLock {
            let task = try loadTask(jobId: normalizedJobID)
            var document = try store.load()
            if let existingIndex = document.receipts.firstIndex(where: { $0.jobId == normalizedJobID }) {
                let existing = document.receipts[existingIndex]
                if existing.status == .accepted {
                    throw ChatConversationLedgerError.jobAlreadyRejected
                }
                if existing.status == .rejected {
                    try receiptWriter(existing, layout.chatConversationReceiptURL(jobId: existing.jobId))
                    return existing
                }
                let receipt = ChatConversationReceipt(
                    jobId: task.jobId,
                    proposalDigest: existing.proposalDigest,
                    status: .rejected,
                    recordedAt: timestamp(now()),
                    reason: reason
                )
                document.receipts[existingIndex] = receipt
                document.updatedAt = timestamp(now())
                try store.save(document)
                try receiptWriter(receipt, layout.chatConversationReceiptURL(jobId: receipt.jobId))
                return receipt
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
            try receiptWriter(receipt, layout.chatConversationReceiptURL(jobId: receipt.jobId))
            return receipt
        }
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
        guard proposal.segments.flatMap(\.sourceMessages).allSatisfy({ input.contains($0) }),
              proposal.duplicateMatches.allSatisfy({ match in
                  !match.sourceBlockIDs.isEmpty &&
                  document.assets.contains(where: { $0.id == match.existingAssetId })
              }),
              proposal.ignoredMessages.allSatisfy({ !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ChatConversationLedgerError.invalidSourceReference
        }
        for asset in proposal.assets {
            guard proposal.segments.contains(where: { $0.id == asset.segmentId }) else {
                throw ChatConversationLedgerError.missingSegment(asset.segmentId)
            }
        }
        let newSegmentIDs = proposal.segments.map(\.id)
        let newAssetIDs = proposal.assets.map(\.id)
        guard Set(newSegmentIDs).count == newSegmentIDs.count,
              Set(newAssetIDs).count == newAssetIDs.count,
              !newSegmentIDs.contains(where: { segmentID in
                  document.segments.contains(where: { existing in existing.id == segmentID })
              }) else {
            throw ChatConversationLedgerError.duplicateRecordID
        }
        for asset in proposal.assets {
            if let replacesID = asset.replacesAssetID {
                guard let existing = document.assets.first(where: { $0.id == replacesID }) else {
                    throw ChatConversationLedgerError.missingAsset(replacesID)
                }
                if existing.isUserLocked {
                    throw ChatConversationLedgerError.lockedAsset(replacesID)
                }
            } else if document.assets.contains(where: { $0.id == asset.id }) {
                throw ChatConversationLedgerError.duplicateRecordID
            }
        }
        guard proposal.segments.allSatisfy({ segment in
            !segment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !segment.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            Set(segment.sourceMessages.map(\.conversationId)).count == 1
        }) else {
            throw ChatConversationLedgerError.invalidSourceReference
        }
        for target in proposal.segments.map(\.topicTarget) {
            switch target {
            case .existing(let id):
                guard document.topics.contains(where: { $0.id == id }) else {
                    throw ChatConversationLedgerError.invalidTopicTarget
                }
            case .new(let id, let name):
                guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !document.topics.contains(where: { $0.id == id }) else {
                    throw ChatConversationLedgerError.invalidTopicTarget
                }
            }
        }
        let proposedNewTopics = proposal.segments.map(\.topicTarget)
        for target in proposedNewTopics {
            guard case .new(let id, let name) = target else { continue }
            guard proposedNewTopics.allSatisfy({ candidate in
                guard case .new(let candidateID, let candidateName) = candidate else { return true }
                return candidateID != id || candidateName == name
            }) else {
                throw ChatConversationLedgerError.invalidTopicTarget
            }
        }
        let materializer = ChatStudyAssetMaterializer()
        for asset in proposal.assets {
            _ = try materializer.materialize(
                asset,
                task: task,
                createdAt: timestamp(now()),
                existingAsset: asset.replacesAssetID.flatMap { id in document.assets.first(where: { $0.id == id }) }
            )
        }
    }

    private func finalizeAcceptance(
        _ proposal: ChatConversationProposal,
        task: ChatConversationProcessingTask,
        document: inout ChatConversationLedgerDocument,
        proposalDigest: String,
        receiptIndex: Int
    ) throws -> ChatConversationReceipt {
        let receipt = ChatConversationReceipt(
            jobId: task.jobId,
            proposalDigest: proposalDigest,
            status: .accepted,
            recordedAt: timestamp(now())
        )

        var targetIDs: [ChatConversationTopicTarget: String] = [:]
        for target in proposal.segments.map(\.topicTarget) {
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
                title: segment.title,
                summary: segment.summary,
                sourceMessages: segment.sourceMessages
            ))
        }
        let materializer = ChatStudyAssetMaterializer()
        let createdAt = timestamp(now())
        for candidate in proposal.assets {
            let existing = candidate.replacesAssetID.flatMap { id in document.assets.first(where: { $0.id == id }) }
            let version = try materializer.materialize(
                candidate,
                task: task,
                createdAt: createdAt,
                existingAsset: existing
            )
            if let replacesID = candidate.replacesAssetID,
               let index = document.assets.firstIndex(where: { $0.id == replacesID }) {
                document.assets[index].versions.append(version)
                document.assets[index].currentVersionId = version.id
                document.assets[index].title = candidate.title
                document.assets[index].kind = candidate.kind
                document.assets[index].subtype = candidate.subtype
                document.assets[index].uses = candidate.uses
                if candidate.origin == .userEdited || candidate.origin == .userSelection {
                    document.assets[index].isUserLocked = true
                }
            } else {
                document.assets.append(ChatStudyAsset(
                    id: candidate.id,
                    segmentId: candidate.segmentId,
                    title: candidate.title,
                    kind: candidate.kind,
                    subtype: candidate.subtype,
                    uses: candidate.uses,
                    versions: [version],
                    currentVersionId: version.id,
                    isUserLocked: candidate.origin == .userSelection || candidate.origin == .userEdited
                ))
            }
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
        document.receipts[receiptIndex] = receipt
        document.updatedAt = timestamp(now())
        try store.save(document)
        try receiptWriter(receipt, layout.chatConversationReceiptURL(jobId: receipt.jobId))
        return receipt
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
        let task = try JSONDecoder().decode(ChatConversationProcessingTask.self, from: Data(contentsOf: url))
        guard task.jobId == normalizedJobID else {
            throw ChatConversationLedgerError.invalidJobId
        }
        return task
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

    private func withExclusiveLedgerLock<T>(_ operation: () throws -> T) throws -> T {
        try layout.ensureDirectories()
        let fileLock = try ChatConversationLedgerFileLock(
            url: layout.recordsDirectoryURL.appendingPathComponent("chatgpt-ledger.lock", isDirectory: false)
        )
        defer { fileLock.release() }
        return try operation()
    }

    private func updateDocument(
        _ update: (inout ChatConversationLedgerDocument) throws -> Void
    ) throws -> ChatConversationLedgerDocument {
        lock.lock()
        defer { lock.unlock() }
        return try withExclusiveLedgerLock {
            var document = try store.load()
            try update(&document)
            document.updatedAt = timestamp(now())
            try store.save(document)
            return document
        }
    }

    private func effectiveProcessedRevisions(
        in document: ChatConversationLedgerDocument
    ) -> [ChatConversationProcessedRevision] {
        let finalizedTaskIDs = Set(document.receipts.compactMap { receipt -> String? in
            guard receipt.status == .accepted, hasFinalizedReceipt(receipt) else { return nil }
            return receipt.jobId
        })
        return document.processedRevisions.filter { finalizedTaskIDs.contains($0.taskId) }
    }

    private func firstUnfinalizedReceipt(
        in document: ChatConversationLedgerDocument
    ) -> ChatConversationReceipt? {
        document.receipts.first(where: { !hasFinalizedReceipt($0) })
    }

    private func hasFinalizedReceipt(_ receipt: ChatConversationReceipt) -> Bool {
        guard receipt.status == .accepted || receipt.status == .rejected,
              let normalizedJobID = try? normalizedJobID(receipt.jobId),
              normalizedJobID == receipt.jobId,
              let data = try? Data(contentsOf: layout.chatConversationReceiptURL(jobId: normalizedJobID)),
              let onDisk = try? JSONDecoder().decode(ChatConversationReceipt.self, from: data) else {
            return false
        }
        return onDisk.jobId == receipt.jobId
            && onDisk.proposalDigest == receipt.proposalDigest
            && onDisk.status == receipt.status
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

    private static let defaultReceiptWriter: @Sendable (ChatConversationReceipt, URL) throws -> Void = { receipt, url in
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(receipt).write(to: url, options: .atomic)
    }
}

private final class ChatConversationLedgerFileLock {
    private var descriptor: Int32

    init(url: URL) throws {
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw ChatConversationLedgerFileLockError.openFailed }
        guard flock(descriptor, LOCK_EX) == 0 else {
            Darwin.close(descriptor)
            descriptor = -1
            throw ChatConversationLedgerFileLockError.lockFailed
        }
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}

private enum ChatConversationLedgerFileLockError: Error {
    case openFailed
    case lockFailed
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private struct LegacyCountProbe: Decodable {
    var topics: [LegacyCountItem]
    var segments: [LegacyCountItem]
    var findings: [LegacyCountItem]
    var processedRevisions: [LegacyCountItem]
    var receipts: [LegacyCountItem]
}

private struct LegacyCountItem: Decodable {}
