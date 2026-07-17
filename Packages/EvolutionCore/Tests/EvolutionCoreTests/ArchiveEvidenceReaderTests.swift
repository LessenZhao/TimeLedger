import Foundation
import XCTest
@testable import EvolutionCore

final class ArchiveEvidenceReaderTests: XCTestCase {
    func testPrepareDayReturnsSeventeenAuditableSourcesAndSeparatesSpanningConversation() throws {
        let fixture = try ArchiveFixture()
        let spanning = "spanning"
        fixture.addThread(id: spanning, title: "跨天项目")
        fixture.addEvent(id: "span-before", threadId: spanning, createdAt: "2026-07-15T17:00:00Z", text: "前一天", sourceLine: 11)
        fixture.addEvent(id: "span-today", threadId: spanning, createdAt: "2026-07-16T18:00:00Z", text: "当天动作", sourceLine: 22)
        fixture.addEvent(id: "span-after", threadId: spanning, createdAt: "2026-07-17T18:00:00Z", text: "后一天", sourceLine: 33)

        fixture.addThread(id: "processor", title: "沉淀处理器")
        fixture.addEvent(id: "processor-user", threadId: "processor", createdAt: "2026-07-16T19:00:00+00:00", text: "[$evolution-ledger] 2026-07-17", sourceLine: 40)

        for index in 1...15 {
            let threadId = "daily-\(index)"
            fixture.addThread(id: threadId, title: "当天会话 \(index)")
            fixture.addEvent(
                id: "event-\(index)",
                threadId: threadId,
                createdAt: String(format: "2026-07-17T%02d:00:00Z", index - 1),
                text: "内容 \(index)",
                sourceLine: 100 + index
            )
        }
        try fixture.write()

        let reader = ArchiveEvidenceReader()
        let day = try reader.prepareDay(
            location: fixture.location,
            date: date("2026-07-17T04:00:00Z"),
            cutoffAt: date("2026-07-17T15:59:00Z"),
            calendar: taipeiCalendar,
            processorThreadIds: []
        )

        XCTAssertEqual(day.date, "2026-07-17")
        XCTAssertEqual(day.slices.count, 17)
        XCTAssertEqual(Set(day.slices.map(\.sessionId)).count, 17)
        XCTAssertTrue(day.slices.allSatisfy { !$0.messageReferences.isEmpty })
        XCTAssertEqual(day.coverage.expectedSessionCount, 17)
        XCTAssertEqual(day.coverage.processorSessionIds, ["codex:processor"])
        XCTAssertFalse(day.coverage.includedSessionIds.contains("codex:processor"))
        XCTAssertFalse(day.coverage.pendingSessionIds.contains("codex:processor"))
        XCTAssertEqual(day.coverage.pendingSessionIds.count, 16)

        let spanningSession = try XCTUnwrap(day.sessions.first { $0.externalThreadId == spanning })
        let spanningSlice = try XCTUnwrap(day.slices.first { $0.sessionId == spanningSession.id })
        XCTAssertEqual(spanningSlice.messageReferences.count, 1)
        XCTAssertEqual(spanningSlice.messageReferences.first?.sourceLine, 22)
        XCTAssertEqual(try reader.conversation(session: spanningSession).count, 3)
        XCTAssertTrue(day.messages.allSatisfy {
            NaturalDayWindow.forDate(date("2026-07-17T04:00:00Z"), calendar: taipeiCalendar)
                .contains($0.reference.createdAt)
        })
        XCTAssertTrue(day.slices.flatMap(\.messageReferences).allSatisfy { reference in
            day.messages.contains { $0.reference.id == reference.id }
        })
        XCTAssertTrue(try day.slices.flatMap(\.messageReferences).allSatisfy { reference in
            guard let session = day.sessions.first(where: { $0.id == EvolutionStableID.sourceSession(source: reference.source, externalThreadId: reference.threadId) }) else {
                return false
            }
            return try reader.contains(reference, in: session)
        })
    }

    func testCutoffExcludesLaterSameDayMessagesAndChangesDigest() throws {
        let fixture = try ArchiveFixture()
        fixture.addThread(id: "cutoff", title: "cutoff")
        fixture.addEvent(id: "early", threadId: "cutoff", createdAt: "2026-07-17T01:00:00Z", text: "早", sourceLine: 1)
        fixture.addEvent(id: "late", threadId: "cutoff", createdAt: "2026-07-17T10:00:00Z", text: "晚", sourceLine: 2)
        try fixture.write()

        let reader = ArchiveEvidenceReader()
        let early = try reader.prepareDay(location: fixture.location, date: date("2026-07-17T04:00:00Z"), cutoffAt: date("2026-07-17T02:00:00Z"), calendar: taipeiCalendar, processorThreadIds: [])
        let late = try reader.prepareDay(location: fixture.location, date: date("2026-07-17T04:00:00Z"), cutoffAt: date("2026-07-17T11:00:00Z"), calendar: taipeiCalendar, processorThreadIds: [])

        XCTAssertEqual(early.messages.map(\.reference.eventId), ["early"])
        XCTAssertEqual(late.messages.map(\.reference.eventId), ["early", "late"])
        XCTAssertNotEqual(early.sourceDigest, late.sourceDigest)
    }

