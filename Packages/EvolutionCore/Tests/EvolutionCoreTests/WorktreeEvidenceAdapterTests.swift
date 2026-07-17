import XCTest
@testable import EvolutionCore

final class WorktreeEvidenceAdapterTests: XCTestCase {
    func testSnapshotSeparatesStagedUnstagedAndUntrackedWithoutTreatingDirtyAsFailure() throws {
        let repo = try TemporaryGitRepository()
        try repo.write("base\n", to: "tracked.txt")
        try repo.git(["add", "tracked.txt"])
        try repo.git(["commit", "-m", "Initial commit"])

        try repo.write("staged\n", to: "staged.txt")
        try repo.git(["add", "staged.txt"])
        try repo.write("base\nunstaged\n", to: "tracked.txt")
        try repo.write("untracked\n", to: "untracked.txt")

        let capturedAt = try XCTUnwrap(ISO8601Codec.date(from: "2026-07-17T12:00:00Z"))
        let snapshot = try WorktreeEvidenceAdapter().snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSince1970: 0),
            capturedAt: capturedAt
        )

        XCTAssertEqual(
            snapshot.repoPath,
            try repo.git(["rev-parse", "--show-toplevel"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertEqual(snapshot.head.count, 40)
        XCTAssertEqual(Set(snapshot.changes.map(\.kind)), [.staged, .unstaged, .untracked])
        XCTAssertTrue(snapshot.changes.contains { $0.path == "staged.txt" && $0.kind == .staged && $0.statusCode == "A" })
        XCTAssertTrue(snapshot.changes.contains { $0.path == "tracked.txt" && $0.kind == .unstaged && $0.statusCode == "M" })
        XCTAssertTrue(snapshot.changes.contains { $0.path == "untracked.txt" && $0.kind == .untracked && $0.statusCode == "??" })
        XCTAssertEqual(snapshot.relevantCommits.map(\.commitMessage), ["Initial commit"])
        XCTAssertEqual(snapshot.verificationStatus, .verified)
        XCTAssertNil(snapshot.limitation)
    }

    func testOnePathCanHaveSeparateStagedAndUnstagedEvidence() throws {
        let repo = try TemporaryGitRepository()
        try repo.write("base\n", to: "both.txt")
        try repo.git(["add", "both.txt"])
        try repo.git(["commit", "-m", "Initial"])
        try repo.write("base\nstaged\n", to: "both.txt")
        try repo.git(["add", "both.txt"])
        try repo.write("base\nstaged\nunstaged\n", to: "both.txt")

        let snapshot = try WorktreeEvidenceAdapter().snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSince1970: 0)
        )
        let changes = snapshot.changes.filter { $0.path == "both.txt" }

        XCTAssertEqual(Set(changes.map(\.kind)), [.staged, .unstaged])
        XCTAssertEqual(Set(changes.map(\.statusCode)), ["M"])
    }

    func testHistoricalSnapshotStatesCurrentWorktreeLimitationButKeepsCommitEvidence() throws {
        let repo = try TemporaryGitRepository()
        try repo.write("base\n", to: "tracked.txt")
        try repo.git(["add", "tracked.txt"])
        try repo.git(
            ["commit", "-m", "Historical commit"],
            environment: [
                "GIT_AUTHOR_DATE": "2026-07-01T12:00:00Z",
                "GIT_COMMITTER_DATE": "2026-07-01T12:00:00Z",
            ]
        )

        let capturedAt = try XCTUnwrap(ISO8601Codec.date(from: "2026-07-17T12:00:00Z"))
        let historicalDate = try XCTUnwrap(ISO8601Codec.date(from: "2026-07-01T12:00:00Z"))
        let snapshot = try WorktreeEvidenceAdapter().snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSince1970: 0),
            capturedAt: capturedAt,
            historicalDate: historicalDate
        )

        XCTAssertEqual(snapshot.verificationStatus, .partial)
        XCTAssertEqual(snapshot.limitation, "当前工作树只能核实捕获时状态，无法证明历史未提交内容。")
        XCTAssertEqual(snapshot.relevantCommits.count, 1)

        let current = try WorktreeEvidenceAdapter().snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSince1970: 0),
            capturedAt: capturedAt
        )
        XCTAssertEqual(current.relevantCommits.map(\.id), snapshot.relevantCommits.map(\.id))
        XCTAssertNotEqual(current.id, snapshot.id)
        XCTAssertNotEqual(current.contentHash, snapshot.contentHash)
    }

    func testHistoricalSnapshotIncludesOnlyCommitsFromRequestedTaipeiDay() throws {
        let repo = try TemporaryGitRepository()
        try repo.write("first\n", to: "tracked.txt")
        try repo.git(["add", "tracked.txt"])
        try repo.git(
            ["commit", "-m", "July first"],
            environment: [
                "GIT_AUTHOR_DATE": "2026-07-01T09:00:00+08:00",
                "GIT_COMMITTER_DATE": "2026-07-01T09:00:00+08:00",
            ]
        )
        try repo.write("first\nsecond\n", to: "tracked.txt")
        try repo.git(["add", "tracked.txt"])
        try repo.git(
            ["commit", "-m", "July second"],
            environment: [
                "GIT_AUTHOR_DATE": "2026-07-02T09:00:00+08:00",
                "GIT_COMMITTER_DATE": "2026-07-02T09:00:00+08:00",
            ]
        )

        let historicalDate = try XCTUnwrap(ISO8601Codec.date(from: "2026-07-01T12:00:00+08:00"))
        let capturedAt = try XCTUnwrap(ISO8601Codec.date(from: "2026-07-17T12:00:00+08:00"))
        let snapshot = try WorktreeEvidenceAdapter().snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSince1970: 0),
            capturedAt: capturedAt,
            historicalDate: historicalDate
        )

        XCTAssertEqual(snapshot.relevantCommits.map(\.commitMessage), ["July first"])
        XCTAssertEqual(snapshot.verificationStatus, .partial)

        let julySecond = try WorktreeEvidenceAdapter().snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSince1970: 0),
            capturedAt: capturedAt,
            historicalDate: dateForWorktreeTest("2026-07-02T12:00:00+08:00")
        )
        XCTAssertEqual(julySecond.relevantCommits.map(\.commitMessage), ["July second"])
        XCTAssertNotEqual(snapshot.id, julySecond.id)
        XCTAssertNotEqual(snapshot.contentHash, julySecond.contentHash)
    }

    func testHistoricalDayUsesCommitterDateAndExcludesExactNextDayBoundary() throws {
        let repo = try TemporaryGitRepository()
        try repo.write("first\n", to: "tracked.txt")
        try repo.git(["add", "tracked.txt"])
        try repo.git(
            ["commit", "-m", "Committed at day end"],
            environment: [
                "GIT_AUTHOR_DATE": "2026-06-30T09:00:00+08:00",
                "GIT_COMMITTER_DATE": "2026-07-01T23:59:59+08:00",
            ]
        )
        try repo.write("first\nsecond\n", to: "tracked.txt")
        try repo.git(["add", "tracked.txt"])
        try repo.git(
            ["commit", "-m", "Committed at next day boundary"],
            environment: [
                "GIT_AUTHOR_DATE": "2026-07-01T09:00:00+08:00",
                "GIT_COMMITTER_DATE": "2026-07-02T00:00:00+08:00",
            ]
        )

        let requestedDay = try XCTUnwrap(ISO8601Codec.date(from: "2026-07-01T12:00:00+08:00"))
        let snapshot = try WorktreeEvidenceAdapter().snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSince1970: 0),
            capturedAt: dateForWorktreeTest("2026-07-17T12:00:00+08:00"),
            historicalDate: requestedDay
        )

        XCTAssertEqual(snapshot.relevantCommits.map(\.commitMessage), ["Committed at day end"])
        XCTAssertEqual(
            snapshot.relevantCommits.first?.capturedAt,
            dateForWorktreeTest("2026-07-01T23:59:59+08:00")
        )
    }

    func testEarlierTimeOnSameTaipeiDayIsNotMisreportedAsHistorical() throws {
        let repo = try TemporaryGitRepository()
        try repo.write("base\n", to: "tracked.txt")
        try repo.git(["add", "tracked.txt"])
        try repo.git(["commit", "-m", "Same day commit"])

        let capturedAt = try XCTUnwrap(ISO8601Codec.date(from: "2026-07-17T12:00:00Z"))
        let sameDay = try XCTUnwrap(ISO8601Codec.date(from: "2026-07-17T00:00:00Z"))
        let snapshot = try WorktreeEvidenceAdapter().snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSince1970: 0),
            capturedAt: capturedAt,
            historicalDate: sameDay
        )

        XCTAssertEqual(snapshot.verificationStatus, .verified)
        XCTAssertNil(snapshot.limitation)
    }

    func testFailedCheckIsRecordedSeparatelyAndDoesNotMakeCapturedEvidenceUnverified() throws {
        let repo = try TemporaryGitRepository()
        try repo.write("base\n", to: "tracked.txt")
        try repo.git(["add", "tracked.txt"])
        try repo.git(["commit", "-m", "Initial"])
        let failedCheck = VerificationCheck(
            id: EvolutionStableID.verificationCheck(command: ["swift", "test"]),
            command: ["swift", "test"],
            status: .failed,
            summary: "Tests failed with exit code 1"
        )

        let snapshot = try WorktreeEvidenceAdapter().snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSince1970: 0),
            checks: [failedCheck]
        )

        XCTAssertEqual(snapshot.checks, [failedCheck])
        XCTAssertEqual(snapshot.verificationStatus, .verified)
    }

    func testSnapshotIdentityIsOrderInsensitiveButIncludesCompleteChangeAndCheckState() throws {
        let repo = try TemporaryGitRepository()
        try repo.write("base\n", to: "tracked.txt")
        try repo.git(["add", "tracked.txt"])
        try repo.git(["commit", "-m", "Initial"])
        try repo.write("one\n", to: "one.txt")
        try repo.write("two\n", to: "two.txt")

        let passed = check(command: ["swift", "test"], status: .passed, summary: "12 tests passed")
        let linted = check(command: ["swift", "format"], status: .passed, summary: "No changes")
        let adapter = WorktreeEvidenceAdapter()
        let first = try adapter.snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSince1970: 0),
            checks: [passed, linted]
        )
        let reordered = try adapter.snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSince1970: 0),
            checks: [linted, passed]
        )

        XCTAssertEqual(first.id, reordered.id)
        XCTAssertEqual(first.contentHash, reordered.contentHash)

        let failed = check(command: ["swift", "test"], status: .failed, summary: "1 test failed")
        let changedCheck = try adapter.snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSince1970: 0),
            checks: [failed, linted]
        )
        XCTAssertNotEqual(first.id, changedCheck.id)
        XCTAssertNotEqual(first.contentHash, changedCheck.contentHash)

        try repo.write("three\n", to: "three.txt")
        let changedWorktree = try adapter.snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSince1970: 0),
            checks: [passed, linted]
        )
        XCTAssertNotEqual(first.id, changedWorktree.id)
        XCTAssertNotEqual(first.contentHash, changedWorktree.contentHash)
    }

    func testRelevantCommitsParticipateInContentHash() throws {
        let repo = try TemporaryGitRepository()
        try repo.write("base\n", to: "tracked.txt")
        try repo.git(["add", "tracked.txt"])
        try repo.git(["commit", "-m", "Initial"])
        let adapter = WorktreeEvidenceAdapter()

        let withCommit = try adapter.snapshot(repoPath: repo.path, since: Date(timeIntervalSince1970: 0))
        let withoutCommit = try adapter.snapshot(
            repoPath: repo.path,
            since: Date(timeIntervalSinceNow: 86_400)
        )

        XCTAssertEqual(withCommit.relevantCommits.count, 1)
        XCTAssertTrue(withoutCommit.relevantCommits.isEmpty)
        XCTAssertNotEqual(withCommit.id, withoutCommit.id)
        XCTAssertNotEqual(withCommit.contentHash, withoutCommit.contentHash)
    }

    func testNonzeroGitCommandThrowsCommandFailedInsteadOfPretendingRepositoryIsClean() throws {
        let repo = try TemporaryGitRepository()

        XCTAssertThrowsError(
            try WorktreeEvidenceAdapter().snapshot(
                repoPath: repo.path,
                since: Date(timeIntervalSince1970: 0)
            )
        ) { error in
            guard case WorktreeEvidenceError.commandFailed(let arguments, let status, let stderr) = error else {
                return XCTFail("Expected commandFailed, got \(error)")
            }
            XCTAssertEqual(Array(arguments.suffix(2)), ["rev-parse", "HEAD"])
            XCTAssertNotEqual(status, 0)
            XCTAssertFalse(stderr.isEmpty)
        }
    }

    func testRepositoryRootAcceptsNestedPathAndNonRepositoryThrowsExplicitError() throws {
        let repo = try TemporaryGitRepository()
        let nested = URL(fileURLWithPath: repo.path).appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertEqual(
            try WorktreeEvidenceAdapter().repositoryRoot(for: nested.path),
            try repo.git(["rev-parse", "--show-toplevel"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        XCTAssertThrowsError(try WorktreeEvidenceAdapter().repositoryRoot(for: outside.path)) { error in
            guard case WorktreeEvidenceError.notRepository(let path) = error else {
                return XCTFail("Expected notRepository, got \(error)")
            }
            XCTAssertEqual(path, outside.path)
        }
    }

    func testVarAliasAndPrivateVarCanonicalPathProduceTheSameSnapshotIdentity() throws {
        let repo = try TemporaryGitRepository()
        try repo.write("base\n", to: "tracked.txt")
        try repo.git(["add", "tracked.txt"])
        try repo.git(["commit", "-m", "Initial"])

        let canonicalRoot = try WorktreeEvidenceAdapter().repositoryRoot(for: repo.path)
        guard canonicalRoot.hasPrefix("/private/var/") else {
            throw XCTSkip("This regression applies to the macOS /var -> /private/var alias")
        }
        let aliasRoot = String(canonicalRoot.dropFirst("/private".count))
        XCTAssertTrue(FileManager.default.fileExists(atPath: aliasRoot))

        let capturedAt = dateForWorktreeTest("2026-07-17T12:00:00+08:00")
        let adapter = WorktreeEvidenceAdapter()
        let fromCanonical = try adapter.snapshot(
            repoPath: canonicalRoot,
            since: Date(timeIntervalSince1970: 0),
            capturedAt: capturedAt
        )
        let fromAlias = try adapter.snapshot(
            repoPath: aliasRoot,
            since: Date(timeIntervalSince1970: 0),
            capturedAt: capturedAt
        )

        XCTAssertEqual(fromAlias.repoPath, fromCanonical.repoPath)
        XCTAssertEqual(fromAlias.id, fromCanonical.id)
        XCTAssertEqual(fromAlias.contentHash, fromCanonical.contentHash)
        XCTAssertEqual(
            fromAlias.relevantCommits.map(\.repoPath),
            fromCanonical.relevantCommits.map(\.repoPath)
        )
    }

    private func check(command: [String], status: VerificationCheckStatus, summary: String) -> VerificationCheck {
        VerificationCheck(
            id: EvolutionStableID.verificationCheck(command: command),
            command: command,
            status: status,
            summary: summary
        )
    }
}

private func dateForWorktreeTest(_ value: String) -> Date {
    ISO8601Codec.date(from: value)!
}

private final class TemporaryGitRepository {
    let path: String

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorktreeEvidenceAdapterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        path = url.resolvingSymlinksInPath().path
        try git(["init", "-b", "main"])
        try git(["config", "user.name", "EvolutionCore Tests"])
        try git(["config", "user.email", "evolution-core-tests@example.invalid"])
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    func write(_ content: String, to relativePath: String) throws {
        let url = URL(fileURLWithPath: path).appendingPathComponent(relativePath)
        try Data(content.utf8).write(to: url)
    }

    @discardableResult
    func git(_ arguments: [String], environment: [String: String] = [:]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "TemporaryGitRepository",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(decoding: error, as: UTF8.self)]
            )
        }
        return String(decoding: output, as: UTF8.self)
    }
}
