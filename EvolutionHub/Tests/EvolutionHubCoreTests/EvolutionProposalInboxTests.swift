import EvolutionCore
@testable import EvolutionHubCore
import Foundation
import XCTest

final class EvolutionProposalInboxTests: XCTestCase {
    func testTrustedPackageImportsWritesReceiptAndMovesProposal() throws {
        let fixture = try InboxTestFixture()
        let inbox = EvolutionProposalInbox(layout: fixture.layout, ledger: fixture.ledger)

        let receipts = try inbox.importPending()

        XCTAssertEqual(receipts.map(\.status), [.imported])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.inboxURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.processedURL.path))
        let storedReceipt = try ISO8601Codec.decoder.decode(
            ImportReceipt.self,
            from: Data(contentsOf: fixture.receiptURL)
        )
        XCTAssertEqual(storedReceipt.status, .imported)
        XCTAssertEqual(try fixture.ledger.read(.all).days.map(\.date), [fixture.dateKey])
    }

    func testTamperedEvidenceIsRejectedWithoutChangingLedger() throws {
        let fixture = try InboxTestFixture()
        var bundle = fixture.bundle
        bundle.sourceDigest = "tampered"
        bundle.contentHash = bundle.recomputedContentHash()
        try ISO8601Codec.encoder.encode(bundle).write(to: fixture.evidenceURL, options: .atomic)

        let before = try fixture.ledger.read(.all)
        let receipts = try EvolutionProposalInbox(layout: fixture.layout, ledger: fixture.ledger).importPending()

        XCTAssertEqual(receipts.map(\.status), [.rejected])
        XCTAssertFalse(try XCTUnwrap(receipts.first).errors.isEmpty)
        XCTAssertEqual(try fixture.ledger.read(.all), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.processedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.evidenceURL.path))
    }

    func testEveryEvidenceTrustBoundaryRejectsBeforeLedgerMutation() throws {
        let mutations: [(inout EvidenceBundle) -> Void] = [
            { bundle in
                bundle.jobId = "different-job"
                bundle.contentHash = bundle.recomputedContentHash()
            },
            { bundle in
                bundle.schemaVersion = EvolutionSchema.current + 1
                bundle.contentHash = bundle.recomputedContentHash()
            },
            { bundle in
                bundle.contentHash = "stale-content-hash"
            },
        ]

        for mutate in mutations {
            let fixture = try InboxTestFixture()
            var bundle = fixture.bundle
            mutate(&bundle)
            try ISO8601Codec.encoder.encode(bundle).write(to: fixture.evidenceURL, options: .atomic)
            let before = try fixture.ledger.read(.all)

            let receipt = try XCTUnwrap(
                EvolutionProposalInbox(layout: fixture.layout, ledger: fixture.ledger)
                    .importPending()
                    .first
            )

            XCTAssertEqual(receipt.status, .rejected)
            XCTAssertFalse(receipt.errors.isEmpty)
            XCTAssertEqual(try fixture.ledger.read(.all), before)
        }
    }

    func testProposalSessionsMustExactlyMatchTrustedEvidence() throws {
        let fixture = try InboxTestFixture()
        var proposal = fixture.proposal
        proposal.sessions[0].title = "伪造的会话标题"
        try ISO8601Codec.encoder.encode(proposal).write(to: fixture.inboxURL, options: .atomic)
        let before = try fixture.ledger.read(.all)

        let receipt = try XCTUnwrap(
            EvolutionProposalInbox(layout: fixture.layout, ledger: fixture.ledger)
                .importPending()
                .first
        )

        XCTAssertEqual(receipt.status, .rejected)
        XCTAssertTrue(receipt.errors.first?.contains("sessions mismatch") == true)
        XCTAssertEqual(try fixture.ledger.read(.all), before)
    }

    func testProposalWorktreesMustExactlyMatchTrustedEvidence() throws {
        let fixture = try InboxTestFixture()
        let capturedAt = fixture.proposal.createdAt
        var bundle = fixture.bundle
        bundle.worktrees = [inboxTestWorktree(branch: "trusted", capturedAt: capturedAt)]
        bundle.contentHash = bundle.recomputedContentHash()
        try ISO8601Codec.encoder.encode(bundle).write(to: fixture.evidenceURL, options: .atomic)

        var proposal = fixture.proposal
        proposal.worktreeEvidence = [inboxTestWorktree(branch: "invented", capturedAt: capturedAt)]
        try ISO8601Codec.encoder.encode(proposal).write(to: fixture.inboxURL, options: .atomic)
        let before = try fixture.ledger.read(.all)

        let receipt = try XCTUnwrap(
            EvolutionProposalInbox(layout: fixture.layout, ledger: fixture.ledger)
                .importPending()
                .first
        )

        XCTAssertEqual(receipt.status, .rejected)
        XCTAssertTrue(receipt.errors.first?.contains("worktrees mismatch") == true)
        XCTAssertEqual(try fixture.ledger.read(.all), before)
    }

    func testFilenameAndProposalJobMismatchIsRejected() throws {
        let fixture = try InboxTestFixture()
        let mismatchedURL = fixture.layout.inboxDirectoryURL.appendingPathComponent("different-job.json")
        try FileManager.default.moveItem(at: fixture.inboxURL, to: mismatchedURL)

        let receipt = try XCTUnwrap(
            EvolutionProposalInbox(layout: fixture.layout, ledger: fixture.ledger)
                .importPending()
                .first
        )

        XCTAssertEqual(receipt.status, .rejected)
        XCTAssertTrue(receipt.errors.first?.contains("jobId mismatch") == true)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.layout.processedDirectoryURL.appendingPathComponent("different-job.json").path
            )
        )
        XCTAssertTrue(try fixture.ledger.read(.all).days.isEmpty)
    }

    func testProposalDigestUsesExactRawBytes() throws {
        let fixture = try InboxTestFixture()
        let original = try Data(contentsOf: fixture.inboxURL)
        var withTrailingWhitespace = original
        withTrailingWhitespace.append(contentsOf: Data(" \n".utf8))

        XCTAssertNotEqual(
            EvolutionProposalInbox.proposalDigest(for: original),
            EvolutionProposalInbox.proposalDigest(for: withTrailingWhitespace)
        )
    }

    func testLedgerWrittenBeforeMoveRecoversAsNoOp() throws {
        let fixture = try InboxTestFixture()
        let rawProposal = try Data(contentsOf: fixture.inboxURL)
        let digest = EvolutionProposalInbox.proposalDigest(for: rawProposal)
        XCTAssertEqual(try fixture.ledger.apply(fixture.proposal, proposalDigest: digest).status, .imported)

        let receipts = try EvolutionProposalInbox(layout: fixture.layout, ledger: fixture.ledger).importPending()

        XCTAssertEqual(receipts.map(\.status), [.noOp])
        XCTAssertEqual(try fixture.ledger.read(.all).days.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.inboxURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.processedURL.path))
    }

    func testTemporaryFilesAreIgnoredAndIdenticalProcessedBytesCloseIdempotently() throws {
        let fixture = try InboxTestFixture()
        let temporary = fixture.layout.inboxDirectoryURL.appendingPathComponent("ignored.tmp")
        try Data("not json".utf8).write(to: temporary)
        let importer = EvolutionProposalInbox(layout: fixture.layout, ledger: fixture.ledger)
        XCTAssertEqual(try importer.importPending().map(\.status), [.imported])

        let processedBytes = try Data(contentsOf: fixture.processedURL)
        try processedBytes.write(to: fixture.inboxURL)
        let receipts = try importer.importPending()

        XCTAssertEqual(receipts.map(\.status), [.noOp])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.inboxURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.processedURL), processedBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporary.path))
    }

    func testDifferentProcessedBytesAreNeverOverwritten() throws {
        let fixture = try InboxTestFixture()
        try Data("different".utf8).write(to: fixture.processedURL)
        let ledgerBefore = try fixture.ledger.read(.all)

        XCTAssertThrowsError(
            try EvolutionProposalInbox(layout: fixture.layout, ledger: fixture.ledger).importPending()
        ) { error in
            guard case EvolutionProposalInboxError.processedConflict(let jobId) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(jobId, fixture.jobId)
        }
        XCTAssertEqual(try fixture.ledger.read(.all), ledgerBefore)
        XCTAssertEqual(try Data(contentsOf: fixture.processedURL), Data("different".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.inboxURL.path))
    }
}

