import EvolutionCore
import EvolutionHubCore
import XCTest

final class ImportAndLinkTests: XCTestCase {
    func testImportTimeLedgerJSON() throws {
        let url = try fixtureURL("timeledger-sample.json")
        let result = try TimeLedgerJSONImporter.importFromFile(at: url)
        XCTAssertEqual(result.projects.count, 1)
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.thoughts.count, 1)
        XCTAssertEqual(result.entries[0].projectNameSnapshot, "TimeLedger")
        XCTAssertEqual(result.thoughts[0].linkedEntryId, "entry-1")
    }

    func testImportContextEventsJSON() throws {
        let url = try fixtureURL("context-events-sample.json")
        let events = try ContextEventJSONImporter.importFromFile(at: url)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].source, .codex)
        XCTAssertEqual(events[0].rawReference, "raw/codex/views/threads/openai/gpt/2026-07/2026-07-12--hub--abc.md")
    }

    @MainActor
    func testHubStoreDayFilterAndManualLink() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let store = HubStore(
            selectedDay: ISO8601Codec.date(from: "2026-07-12T12:00:00Z")!,
            calendar: calendar
        )

        let tl = try TimeLedgerJSONImporter.importFromFile(at: try fixtureURL("timeledger-sample.json"))
        store.projects = tl.projects
        store.timeEntries = tl.entries
        store.thoughtNotes = tl.thoughts

        let events = try ContextEventJSONImporter.importFromFile(at: try fixtureURL("context-events-sample.json"))
        store.mergeContextEvents(events)

        XCTAssertEqual(store.entriesForSelectedDay.map(\.id), ["entry-1"])
        XCTAssertEqual(store.thoughtsForSelectedDay.count, 1)
        XCTAssertEqual(store.inboxEvents.count, 2)

        try store.manuallyLink(timeEntryId: "entry-1", contextEventId: "evt-1")
        XCTAssertEqual(store.confirmedLinks(for: "entry-1").count, 1)
        XCTAssertEqual(store.inboxEvents.map(\.id), ["evt-2"])
        XCTAssertTrue(store.confirmedLinks(for: "entry-1")[0].isUserLocked)

        // re-import same events should not drop manual link
        store.mergeContextEvents(events)
        XCTAssertEqual(store.confirmedLinks(for: "entry-1").count, 1)
        XCTAssertEqual(store.event(id: "evt-1")?.title, "Implement EvolutionHub shell")
    }

    func testManualLinkIdempotentConfirmed() throws {
        let first = try ManualLinkingService.link(
            timeEntryId: "e1",
            contextEventId: "c1",
            existing: []
        )
        XCTAssertThrowsError(
            try ManualLinkingService.link(
                timeEntryId: "e1",
                contextEventId: "c1",
                existing: [first]
            )
        ) { error in
            XCTAssertEqual(error as? ManualLinkError, .alreadyLinked)
        }
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: (name as NSString).deletingPathExtension, withExtension: (name as NSString).pathExtension, subdirectory: "Fixtures")
        guard let url else {
            XCTFail("missing fixture \(name)")
            throw NSError(domain: "test", code: 1)
        }
        return url
    }
}
