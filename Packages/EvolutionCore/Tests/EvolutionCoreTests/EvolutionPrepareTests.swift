import Foundation
import XCTest
@testable import EvolutionCore

final class EvolutionPrepareTests: XCTestCase {
    func testPreparePreservesEverySourceDeduplicatesRepositoryAndIsDeterministic() throws {
        let fixture = try PrepareFixture()
        let repository = try fixture.makeRepository()
        let nested = repository.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let codex = try fixture.makeArchive(
            source: .codex,
            name: "codex",
            threads: [
                ("same-thread", nested.path, "Codex project"),
                ("no-cwd", nil, "Thinking only"),
            ]
        )
        let claude = try fixture.makeArchive(
            source: .claude,
            name: "claude",
            threads: [
                ("same-thread", repository.path, "Claude project"),
            ]
        )
        let request = EvolutionPrepareRequest(
            date: "2026-07-17",
            timeZoneIdentifier: "Asia/Taipei",
            cutoffAt: fixture.date("2026-07-17T12:00:00Z"),
            archives: [codex, claude],
            explicitProcessorThreadIds: []
        )
        let capturedAt = fixture.date("2026-07-17T12:30:00Z")
        let ledger = EvolutionLedger(store: PrepareStore(), now: { capturedAt })

        let first = try ledger.prepare(jobId: "job-prepare", request: request)
        let second = try ledger.prepare(jobId: "job-prepare", request: request)

        XCTAssertEqual(first.archiveDays.flatMap(\.sessions).count, 3)
        XCTAssertEqual(
            Set(first.archiveDays.flatMap(\.sessions).map(\.id)),
            ["codex:same-thread", "codex:no-cwd", "claude:same-thread"]
        )
        XCTAssertEqual(first.worktrees.count, 1)
        XCTAssertEqual(
            first.worktrees.single?.repoPath,
            try WorktreeEvidenceAdapter().repositoryRoot(for: repository.path)
        )
        XCTAssertTrue(first.diagnostics.contains { $0.code == "prepare_missing_cwd" })
        XCTAssertEqual(first.sourceDigest, second.sourceDigest)
        XCTAssertEqual(first.contentHash, second.contentHash)
        XCTAssertEqual(first.contentHash, first.recomputedContentHash())
        var changedCWD = first
        changedCWD.archiveDays[0].sessions[0].cwd = "/different/repository"
        XCTAssertNotEqual(first.contentHash, changedCWD.recomputedContentHash())
        var changedClassification = first
        changedClassification.archiveDays[0].slices[0].classification = .excluded
        XCTAssertNotEqual(first.contentHash, changedClassification.recomputedContentHash())
        var changedCaptureTime = first
        changedCaptureTime.worktrees[0].capturedAt = capturedAt.addingTimeInterval(1)
        XCTAssertNotEqual(first.contentHash, changedCaptureTime.recomputedContentHash())
        XCTAssertEqual(
            first.sourceDigest,
            EvolutionSourceDigest.make(
                sourceCutoffAt: request.cutoffAt,
                dateIDs: first.archiveDays.map(\.date),
                sourceSliceIDs: first.archiveDays.flatMap(\.slices).map(\.id),
                messageIDs: first.archiveDays.flatMap(\.messages).map(\.id)
            )
        )
    }

    func testHistoricalPrepareIsPartialAndOnlyIncludesCommitsFromRequestedTaipeiDay() throws {
        let fixture = try PrepareFixture()
        let repository = try fixture.makeRepository()
        try fixture.commit(in: repository, file: "on-day.txt", text: "on day", date: "2026-07-17T09:00:00+08:00")
        try fixture.commit(in: repository, file: "next-day.txt", text: "next day", date: "2026-07-18T09:00:00+08:00")
        let archive = try fixture.makeArchive(
            source: .codex,
            name: "history",
            threads: [("history-thread", repository.path, "Historical")]
        )
        let request = EvolutionPrepareRequest(
            date: "2026-07-17",
            timeZoneIdentifier: "Asia/Taipei",
            cutoffAt: fixture.date("2026-07-20T00:00:00Z"),
            archives: [archive],
            explicitProcessorThreadIds: []
        )

        let capturedAt = fixture.date("2026-07-20T01:00:00Z")
        let bundle = try EvolutionLedger(store: PrepareStore(), now: { capturedAt })
            .prepare(jobId: "history", request: request)

        let snapshot = try XCTUnwrap(bundle.worktrees.single)
        XCTAssertEqual(snapshot.verificationStatus, .partial)
        XCTAssertNotNil(snapshot.limitation)
        XCTAssertEqual(snapshot.capturedAt, capturedAt)
        XCTAssertEqual(snapshot.relevantCommits.map(\.commitMessage), ["on-day.txt"])
        XCTAssertTrue(bundle.diagnostics.contains { $0.code == "prepare_historical_worktree_limit" })
    }

