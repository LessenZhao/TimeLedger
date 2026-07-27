import XCTest
@testable import EvolutionCore

final class DTOCodingTests: XCTestCase {
    func testContextThreadRoundTrip() throws {
        let original = ContextThread(
            source: .codex,
            externalId: "thread-1",
            title: "Fix tests",
            createdAt: date("2026-07-12T01:00:00.000+08:00"),
            updatedAt: date("2026-07-12T03:00:00.000+08:00"),
            cwd: "/Users/lessen/coding/test/TimeLedger",
            projectHint: "TimeLedger",
            rawPath: "raw/codex/views/a.md",
            contentHash: ContentHasher.hash("body"),
            importedAt: date("2026-07-12T04:00:00.000+08:00")
        )

        let data = try ISO8601Codec.encoder.encode(original)
        let decoded = try ISO8601Codec.decoder.decode(ContextThread.self, from: data)

        XCTAssertEqual(decoded.externalId, original.externalId)
        XCTAssertEqual(decoded.source, .codex)
        XCTAssertEqual(decoded.schemaVersion, EvolutionSchema.current)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, original.createdAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testContextMessageAndEventRoundTrip() throws {
        let message = ContextMessage(
            threadId: "t1",
            externalId: "msg-1",
            role: .user,
            createdAt: date("2026-07-12T02:00:00Z"),
            text: "hello",
            contentHash: ContentHasher.hash("hello")
        )
        let event = ContextEvent(
            source: .claude,
            threadId: "t1",
            startedAt: date("2026-07-12T02:00:00Z"),
            endedAt: date("2026-07-12T02:30:00Z"),
            title: "Session",
            summary: "Discussed API",
            rawReference: "raw/claude/events.jsonl"
        )

        let messageDecoded = try roundTrip(message)
        let eventDecoded = try roundTrip(event)
        XCTAssertEqual(messageDecoded.role, .user)
        XCTAssertEqual(eventDecoded.source, .claude)
        XCTAssertEqual(eventDecoded.schemaVersion, 1)
    }

    func testEvidenceLinkAndDailyReviewRoundTrip() throws {
        let link = EvidenceLink(
            timeEntryId: "te-1",
            contextEventId: "ce-1",
            method: .cwdMapping,
            confidence: 0.95,
            userState: .suggested
        )
        let review = DailyReview(
            date: "2026-07-12",
            mainFocus: "TimeLedger V3",
            nextAdjustment: "Ship V3.0 only",
            evidenceIds: ["ce-1"],
            status: .draft
        )

        XCTAssertEqual(try roundTrip(link).confidence, 0.95, accuracy: 0.0001)
        XCTAssertEqual(try roundTrip(review).date, "2026-07-12")
        XCTAssertTrue(EvidenceLink(
            timeEntryId: "a",
            contextEventId: "b",
            method: .manual,
            confidence: 1,
            userState: .confirmed
        ).isUserLocked)
    }

    func testCollectorRequestResultRoundTrip() throws {
        let request = CollectorRequest(
            source: .chatgpt,
            startAt: date("2026-07-12T00:00:00+08:00"),
            endAt: date("2026-07-13T00:00:00+08:00"),
            outputRoot: "/tmp/pee/raw/chatgpt",
            mode: .incremental,
            requestId: "req-1"
        )
        let result = CollectorResult(
            requestId: "req-1",
            source: .chatgpt,
            status: .waitingForBrowser,
            startedAt: date("2026-07-12T10:00:00+08:00"),
            finishedAt: date("2026-07-12T10:00:01+08:00"),
            warnings: ["browser offline"]
        )

        XCTAssertEqual(try roundTrip(request).source, .chatgpt)
        let decoded = try roundTrip(result)
        XCTAssertTrue(decoded.isNonBlockingWait)
        XCTAssertFalse(decoded.isBlockingFailure)
    }

    func testSchemaVersionConstant() {
        XCTAssertEqual(EvolutionSchema.current, 1)
        XCTAssertEqual(EvolutionSchema.protocolVersion, "1.0")
    }

    func testChatConversationProposalDecodesLegacyCandidateWithoutDuplicateMatches() throws {
        let legacy = """
        {
          "jobId": "job-1",
          "sourceDigest": "source",
          "baseLedgerDigest": "ledger",
          "segments": [],
          "findings": [],
          "ignoredMessages": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ChatConversationProposal.self, from: legacy)
        XCTAssertTrue(decoded.duplicateMatches.isEmpty)

        let proposal = ChatConversationProposal(
            jobId: "job-2",
            sourceDigest: "source",
            baseLedgerDigest: "ledger",
            segments: [],
            findings: [],
            duplicateMatches: [ChatConversationDuplicateMatch(
                existingFindingId: "finding-existing",
                sourceMessages: [ChatConversationMessageReference(conversationId: "conversation-1", messageId: "message-1")]
            )],
            ignoredMessages: []
        )
        XCTAssertEqual(try roundTrip(proposal).duplicateMatches, proposal.duplicateMatches)
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let data = try ISO8601Codec.encoder.encode(value)
        return try ISO8601Codec.decoder.decode(T.self, from: data)
    }

    private func date(_ iso: String) -> Date {
        guard let value = ISO8601Codec.date(from: iso) else {
            XCTFail("bad date \(iso)")
            return Date()
        }
        return value
    }
}
