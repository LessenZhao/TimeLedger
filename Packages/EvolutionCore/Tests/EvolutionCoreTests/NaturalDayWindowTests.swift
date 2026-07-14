import XCTest
@testable import EvolutionCore

final class NaturalDayWindowTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    func testNaturalDayBoundsInShanghai() {
        let noon = ISO8601Codec.date(from: "2026-07-12T12:00:00+08:00")!
        let window = NaturalDayWindow.forDate(noon, calendar: calendar)

        XCTAssertEqual(ISO8601Codec.string(from: window.start).prefix(19), "2026-07-11T16:00:00")
        // start is 2026-07-12 00:00 +08 = 2026-07-11 16:00 Z
        XCTAssertTrue(window.contains(ISO8601Codec.date(from: "2026-07-12T00:00:00+08:00")!))
        XCTAssertTrue(window.contains(ISO8601Codec.date(from: "2026-07-12T23:59:59+08:00")!))
        XCTAssertFalse(window.contains(ISO8601Codec.date(from: "2026-07-13T00:00:00+08:00")!))
        XCTAssertFalse(window.contains(ISO8601Codec.date(from: "2026-07-11T23:59:59+08:00")!))
    }

    func testOldThreadWithNewMessageIsActiveOnDay() {
        let window = NaturalDayWindow.forDate(
            ISO8601Codec.date(from: "2026-07-12T10:00:00+08:00")!,
            calendar: calendar
        )

        let created = ISO8601Codec.date(from: "2026-06-01T09:00:00+08:00")!
        let updated = ISO8601Codec.date(from: "2026-07-12T15:00:00+08:00")!
        let messages = [
            ISO8601Codec.date(from: "2026-06-01T09:01:00+08:00")!,
            ISO8601Codec.date(from: "2026-07-12T14:00:00+08:00")!
        ]

        XCTAssertTrue(window.isThreadActiveOnDay(
            createdAt: created,
            updatedAt: updated,
            messageTimes: messages
        ))
    }

    func testInactiveThreadOutsideDay() {
        let window = NaturalDayWindow.forDate(
            ISO8601Codec.date(from: "2026-07-12T10:00:00+08:00")!,
            calendar: calendar
        )
        let created = ISO8601Codec.date(from: "2026-06-01T09:00:00+08:00")!
        let updated = ISO8601Codec.date(from: "2026-06-02T09:00:00+08:00")!
        let messages = [ISO8601Codec.date(from: "2026-06-01T10:00:00+08:00")!]

        XCTAssertFalse(window.isThreadActiveOnDay(
            createdAt: created,
            updatedAt: updated,
            messageTimes: messages
        ))
    }

    func testOnlyMessageOnDayWithoutUpdatedAtChangeStillActive() {
        let window = NaturalDayWindow.forDate(
            ISO8601Codec.date(from: "2026-07-12T10:00:00+08:00")!,
            calendar: calendar
        )
        // updatedAt wrongly stuck in past; message proves activity
        XCTAssertTrue(window.isThreadActiveOnDay(
            createdAt: ISO8601Codec.date(from: "2026-01-01T00:00:00+08:00")!,
            updatedAt: ISO8601Codec.date(from: "2026-01-01T00:00:00+08:00")!,
            messageTimes: [ISO8601Codec.date(from: "2026-07-12T08:00:00+08:00")!]
        ))
    }

    func testTimezonePreservedInCodec() {
        let z = ISO8601Codec.date(from: "2026-07-12T00:00:00Z")!
        let plus8 = ISO8601Codec.date(from: "2026-07-12T08:00:00+08:00")!
        XCTAssertEqual(z.timeIntervalSince1970, plus8.timeIntervalSince1970, accuracy: 0.001)
    }
}
