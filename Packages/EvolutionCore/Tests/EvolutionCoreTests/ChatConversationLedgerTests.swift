import Foundation
import XCTest
@testable import EvolutionCore

final class ChatConversationLedgerTests: XCTestCase {
    func testCreatesImmutableTaskForPendingMessagesAndAppliesProposalOnlyOnce() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(
            id: "conversation-1",
            messages: [
                fixture.message(id: "old-user", role: "user", content: "Old question"),
                fixture.message(id: "old-assistant", role: "assistant", content: "Old response"),
                fixture.message(id: "new-user", role: "user", content: "New question"),
                fixture.message(id: "new-assistant", role: "assistant", content: "New response"),
            ]
        )
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let store = JSONChatConversationLedgerStore(layout: layout)
        let previousReceipt = ChatConversationReceipt(
            jobId: "previous-job",
            proposalDigest: "previous-proposal",
            status: .accepted,
            recordedAt: "2026-07-01T00:00:00Z"
        )
        try store.save(ChatConversationLedgerDocument(
            processedRevisions: [
                ChatConversationProcessedRevision(
                    conversationId: "conversation-1",
                    messageId: "old-user",
                    contentHash: ContentHasher.hash("Old question"),
                    taskId: "previous-job"
                ),
                ChatConversationProcessedRevision(
                    conversationId: "conversation-1",
                    messageId: "old-assistant",
                    contentHash: ContentHasher.hash("Old response"),
                    taskId: "previous-job"
                ),
            ],
            receipts: [previousReceipt]
        ))
        try JSONEncoder().encode(previousReceipt).write(
            to: layout.chatConversationReceiptURL(jobId: previousReceipt.jobId),
            options: .atomic
        )
        let ledger = ChatConversationLedger(layout: layout)

        let task = try ledger.createTask(
            jobId: "job-1",
            selectedConversationIDs: ["conversation-1"],
            archiveRoot: fixture.rootURL
        )