    func testPrepareRejectsInvalidDateTimezoneAndCutoffBeforeDay() throws {
        let ledger = EvolutionLedger(store: PrepareStore())
        let base = EvolutionPrepareRequest(
            date: "2026-07-17",
            timeZoneIdentifier: "Asia/Taipei",
            cutoffAt: Date(timeIntervalSince1970: 1_752_748_800),
            archives: [],
            explicitProcessorThreadIds: []
        )

        var invalidZone = base
        invalidZone.timeZoneIdentifier = "Mars/Olympus"
        XCTAssertThrowsError(try ledger.prepare(jobId: "job", request: invalidZone))

        var invalidDate = base
        invalidDate.date = "17-07-2026"
        XCTAssertThrowsError(try ledger.prepare(jobId: "job", request: invalidDate))

        var beforeDay = base
        beforeDay.cutoffAt = Date(timeIntervalSince1970: 0)
        XCTAssertThrowsError(try ledger.prepare(jobId: "job", request: beforeDay))
    }
}

private final class PrepareStore: EvolutionDocumentStore, @unchecked Sendable {
    func load() throws -> EvolutionLedgerDocument { fatalError("prepare must not load records") }
    func save(_ document: EvolutionLedgerDocument) throws { fatalError("prepare must not write records") }
}

private struct PrepareFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvolutionPrepareTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func date(_ value: String) -> Date {
        ISO8601Codec.date(from: value)!
    }

    func makeArchive(
        source: ContextSource,
        name: String,
        threads: [(id: String, cwd: String?, title: String)]
    ) throws -> SourceArchiveLocation {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let events = directory.appendingPathComponent("events.jsonl")
        let index = directory.appendingPathComponent("threads-index.jsonl")
        let eventLines = try threads.enumerated().map { offset, thread in
            let row: [String: Any] = [
                "event_id": "event-\(offset)",
                "thread_id": thread.id,
                "created_at": "2026-07-17T01:00:00Z",
                "role": "user",
                "text": "message \(thread.id)",
                "source_file": events.path,
                "source_line": offset + 1,
            ]
            return try JSONSerialization.data(withJSONObject: row)
        }
        let threadLines = try threads.map { thread in
            var row: [String: Any] = [
                "thread_id": thread.id,
                "title": thread.title,
                "created_at": "2026-07-17T01:00:00Z",
                "updated_at": "2026-07-17T01:00:00Z",
            ]
            if let cwd = thread.cwd { row["cwd"] = cwd }
            return try JSONSerialization.data(withJSONObject: row)
        }
        try writeJSONLines(eventLines, to: events)
        try writeJSONLines(threadLines, to: index)
        return SourceArchiveLocation(source: source, eventsPath: events.path, threadsPath: index.path)
    }

    func makeRepository() throws -> URL {
        let repository = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try run(["init", "-q"], in: repository)
        try run(["config", "user.email", "fixture@example.invalid"], in: repository)
        try run(["config", "user.name", "Fixture"], in: repository)
        let seed = repository.appendingPathComponent("seed.txt")
        try Data("seed".utf8).write(to: seed)
        try run(["add", "seed.txt"], in: repository)
        try run(
            ["commit", "-q", "-m", "seed"],
            in: repository,
            environment: [
                "GIT_AUTHOR_DATE": "2026-07-16T09:00:00+08:00",
                "GIT_COMMITTER_DATE": "2026-07-16T09:00:00+08:00",
            ]
        )
        return repository
    }

    func commit(in repository: URL, file: String, text: String, date: String) throws {
        try Data(text.utf8).write(to: repository.appendingPathComponent(file))
        try run(["add", file], in: repository)
        try run(["commit", "-q", "-m", file], in: repository, environment: ["GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date])
    }

    private func writeJSONLines(_ lines: [Data], to url: URL) throws {
        var data = Data()
        for line in lines {
            data.append(line)
            data.append(0x0A)
        }
        try data.write(to: url)
    }

    private func run(_ arguments: [String], in directory: URL, environment: [String: String] = [:]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let error = Pipe()
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "PrepareFixture",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)]
            )
        }
    }
}

private extension Array {
    var single: Element? { count == 1 ? self[0] : nil }
}
