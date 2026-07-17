import EvolutionCore
@testable import EvolutionHubCore
import Foundation
import XCTest

final class WorkEvolutionHubStoreTests: XCTestCase {
    @MainActor
    func testRefreshUserAnnotationAndConfirmationSurviveStoreRestart() async throws {
        let fixture = try InboxTestFixture()
        let now = ISO8601Codec.date(from: "2026-07-18T02:03:04Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        var store: WorkEvolutionHubStore? = WorkEvolutionHubStore(
            layout: fixture.layout,
            calendar: calendar,
            now: { now }
        )

        await store?.refresh()
        XCTAssertEqual(store?.snapshot.days.map(\.date), [fixture.dateKey])
        XCTAssertEqual(store?.receipts.map(\.status), [.imported])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.layout.dailyMapsDirectoryURL
                    .appendingPathComponent("\(fixture.dateKey).md")
                    .path
            )
        )
        try store?.addAnnotation(
            target: AnnotationTarget(kind: .day, targetId: fixture.dateKey),
            kind: .supplement,
            body: "  我补充的判断  "
        )
        try store?.confirmDay(fixture.dateKey)
        store = nil

        let restarted = WorkEvolutionHubStore(
            layout: fixture.layout,
            calendar: calendar,
            now: { now }
        )
        await restarted.refresh()

        XCTAssertEqual(restarted.snapshot.annotations.map(\.body), ["我补充的判断"])
        XCTAssertEqual(restarted.snapshot.annotations.first?.recognizedAt, now)
        XCTAssertEqual(restarted.snapshot.days.first?.reviewState, .confirmed)
        XCTAssertEqual(WorkEvolutionHubStore.dayKey(for: restarted.selectedDay, calendar: calendar), "2026-07-18")
        let dailyMap = try String(
            contentsOf: fixture.layout.dailyMapsDirectoryURL
                .appendingPathComponent("2026-07-18.md"),
            encoding: .utf8
        )
        XCTAssertTrue(dailyMap.contains("我补充的判断"))
    }

    @MainActor
    func testConversationReadsCanonicalFullSessionFromSelectedSnapshot() async throws {
        let fixture = try InboxTestFixture()
        let store = WorkEvolutionHubStore(layout: fixture.layout)
        await store.refresh()
        let sessionId = try XCTUnwrap(store.snapshot.sourceSessions.first?.id)

        let conversation = try store.conversation(sessionId: sessionId)

        XCTAssertEqual(conversation.count, 1)
        XCTAssertEqual(conversation.first?.text, "记录当天工作")
    }

    @MainActor
    func testReflectionStillUsesLedgerRuleAndRequiresHappenedAt() async throws {
        let fixture = try InboxTestFixture()
        let store = WorkEvolutionHubStore(layout: fixture.layout)
        await store.refresh()

        XCTAssertThrowsError(
            try store.addAnnotation(
                target: AnnotationTarget(kind: .day, targetId: fixture.dateKey),
                kind: .reflection,
                body: "后来才认识到"
            )
        ) { error in
            XCTAssertEqual(error as? EvolutionLedgerError, .reflectionRequiresHappenedAt)
        }
    }

    @MainActor
    func testMissingConversationSessionHasExplicitError() async throws {
        let fixture = try InboxTestFixture()
        let store = WorkEvolutionHubStore(layout: fixture.layout)
        await store.refresh()

        XCTAssertThrowsError(try store.conversation(sessionId: "missing")) { error in
            XCTAssertEqual(error as? WorkEvolutionHubStoreError, .sourceSessionNotFound("missing"))
        }
    }

    @MainActor
    func testConcurrentRefreshesShareOneInboxImport() async throws {
        let fixture = try InboxTestFixture()
        let store = WorkEvolutionHubStore(layout: fixture.layout)

        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        _ = await (first, second)

        XCTAssertEqual(store.snapshot.days.map(\.date), [fixture.dateKey])
        XCTAssertEqual(store.receipts.map(\.status), [.imported])
        XCTAssertNil(store.lastError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.inboxURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.processedURL.path))
    }
}
