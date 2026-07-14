import XCTest
@testable import EvolutionCore

final class LinkingAndReviewTests: XCTestCase {
    func testCwdMappingAutoLinks() {
        let entry = TimelineEntryLike(
            id: "e1",
            projectId: "p1",
            projectName: "TimeLedger",
            startAt: ISO8601Codec.date(from: "2026-07-12T01:00:00Z")!,
            endAt: ISO8601Codec.date(from: "2026-07-12T03:00:00Z")!
        )
        let event = ContextEvent(
            id: "c1",
            source: .codex,
            threadId: "t1",
            startedAt: ISO8601Codec.date(from: "2026-07-12T01:30:00Z")!,
            endedAt: ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!,
            title: "Work",
            projectHint: "TimeLedger"
        )
        let result = LinkingEngine.suggest(
            entries: [entry],
            events: [event],
            existingLinks: [],
            cwdMappings: ["/Users/x/TimeLedger": "p1"]
        )
        XCTAssertEqual(result.auto.count, 1)
        XCTAssertEqual(result.auto[0].userState, .confirmed)
    }

    func testManualLinkNotOverwritten() {
        let entry = TimelineEntryLike(
            id: "e1", projectId: "p1", projectName: "A",
            startAt: ISO8601Codec.date(from: "2026-07-12T01:00:00Z")!,
            endAt: ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!
        )
        let event = ContextEvent(
            id: "c1", source: .chatgpt, threadId: "t",
            startedAt: ISO8601Codec.date(from: "2026-07-12T01:10:00Z")!,
            title: "x"
        )
        let locked = EvidenceLink(
            timeEntryId: "e1",
            contextEventId: "c1",
            method: .manual,
            confidence: 1,
            userState: .confirmed
        )
        let result = LinkingEngine.suggest(entries: [entry], events: [event], existingLinks: [locked])
        XCTAssertTrue(result.auto.isEmpty)
        XCTAssertTrue(result.suggested.isEmpty)
        XCTAssertTrue(result.inboxEventIds.isEmpty)
    }

    func testSyncMergerIdempotentAndConflict() {
        let env1 = AnySyncEnvelope(
            deviceId: "phone",
            entityType: .timeEntry,
            entityId: "e1",
            revision: 1,
            updatedAt: ISO8601Codec.date(from: "2026-07-12T01:00:00Z")!,
            payloadJSON: "{}"
        )
        let env2 = AnySyncEnvelope(
            deviceId: "phone",
            entityType: .timeEntry,
            entityId: "e1",
            revision: 1,
            updatedAt: ISO8601Codec.date(from: "2026-07-12T01:00:00Z")!,
            payloadJSON: "{}"
        )
        let first = SyncMerger.apply(envelopes: [env1], existing: [:])
        XCTAssertEqual(first.accepted.count, 1)
        let second = SyncMerger.apply(envelopes: [env2], existing: first.nextState)
        // same revision + same updatedAt → not accepted (not greater)
        XCTAssertEqual(second.accepted.count, 0)

        let higher = AnySyncEnvelope(
            deviceId: "phone",
            entityType: .timeEntry,
            entityId: "e1",
            revision: 2,
            updatedAt: ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!,
            payloadJSON: "{}"
        )
        let third = SyncMerger.apply(envelopes: [higher], existing: second.nextState)
        XCTAssertEqual(third.accepted.count, 1)
    }

    func testDeterministicReviewWithoutAI() async throws {
        let package = DailyContextPackage(
            dateKey: "2026-07-12",
            entries: [
                TimelineEntryLike(
                    id: "e1", projectId: "p", projectName: "TimeLedger",
                    startAt: ISO8601Codec.date(from: "2026-07-12T01:00:00Z")!,
                    endAt: ISO8601Codec.date(from: "2026-07-12T03:00:00Z")!
                )
            ],
            thoughtBodies: ["先做闭环"],
            events: [
                ContextEvent(
                    id: "ev1", source: .codex, threadId: "t",
                    startedAt: ISO8601Codec.date(from: "2026-07-12T01:30:00Z")!,
                    title: "Hub work"
                )
            ],
            links: [
                EvidenceLink(
                    timeEntryId: "e1", contextEventId: "ev1",
                    method: .cwdMapping, confidence: 0.95, userState: .confirmed
                )
            ],
            gitEvidence: [
                GitEvidenceSummary(
                    repoPath: "/tmp/x",
                    commitHash: "abcdef123456",
                    commitMessage: "feat: hub"
                )
            ],
            yesterdayAdjustment: "TimeLedger"
        )
        let draft = try await DeterministicReviewProvider().createDraft(from: package)
        XCTAssertTrue(draft.deterministicMarkdown.contains("今日主要投入"))
        XCTAssertTrue(draft.verifiedOutputs.contains { $0.level == .verified })
        XCTAssertFalse(draft.mainFocus.isEmpty)
    }
}