    func testThreadUpdatedOnDayWithoutMessageDoesNotBecomeSource() throws {
        let fixture = try ArchiveFixture()
        fixture.addThread(id: "metadata-only", title: "只有索引更新", updatedAt: "2026-07-17T08:00:00Z")
        fixture.addEvent(id: "old", threadId: "metadata-only", createdAt: "2026-07-15T08:00:00Z", text: "旧消息", sourceLine: 1)
        try fixture.write()

        let result = try ArchiveEvidenceReader().prepareDay(location: fixture.location, date: date("2026-07-17T04:00:00Z"), cutoffAt: date("2026-07-17T15:59:00Z"), calendar: taipeiCalendar, processorThreadIds: [])

        XCTAssertTrue(result.sessions.isEmpty)
        XCTAssertTrue(result.slices.isEmpty)
        XCTAssertEqual(result.coverage.expectedSessionCount, 0)
    }

    func testMixedUTCAndExplicitOffsetUseTaipeiNaturalDay() throws {
        let fixture = try ArchiveFixture()
        fixture.addThread(id: "timezone", title: "时区")
        fixture.addEvent(id: "utc-before", threadId: "timezone", createdAt: "2026-07-16T15:59:59Z", text: "前一天", sourceLine: 1)
        fixture.addEvent(id: "offset-start", threadId: "timezone", createdAt: "2026-07-17T00:00:00+08:00", text: "当天开始", sourceLine: 2)
        fixture.addEvent(id: "utc-end", threadId: "timezone", createdAt: "2026-07-17T15:59:59Z", text: "当天结束", sourceLine: 3)
        fixture.addEvent(id: "offset-next", threadId: "timezone", createdAt: "2026-07-18T00:00:00+08:00", text: "下一天", sourceLine: 4)
        try fixture.write()

        let result = try ArchiveEvidenceReader().prepareDay(location: fixture.location, date: date("2026-07-17T04:00:00Z"), cutoffAt: date("2026-07-17T15:59:59Z"), calendar: taipeiCalendar, processorThreadIds: [])

        XCTAssertEqual(result.messages.map(\.reference.eventId), ["offset-start", "utc-end"])
    }

    func testDoesNotInventCollapsedDuplicateMessage() throws {
        let fixture = try ArchiveFixture()
        fixture.addThread(id: "collapsed", title: "重复文本", updatedAt: "2026-07-17T08:00:00Z")
        fixture.addEvent(id: "only-existing", threadId: "collapsed", createdAt: "2026-07-15T08:00:00Z", text: "完全相同", sourceLine: 1)
        try fixture.write()

        let result = try ArchiveEvidenceReader().prepareDay(location: fixture.location, date: date("2026-07-17T04:00:00Z"), cutoffAt: date("2026-07-17T15:59:59Z"), calendar: taipeiCalendar, processorThreadIds: [])

        XCTAssertTrue(result.slices.isEmpty)
        XCTAssertTrue(result.messages.isEmpty)
    }

    func testMissingSourceMetadataPreservesSessionAndAddsDiagnostics() throws {
        let fixture = try ArchiveFixture()
        fixture.addThread(id: "missing-source", title: "缺来源")
        fixture.addEvent(id: "missing", threadId: "missing-source", createdAt: "2026-07-17T01:00:00Z", text: "仍应保留", sourceLine: nil, sourceFile: nil)
        try fixture.write()

        let result = try ArchiveEvidenceReader().prepareDay(location: fixture.location, date: date("2026-07-17T04:00:00Z"), cutoffAt: date("2026-07-17T15:59:59Z"), calendar: taipeiCalendar, processorThreadIds: [])

        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.slices.count, 1)
        XCTAssertEqual(result.messages.first?.reference.sourceFile, "")
        XCTAssertEqual(result.messages.first?.reference.sourceLine, -1)
        XCTAssertEqual(Set(result.diagnostics.map(\.code)), ["archive_missing_source_file", "archive_missing_source_line"])
        XCTAssertTrue(result.diagnostics.allSatisfy { $0.severity == .warning })
    }

    private var taipeiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        guard let value = ISO8601Codec.date(from: iso) else {
            XCTFail("bad date \(iso)")
            return Date()
        }
        return value
    }
}

private final class ArchiveFixture {
    let root: URL
    let eventsURL: URL
    let threadsURL: URL
    var events: [[String: Any]] = []
    var threads: [[String: Any]] = []

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        eventsURL = root.appendingPathComponent("events.jsonl")
        threadsURL = root.appendingPathComponent("threads-index.jsonl")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var location: SourceArchiveLocation {
        SourceArchiveLocation(source: .codex, eventsPath: eventsURL.path, threadsPath: threadsURL.path)
    }

    func addThread(
        id: String,
        title: String,
        createdAt: String = "2026-07-15T08:00:00Z",
        updatedAt: String = "2026-07-18T08:00:00Z"
    ) {
        threads.append([
            "thread_id": id,
            "title": title,
            "cwd": "/tmp/\(id)",
            "created_at": createdAt,
            "updated_at": updatedAt,
            "source_file": "/archive/\(id).jsonl"
        ])
    }

    func addEvent(
        id: String,
        threadId: String,
        createdAt: String,
        text: String,
        sourceLine: Int?,
        sourceFile: String? = "/archive/source.jsonl",
        role: String = "user"
    ) {
        var row: [String: Any] = [
            "event_id": id,
            "thread_id": threadId,
            "created_at": createdAt,
            "role": role,
            "text": text
        ]
        if let sourceLine { row["source_line"] = sourceLine }
        if let sourceFile { row["source_file"] = sourceFile }
        events.append(row)
    }

    func write() throws {
        try jsonLines(events).write(to: eventsURL, atomically: true, encoding: .utf8)
        try jsonLines(threads).write(to: threadsURL, atomically: true, encoding: .utf8)
    }

    private func jsonLines(_ rows: [[String: Any]]) throws -> String {
        try rows.map { row in
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        }.joined(separator: "\n") + "\n"
    }
}