        XCTAssertEqual(task.inputMessages.filter(\.contextOnly).map(\.messageId), ["old-user", "old-assistant"])
        XCTAssertEqual(task.inputMessages.filter { !$0.contextOnly }.map(\.messageId), ["new-user", "new-assistant"])
        XCTAssertFalse(task.inputMessages.first { $0.messageId == "new-assistant" }?.sourceBlocks.isEmpty ?? true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.chatConversationJobURL(jobId: "job-1").path))

        let proposal = proposal(for: task)
        let receipt = try ledger.apply(proposal)
        let repeatedReceipt = try ledger.apply(proposal)
        let document = try ledger.load()

        XCTAssertEqual(receipt.status, .accepted)
        XCTAssertEqual(repeatedReceipt.status, .noOp)
        XCTAssertEqual(document.topics.map(\.id), ["topic:planning"])
        XCTAssertEqual(document.segments.count, 1)
        XCTAssertEqual(document.segments.first?.title, "New planning segment")
        XCTAssertEqual(document.assets.count, 1)
        XCTAssertEqual(
            document.processedRevisions.map(\.messageId),
            ["old-user", "old-assistant", "new-user", "new-assistant"]
        )
    }

    func testRejectsIncompleteProposalAndRejectedTaskLeavesMessagesPending() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(
            id: "conversation-1",
            messages: [
                fixture.message(id: "message-1", role: "user", content: "One"),
                fixture.message(id: "message-2", role: "assistant", content: "Two"),
            ]
        )
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let ledger = ChatConversationLedger(layout: layout)
        let task = try ledger.createTask(jobId: "job-incomplete", selectedConversationIDs: ["conversation-1"], archiveRoot: fixture.rootURL)
        var invalid = proposal(for: task)
        invalid.segments[0].sourceMessages = [task.inputMessages[0].reference]

        XCTAssertThrowsError(try ledger.apply(invalid)) { error in
            XCTAssertEqual(error as? ChatConversationLedgerError, .incompleteInputCoverage)
        }
        XCTAssertTrue(try ledger.load().processedRevisions.isEmpty)

        let rejected = try ledger.reject(jobId: task.jobId, reason: "User declined this candidate")
        XCTAssertEqual(rejected.status, .rejected)
        XCTAssertTrue(try ledger.load().processedRevisions.isEmpty)
    }

    func testRejectsAssetWhoseSegmentIsMissing() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(
            id: "conversation-1",
            messages: [fixture.message(id: "message-1", role: "user", content: "One")]
        )
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let ledger = ChatConversationLedger(layout: layout)
        let task = try ledger.createTask(
            jobId: "job-missing-segment",
            selectedConversationIDs: ["conversation-1"],
            archiveRoot: fixture.rootURL
        )
        var invalid = proposal(for: task)
        invalid.assets[0].segmentId = "missing-segment"

        XCTAssertThrowsError(try ledger.apply(invalid)) { error in
            XCTAssertEqual(error as? ChatConversationLedgerError, .missingSegment("missing-segment"))
        }
        XCTAssertTrue(try ledger.load().processedRevisions.isEmpty)
    }

    func testRecoversMissingReceiptAndRejectsOldTaskWithoutChangingItsMessages() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(id: "conversation-1", messages: [fixture.message(id: "one", role: "user", content: "One")])
        try fixture.writeConversation(id: "conversation-2", messages: [fixture.message(id: "two", role: "user", content: "Two")])
        try fixture.writeManifest(conversationIDs: ["conversation-1", "conversation-2"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let ledger = ChatConversationLedger(layout: layout)
        let oldTask = try ledger.createTask(jobId: "job-old", selectedConversationIDs: ["conversation-1"], archiveRoot: fixture.rootURL)
        let currentTask = try ledger.createTask(jobId: "job-current", selectedConversationIDs: ["conversation-2"], archiveRoot: fixture.rootURL)

        _ = try ledger.apply(proposal(for: currentTask))
        try FileManager.default.removeItem(at: layout.chatConversationReceiptURL(jobId: currentTask.jobId))
        let recovered = try ledger.apply(proposal(for: currentTask))

        XCTAssertEqual(recovered.status, .noOp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.chatConversationReceiptURL(jobId: currentTask.jobId).path))
        XCTAssertThrowsError(try ledger.apply(proposal(for: oldTask))) { error in
            XCTAssertEqual(error as? ChatConversationLedgerError, .staleLedger)
        }
        XCTAssertEqual(try ledger.load().processedRevisions.map(\.messageId), ["two"])
    }

    func testApplyingToExistingLockedTopicPreservesUserControl() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(id: "conversation-1", messages: [fixture.message(id: "message-1", role: "user", content: "User message")])
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let store = JSONChatConversationLedgerStore(layout: layout)
        try store.save(ChatConversationLedgerDocument(topics: [
            ChatConversationTopic(id: "topic:locked", name: "User name", isUserLocked: true),
        ]))
        let ledger = ChatConversationLedger(layout: layout)
        let task = try ledger.createTask(jobId: "job-locked", selectedConversationIDs: ["conversation-1"], archiveRoot: fixture.rootURL)

        _ = try ledger.apply(proposal(for: task, topicTarget: .existing(id: "topic:locked")))

        XCTAssertEqual(try ledger.load().topics, [
            ChatConversationTopic(id: "topic:locked", name: "User name", isUserLocked: true),
        ])
    }

    func testDuplicateMatchMustReferenceAnExistingAssetAndDoesNotCreateAnotherOne() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(id: "conversation-1", messages: [fixture.message(id: "message-1", role: "user", content: "User message")])
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let store = JSONChatConversationLedgerStore(layout: layout)
        let source = ChatConversationMessageReference(conversationId: "old-conversation", messageId: "old-message")
        let version = ChatStudyAssetVersion(
            id: "asset:existing-v1",
            textSnapshot: "Existing asset",
            textHash: ContentHasher.hash("Existing asset"),
            preservation: .distilled,
            origin: .skill,
            sourceMessages: [source],
            sourceSpans: [],
            supersedesVersionId: nil,
            createdAt: "2026-07-01T00:00:00Z"
        )
        try store.save(ChatConversationLedgerDocument(
            topics: [ChatConversationTopic(id: "topic:existing", name: "Existing")],
            segments: [
                ChatConversationSegment(
                    id: "segment:existing",
                    conversationId: "old-conversation",
                    topicId: "topic:existing",
                    title: "Existing segment",
                    summary: "Existing summary",
                    sourceMessages: [source]
                ),
            ],
            assets: [
                ChatStudyAsset(
                    id: "asset:existing",
                    segmentId: "segment:existing",
                    title: "Existing",
                    kind: .viewpointKnowledge,
                    subtype: "历史结论",
                    uses: [.review],
                    versions: [version],
                    currentVersionId: version.id
                ),
            ]
        ))
        let ledger = ChatConversationLedger(layout: layout)
        let task = try ledger.createTask(jobId: "job-duplicate", selectedConversationIDs: ["conversation-1"], archiveRoot: fixture.rootURL)

        var invalid = proposal(for: task, topicTarget: .existing(id: "topic:existing"))
        invalid.duplicateMatches = [ChatConversationDuplicateAssetMatch(
            existingAssetId: "missing-asset",
            sourceBlockIDs: ["block-1"]
        )]
        XCTAssertThrowsError(try ledger.apply(invalid)) { error in
            XCTAssertEqual(error as? ChatConversationLedgerError, .invalidSourceReference)
        }

        var proposal = proposal(for: task, topicTarget: .existing(id: "topic:existing"))
        proposal.assets = []
        proposal.duplicateMatches = [ChatConversationDuplicateAssetMatch(
            existingAssetId: "asset:existing",
            sourceBlockIDs: ["block-1"]
        )]
        _ = try ledger.apply(proposal)

        XCTAssertEqual(
            try ledger.load().assets.map(\.id),
            ["asset:existing"],
            "The duplicate match is review-only; accepting it must not create a duplicate formal asset."
        )
    }

    func testRejectsUnsafeJobIDAndOnlyUsesUserAssistantContextInOrder() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(
            id: "conversation-1",
            messages: [
                fixture.message(id: "old-assistant", role: "assistant", content: "Old response"),
                fixture.message(id: "old-user", role: "user", content: "Old follow-up"),
                fixture.message(id: "new-user", role: "user", content: "New question"),
            ]
        )
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let ledger = ChatConversationLedger(layout: layout)

        XCTAssertThrowsError(try ledger.createTask(
            jobId: "../outside",
            selectedConversationIDs: ["conversation-1"],
            archiveRoot: fixture.rootURL
        )) { error in
            XCTAssertEqual(error as? ChatConversationLedgerError, .invalidJobId)
        }

        let task = try ledger.createTask(
            jobId: "job-safe",
            selectedConversationIDs: ["conversation-1"],
            archiveRoot: fixture.rootURL
        )
        XCTAssertTrue(task.inputMessages.allSatisfy { !$0.contextOnly })
    }

    func testReceiptWriteFailureLeavesMessagesPendingUntilRetryFinalizes() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(id: "conversation-1", messages: [fixture.message(id: "message-1", role: "user", content: "One")])
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let failingLedger = ChatConversationLedger(
            layout: layout,
            receiptWriter: { _, _ in throw ReceiptWriteFailure.failed }
        )
        let task = try failingLedger.createTask(jobId: "job-recover", selectedConversationIDs: ["conversation-1"], archiveRoot: fixture.rootURL)

        XCTAssertThrowsError(try failingLedger.apply(proposal(for: task)))

        let interrupted = try failingLedger.load()
        XCTAssertEqual(interrupted.receipts.map(\.status), [.accepted])
        XCTAssertEqual(interrupted.processedRevisions.map(\.messageId), ["message-1"])
        XCTAssertEqual(
            try failingLedger.readArchiveSummaries(archiveRoot: fixture.rootURL).first?.pendingMessageCount,
            1
        )
        XCTAssertThrowsError(try failingLedger.createTask(
            jobId: "job-blocked",
            selectedConversationIDs: ["conversation-1"],
            archiveRoot: fixture.rootURL
        )) { error in
            XCTAssertEqual(error as? ChatConversationLedgerError, .pendingFinalization("job-recover"))
        }

        let retried = try ChatConversationLedger(layout: layout).apply(proposal(for: task))
        XCTAssertEqual(retried.status, .noOp)
        XCTAssertEqual(
            try ChatConversationLedger(layout: layout).readArchiveSummaries(archiveRoot: fixture.rootURL).first?.processedMessageCount,
            1
        )
        XCTAssertEqual(try ChatConversationLedger(layout: layout).load().processedRevisions.map(\.messageId), ["message-1"])
    }

    func testFinalLedgerWriteFailureLeavesMessagesPendingUntilRetryFinalizes() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(id: "conversation-1", messages: [fixture.message(id: "message-1", role: "user", content: "One")])
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let store = FailingOnSecondSaveLedgerStore(layout: layout)
        let failingLedger = ChatConversationLedger(layout: layout, store: store)
        let task = try failingLedger.createTask(jobId: "job-final-save", selectedConversationIDs: ["conversation-1"], archiveRoot: fixture.rootURL)

        XCTAssertThrowsError(try failingLedger.apply(proposal(for: task)))

        let interrupted = try ChatConversationLedger(layout: layout).load()
        XCTAssertEqual(interrupted.receipts.map(\.status), [.pending])
        XCTAssertTrue(interrupted.processedRevisions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.chatConversationReceiptURL(jobId: task.jobId).path))
        XCTAssertEqual(
            try ChatConversationLedger(layout: layout).readArchiveSummaries(archiveRoot: fixture.rootURL).first?.pendingMessageCount,
            1
        )

        let retried = try ChatConversationLedger(layout: layout).apply(proposal(for: task))
        XCTAssertEqual(retried.status, .accepted)
        XCTAssertEqual(try ChatConversationLedger(layout: layout).load().processedRevisions.map(\.messageId), ["message-1"])
    }

    func testRejectsMultiConversationSegmentBeforePublishingAnyReceipt() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(id: "conversation-1", messages: [fixture.message(id: "message-1", role: "user", content: "One")])
        try fixture.writeConversation(id: "conversation-2", messages: [fixture.message(id: "message-2", role: "user", content: "Two")])
        try fixture.writeManifest(conversationIDs: ["conversation-1", "conversation-2"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let ledger = ChatConversationLedger(layout: layout)
        let task = try ledger.createTask(
            jobId: "job-multi-conversation",
            selectedConversationIDs: ["conversation-1", "conversation-2"],
            archiveRoot: fixture.rootURL
        )
        var invalid = proposal(for: task)
        invalid.segments[0].sourceMessages = task.inputMessages.map(\.reference)

        XCTAssertThrowsError(try ledger.apply(invalid)) { error in
            XCTAssertEqual(error as? ChatConversationLedgerError, .invalidSourceReference)
        }
        XCTAssertTrue(try ledger.load().receipts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.chatConversationReceiptURL(jobId: task.jobId).path))
    }

    func testRejectsTaskWhoseEmbeddedJobIDDoesNotMatchItsSafeFilename() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(id: "conversation-1", messages: [fixture.message(id: "message-1", role: "user", content: "One")])
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let ledger = ChatConversationLedger(layout: layout)
        let task = try ledger.createTask(
            jobId: "job-safe",
            selectedConversationIDs: ["conversation-1"],
            archiveRoot: fixture.rootURL
        )
        var tampered = task
        tampered.jobId = "../outside"
        try JSONEncoder().encode(tampered).write(
            to: layout.chatConversationJobURL(jobId: "job-safe"),
            options: .atomic
        )

        XCTAssertThrowsError(try ledger.apply(proposal(for: task))) { error in
            XCTAssertEqual(error as? ChatConversationLedgerError, .invalidJobId)
        }
        XCTAssertTrue(try ledger.load().receipts.isEmpty)
    }

    func testUserTopicSegmentAndAssetEditsPersistWithoutCandidateOverwrite() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let store = JSONChatConversationLedgerStore(layout: layout)
        let version = ChatStudyAssetVersion(
            id: "asset-1-v1",
            textSnapshot: "User-relevant asset",
            textHash: ContentHasher.hash("User-relevant asset"),
            preservation: .distilled,
            origin: .skill,
            sourceMessages: [ChatConversationMessageReference(conversationId: "conversation-1", messageId: "message-1")],
            sourceSpans: [],
            supersedesVersionId: nil,
            createdAt: "2026-07-01T00:00:00Z"
        )
        try store.save(ChatConversationLedgerDocument(
            topics: [
                ChatConversationTopic(id: "topic-a", name: "Candidate topic"),
                ChatConversationTopic(id: "topic-b", name: "Move target"),
                ChatConversationTopic(id: "topic-c", name: "Merge target"),
            ],
            segments: [
                ChatConversationSegment(
                    id: "segment-1",
                    conversationId: "conversation-1",
                    topicId: "topic-a",
                    title: "Segment title",
                    summary: "Segment summary",
                    sourceMessages: [ChatConversationMessageReference(conversationId: "conversation-1", messageId: "message-1")]
                )
            ],
            assets: [
                ChatStudyAsset(
                    id: "asset-1",
                    segmentId: "segment-1",
                    title: "Asset",
                    kind: .viewpointKnowledge,
                    subtype: "观点",
                    uses: [.review],
                    versions: [version],
                    currentVersionId: version.id
                )
            ]
        ))
        let ledger = ChatConversationLedger(layout: layout)

        _ = try ledger.renameTopic(id: "topic-a", name: "User name")
        _ = try ledger.moveSegment(id: "segment-1", toTopicID: "topic-b")
        _ = try ledger.setMark(assetID: "asset-1", isHighlighted: true, note: "Keep this")
        _ = try ledger.mergeTopic(id: "topic-b", intoTopicID: "topic-c")

        let reloaded = try ChatConversationLedger(layout: layout).load()
        XCTAssertEqual(reloaded.topics.map(\.id), ["topic-a", "topic-c"])
        XCTAssertEqual(reloaded.topics.first(where: { $0.id == "topic-a" }), ChatConversationTopic(id: "topic-a", name: "User name", isUserLocked: true))
        XCTAssertEqual(reloaded.segments.first?.topicId, "topic-c")
        XCTAssertTrue(reloaded.segments.first?.isUserLocked == true)
        XCTAssertEqual(reloaded.assets.first?.segmentId, "segment-1")
        XCTAssertEqual(reloaded.assets.first?.isHighlighted, true)
        XCTAssertEqual(reloaded.assets.first?.note, "Keep this")
    }

    func testRejectNormalizesJobIDAndRecoversMissingReceipt() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(id: "conversation-1", messages: [fixture.message(id: "message-1", role: "user", content: "One")])
        try fixture.writeManifest(conversationIDs: ["conversation-1"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let ledger = ChatConversationLedger(layout: layout)
        _ = try ledger.createTask(jobId: "job-rejected", selectedConversationIDs: ["conversation-1"], archiveRoot: fixture.rootURL)

        _ = try ledger.reject(jobId: "job-rejected", reason: "Declined")
        try FileManager.default.removeItem(at: layout.chatConversationReceiptURL(jobId: "job-rejected"))
        let repeated = try ledger.reject(jobId: " job-rejected ", reason: "Ignored on repeat")

        XCTAssertEqual(repeated.status, .rejected)
        XCTAssertEqual(try ledger.load().receipts.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.chatConversationReceiptURL(jobId: "job-rejected").path))
    }

    func testTwoLedgerInstancesDoNotAcceptConflictingTasks() throws {
        let fixture = try ChatLedgerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writeConversation(id: "conversation-1", messages: [fixture.message(id: "message-1", role: "user", content: "One")])
        try fixture.writeConversation(id: "conversation-2", messages: [fixture.message(id: "message-2", role: "user", content: "Two")])
        try fixture.writeManifest(conversationIDs: ["conversation-1", "conversation-2"])
        let layout = EvolutionLedgerLayout(rootURL: fixture.rootURL.appendingPathComponent("Personal Evolution"))
        let firstLedger = ChatConversationLedger(layout: layout)
        let secondLedger = ChatConversationLedger(layout: layout)
        let firstTask = try firstLedger.createTask(jobId: "job-first", selectedConversationIDs: ["conversation-1"], archiveRoot: fixture.rootURL)
        let secondTask = try secondLedger.createTask(jobId: "job-second", selectedConversationIDs: ["conversation-2"], archiveRoot: fixture.rootURL)
        let resultLock = NSLock()
        var results: [Result<ChatConversationReceipt, Error>] = []
        let finished = expectation(description: "both applies finish")
        finished.expectedFulfillmentCount = 2

        DispatchQueue.concurrentPerform(iterations: 2) { index in
            let result = Result {
                try (index == 0 ? firstLedger : secondLedger).apply(proposal(for: index == 0 ? firstTask : secondTask))
            }
            resultLock.lock()
            results.append(result)
            resultLock.unlock()
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertEqual(results.compactMap { try? $0.get() }.filter { $0.status == .accepted }.count, 1)
        XCTAssertEqual(results.compactMap { result -> ChatConversationLedgerError? in
            guard case .failure(let error) = result else { return nil }
            return error as? ChatConversationLedgerError
        }, [.staleLedger])
    }

    private func proposal(
        for task: ChatConversationProcessingTask,
        topicTarget: ChatConversationTopicTarget = .new(id: "topic:planning", name: "Planning")
    ) -> ChatConversationProposal {
        let selectedMessages = task.inputMessages.filter { !$0.contextOnly }
        let first = selectedMessages[0]
        let assistantBlocks = selectedMessages.first(where: { $0.role == .assistant })?.sourceBlocks ?? []
        let asset: ChatConversationProposalAsset
        if !assistantBlocks.isEmpty {
            asset = ChatConversationProposalAsset(
                id: "asset:1",
                segmentId: "segment:1",
                title: "A supported asset",
                kind: .finishedWork,
                subtype: "范文",
                uses: [.memorize],
                preservation: .verbatim,
                draftText: nil,
                sourceBlockIDs: assistantBlocks.map(\.id),
                sourceSpans: [],
                replacesAssetID: nil,
                origin: .skill
            )
        } else {
            asset = ChatConversationProposalAsset(
                id: "asset:1",
                segmentId: "segment:1",
                title: "A supported asset",
                kind: .viewpointKnowledge,
                subtype: "观点",
                uses: [.review],
                preservation: .distilled,
                draftText: "A supported finding",
                sourceBlockIDs: first.sourceBlocks.map(\.id),
                sourceSpans: [],
                replacesAssetID: nil,
                origin: .skill
            )
        }
        return ChatConversationProposal(
            jobId: task.jobId,
            sourceDigest: task.sourceDigest,
            baseLedgerDigest: task.baseLedgerDigest,
            segments: [
                ChatConversationProposalSegment(
                    id: "segment:1",
                    title: "New planning segment",
                    summary: "Covers the selected messages for this task.",
                    topicTarget: topicTarget,
                    sourceMessages: selectedMessages.map(\.reference)
                ),
            ],
            assets: [asset],
            ignoredMessages: []
        )
    }
}