struct InboxTestFixture {
    let root: URL
    let layout: EvolutionLedgerLayout
    let ledger: EvolutionLedger
    let jobId = "job-trusted"
    let dateKey = "2026-07-17"
    let cutoffAt = ISO8601Codec.date(from: "2026-07-17T15:00:00Z")!
    let proposal: EvolutionProposalEnvelope
    let bundle: EvidenceBundle

    var inboxURL: URL { layout.inboxDirectoryURL.appendingPathComponent("\(jobId).json") }
    var processedURL: URL { layout.processedDirectoryURL.appendingPathComponent("\(jobId).json") }
    var jobDirectoryURL: URL { layout.jobsDirectoryURL.appendingPathComponent(jobId, isDirectory: true) }
    var evidenceURL: URL { jobDirectoryURL.appendingPathComponent("evidence.json") }
    var receiptURL: URL { jobDirectoryURL.appendingPathComponent("receipt.json") }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvolutionProposalInboxTests-\(UUID().uuidString)", isDirectory: true)
        layout = EvolutionLedgerLayout(rootURL: root)
        try layout.ensureDirectories()

        let archiveDirectory = root.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let eventsURL = archiveDirectory.appendingPathComponent("events.jsonl")
        let threadsURL = archiveDirectory.appendingPathComponent("threads.jsonl")
        try Data(#"{"event_id":"event-1","thread_id":"thread-1","created_at":"2026-07-17T10:00:00Z","role":"user","text":"记录当天工作","source_file":"events.jsonl","source_line":1}"#.utf8).write(to: eventsURL)
        try Data(#"{"thread_id":"thread-1","title":"可信会话","cwd":"/tmp/project","created_at":"2026-07-17T09:00:00Z","updated_at":"2026-07-17T10:00:00Z"}"#.utf8).write(to: threadsURL)

        let location = SourceArchiveLocation(
            source: .codex,
            eventsPath: eventsURL.path,
            threadsPath: threadsURL.path
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let requestedDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17))!
        let prepared = try ArchiveEvidenceReader().prepareDay(
            location: location,
            date: requestedDate,
            cutoffAt: cutoffAt,
            calendar: calendar,
            processorThreadIds: []
        )
        let generatedAt = ISO8601Codec.date(from: "2026-07-17T15:01:00Z")!
        let day = WorkEvolutionDayRecord(
            date: dateKey,
            sourceCutoffAt: cutoffAt,
            projectSlices: [],
            independentThoughts: [],
            sourceSlices: prepared.slices,
            coverage: prepared.coverage,
            reviewState: .candidate,
            generatedAt: generatedAt,
            updatedAt: generatedAt
        )
        let sourceDigest = EvolutionSourceDigest.make(sourceCutoffAt: cutoffAt, days: [day])
        proposal = EvolutionProposalEnvelope(
            jobId: jobId,
            scope: EvolutionProposalScope(kind: .day, dates: [dateKey]),
            createdAt: generatedAt,
            sourceCutoffAt: cutoffAt,
            sourceDigest: sourceDigest,
            sessions: prepared.sessions,
            days: [day],
            projects: [],
            nodes: [],
            worktreeEvidence: [],
            userAnnotations: [],
            diagnostics: []
        )
        let request = EvolutionPrepareRequest(
            date: dateKey,
            timeZoneIdentifier: "Asia/Taipei",
            cutoffAt: cutoffAt,
            archives: [location],
            explicitProcessorThreadIds: []
        )
        var evidence = EvidenceBundle(
            jobId: jobId,
            request: request,
            archiveDays: [prepared],
            worktrees: [],
            diagnostics: [],
            sourceDigest: sourceDigest,
            contentHash: ""
        )
        evidence.contentHash = evidence.recomputedContentHash()
        bundle = evidence

        let jobDirectory = layout.jobsDirectoryURL.appendingPathComponent(jobId, isDirectory: true)
        try FileManager.default.createDirectory(at: jobDirectory, withIntermediateDirectories: true)
        try ISO8601Codec.encoder.encode(proposal).write(
            to: layout.inboxDirectoryURL.appendingPathComponent("\(jobId).json"),
            options: .atomic
        )
        try ISO8601Codec.encoder.encode(bundle).write(
            to: jobDirectory.appendingPathComponent("evidence.json"),
            options: .atomic
        )
        ledger = EvolutionLedger(store: JSONEvolutionDocumentStore(layout: layout))
    }
}

private func inboxTestWorktree(branch: String, capturedAt: Date) -> WorktreeEvidenceSnapshot {
    let repoPath = "/tmp/trusted-evidence"
    let head = String(repeating: "a", count: 40)
    let status = EvidenceVerificationStatus.verified
    let id = EvolutionStableID.worktree(
        repoPath: repoPath,
        branch: branch,
        head: head,
        verificationStatus: status,
        limitation: nil,
        sortedChanges: [],
        sortedChecks: [],
        sortedCommits: []
    )
    let contentHash = EvolutionStableID.worktreeContentHash(
        repoPath: repoPath,
        branch: branch,
        head: head,
        verificationStatus: status,
        limitation: nil,
        sortedChanges: [],
        sortedChecks: [],
        sortedCommits: []
    )
    return WorktreeEvidenceSnapshot(
        id: id,
        repoPath: repoPath,
        branch: branch,
        head: head,
        capturedAt: capturedAt,
        relevantCommits: [],
        changes: [],
        checks: [],
        verificationStatus: status,
        limitation: nil,
        contentHash: contentHash
    )
}
