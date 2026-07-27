import EvolutionCore
@testable import EvolutionHubCore
import Foundation
import XCTest

final class ChatConversationProposalInboxTests: XCTestCase {
    func testReadsOnlyMatchingFinalProposalFilesWithoutMutatingLedger() throws {
        let fixture = try ChatProposalInboxFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let proposal = fixture.proposal(jobId: "job-1")
        try fixture.write(proposal, named: "job-1.json")
        try fixture.write(proposal, named: "job-1.json.tmp")

        let inbox = ChatConversationProposalInbox(layout: fixture.layout)
        let candidates = try inbox.readPending()

        XCTAssertEqual(candidates, [proposal])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.layout.chatConversationLedgerFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.layout.chatConversationProposalInboxDirectoryURL.appendingPathComponent("job-1.json").path))
    }

    func testRejectsProposalWhoseFilenameAndJobIDDoNotMatch() throws {
        let fixture = try ChatProposalInboxFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.write(fixture.proposal(jobId: "different-job"), named: "job-1.json")

        XCTAssertThrowsError(try ChatConversationProposalInbox(layout: fixture.layout).readPending()) { error in
            XCTAssertEqual(error as? ChatConversationProposalInboxError, .jobIdMismatch(filename: "job-1", proposal: "different-job"))
        }
    }

    func testRejectsDiskCandidateWithUserOriginOrSourceSpans() throws {
        let fixture = try ChatProposalInboxFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var proposal = fixture.proposal(jobId: "job-bad")
        proposal.assets = [
            ChatConversationProposalAsset(
                id: "asset-1",
                segmentId: "segment-1",
                title: "t",
                kind: .finishedWork,
                subtype: "范文",
                uses: [.memorize],
                preservation: .verbatim,
                draftText: nil,
                sourceBlockIDs: ["b1"],
                sourceSpans: [
                    ChatConversationSourceSpan(
                        message: ChatConversationMessageReference(conversationId: "c", messageId: "m"),
                        contentHash: "h",
                        locationUTF16: 0,
                        lengthUTF16: 1,
                        textHash: "t"
                    ),
                ],
                replacesAssetID: nil,
                origin: .userSelection
            ),
        ]
        try fixture.write(proposal, named: "job-bad.json")

        XCTAssertThrowsError(try ChatConversationProposalInbox(layout: fixture.layout).readPending()) { error in
            XCTAssertEqual(
                error as? ChatConversationProposalInboxError,
                .disallowedDiskCandidate("disk candidate origin must be skill: asset-1")
            )
        }
    }
}

private struct ChatProposalInboxFixture {
    let root: URL
    let layout: EvolutionLedgerLayout

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatConversationProposalInboxTests-\(UUID().uuidString)", isDirectory: true)
        layout = EvolutionLedgerLayout(rootURL: root.appendingPathComponent("Personal Evolution", isDirectory: true))
        try layout.ensureDirectories()
    }

    func proposal(jobId: String) -> ChatConversationProposal {
        ChatConversationProposal(
            jobId: jobId,
            sourceDigest: "source",
            baseLedgerDigest: "ledger",
            segments: [
                ChatConversationProposalSegment(
                    id: "segment-1",
                    title: "Segment",
                    summary: "Summary",
                    topicTarget: .new(id: "topic-1", name: "Topic"),
                    sourceMessages: [ChatConversationMessageReference(conversationId: "conversation-1", messageId: "message-1")]
                )
            ],
            assets: [],
            ignoredMessages: []
        )
    }

    func write(_ proposal: ChatConversationProposal, named filename: String) throws {
        try JSONEncoder().encode(proposal).write(
            to: layout.chatConversationProposalInboxDirectoryURL.appendingPathComponent(filename),
            options: .atomic
        )
    }
}