private final class ChatLedgerFixture {
    let rootURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatConversationLedgerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func message(id: String, role: String, content: String) -> [String: String] {
        [
            "id": id,
            "role": role,
            "createdAt": "2026-07-02T00:00:00Z",
            "content": content,
        ]
    }

    func writeManifest(conversationIDs: [String]) throws {
        let manifest = Dictionary(uniqueKeysWithValues: conversationIDs.map { id in
            (id, [
                "createdAt": "2026-07-01T00:00:00Z",
                "lastActivityAt": "2026-07-02T00:00:00Z",
                "lastSnapshotFilename": "2026-07-01--\(id).md",
                "lastDataFilename": "data/conversations/\(id).json",
            ])
        })
        try writeJSON(manifest, to: rootURL.appendingPathComponent("_archive-index.json"))
    }

    func writeConversation(id: String, messages: [[String: String]]) throws {
        let fileURL = rootURL.appendingPathComponent("data/conversations/\(id).json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSON([
            "schemaVersion": 1,
            "conversationId": id,
            "title": id,
            "sourceURL": "https://chatgpt.com/c/\(id)",
            "createdAt": "2026-07-01T00:00:00Z",
            "updatedAt": "2026-07-02T00:00:00Z",
            "messages": messages,
        ], to: fileURL)
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: url)
    }
}

private enum ReceiptWriteFailure: Error {
    case failed
}

private final class FailingOnSecondSaveLedgerStore: ChatConversationLedgerDocumentStore, @unchecked Sendable {
    private let backing: JSONChatConversationLedgerStore
    private let lock = NSLock()
    private var saveCount = 0

    init(layout: EvolutionLedgerLayout) {
        backing = JSONChatConversationLedgerStore(layout: layout)
    }

    func load() throws -> ChatConversationLedgerDocument {
        try backing.load()
    }

    func save(_ document: ChatConversationLedgerDocument) throws {
        lock.lock()
        saveCount += 1
        let shouldFail = saveCount == 2
        lock.unlock()
        if shouldFail { throw ReceiptWriteFailure.failed }
        try backing.save(document)
    }
}
