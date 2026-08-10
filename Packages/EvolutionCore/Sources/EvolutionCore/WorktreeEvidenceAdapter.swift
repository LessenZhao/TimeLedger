import Foundation

public enum WorktreeEvidenceError: Error, LocalizedError, Sendable {
    case commandFailed(arguments: [String], status: Int32, stderr: String)
    case notRepository(String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments, status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "git \(arguments.joined(separator: " ")) failed with status \(status)\(detail.isEmpty ? "" : ": \(detail)")"
        case let .notRepository(path):
            return "Not a Git repository: \(path)"
        }
    }
}

/// Captures only verifiable repository facts. It never stores a full diff and never
/// treats a dirty worktree as a failed verification.
public struct WorktreeEvidenceAdapter: Sendable {
    public let gitPath: String

    public init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }

    public func repositoryRoot(for path: String) throws -> String {
        do {
            let output = try runGit(at: path, arguments: ["rev-parse", "--show-toplevel"])
            let root = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !root.isEmpty else {
                throw WorktreeEvidenceError.notRepository(path)
            }
            return root
        } catch let error as WorktreeEvidenceError {
            switch error {
            case .commandFailed:
                throw WorktreeEvidenceError.notRepository(path)
            case .notRepository:
                throw error
            }
        }
    }

    public func snapshot(
        repoPath: String,
        since: Date,
        capturedAt: Date = Date(),
        historicalDate: Date? = nil,
        checks: [VerificationCheck] = []
    ) throws -> WorktreeEvidenceSnapshot {
        let root = try repositoryRoot(for: repoPath)
        let branch = try runGit(at: root, arguments: ["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let head = try runGit(at: root, arguments: ["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let statusOutput = try runGit(
            at: root,
            arguments: ["status", "--porcelain=v1", "--untracked-files=all"]
        )
        let changes = parseStatus(statusOutput)
        var logArguments = ["log"]
        if let historicalDate {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
            let interval = calendar.dateInterval(of: .day, for: historicalDate)!
            logArguments.append("--since=\(ISO8601Codec.string(from: interval.start))")
            logArguments.append("--until=\(ISO8601Codec.string(from: interval.end.addingTimeInterval(-1)))")
        } else {
            logArguments.append("--since=\(ISO8601Codec.string(from: since))")
        }
        logArguments.append(contentsOf: [
            "--pretty=format:%H%x09%s%x09%cI",
            "--shortstat",
        ])
        let commitsOutput = try runGit(at: root, arguments: logArguments)
        let commits = parseCommits(commitsOutput, repoPath: root)

        let sortedChanges = changes.map(changeFingerprint).sorted()
        let sortedChecks = checks.map(checkFingerprint).sorted()
        let sortedCommits = commits.map(commitFingerprint).sorted()
        let isHistorical = historicalDate.map { isEarlierNaturalDay($0, than: capturedAt) } ?? false
        let verificationStatus: EvidenceVerificationStatus = isHistorical ? .partial : .verified
        let limitation = isHistorical ? "当前工作树只能核实捕获时状态，无法证明历史未提交内容。" : nil
        let contentHash = EvolutionStableID.worktreeContentHash(
            repoPath: root,
            branch: branch,
            head: head,
            verificationStatus: verificationStatus,
            limitation: limitation,
            sortedChanges: sortedChanges,
            sortedChecks: sortedChecks,
            sortedCommits: sortedCommits
        )
        let id = EvolutionStableID.worktree(
            repoPath: root,
            branch: branch,
            head: head,
            verificationStatus: verificationStatus,
            limitation: limitation,
            sortedChanges: sortedChanges,
            sortedChecks: sortedChecks,
            sortedCommits: sortedCommits
        )

        return WorktreeEvidenceSnapshot(
            id: id,
            repoPath: root,
            branch: branch,
            head: head,
            capturedAt: capturedAt,
            relevantCommits: commits,
            changes: changes,
            checks: checks,
            verificationStatus: verificationStatus,
            limitation: limitation,
            contentHash: contentHash
        )
    }

    private func runGit(at path: String, arguments: [String]) throws -> String {
#if os(macOS)
        let processArguments = ["-C", path] + arguments
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = processArguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw WorktreeEvidenceError.commandFailed(
                arguments: processArguments,
                status: -1,
                stderr: error.localizedDescription
            )
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw WorktreeEvidenceError.commandFailed(
                arguments: processArguments,
                status: process.terminationStatus,
                stderr: String(decoding: errorData, as: UTF8.self)
            )
        }
        return String(decoding: outputData, as: UTF8.self)
#else
        throw WorktreeEvidenceError.commandFailed(
            arguments: ["-C", path] + arguments,
            status: -1,
            stderr: "git command unavailable on iOS"
        )
#endif
    }

    private func parseStatus(_ output: String) -> [WorktreeFileChange] {
        var changes: [WorktreeFileChange] = []
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let characters = Array(rawLine)
            guard characters.count >= 3 else { continue }
            let indexStatus = characters[0]
            let worktreeStatus = characters[1]
            let path = String(characters.dropFirst(3))

            if indexStatus == "?", worktreeStatus == "?" {
                changes.append(makeChange(path: path, kind: .untracked, statusCode: "??"))
                continue
            }
            if indexStatus != " " {
                changes.append(makeChange(path: path, kind: .staged, statusCode: String(indexStatus)))
            }
            if worktreeStatus != " " {
                changes.append(makeChange(path: path, kind: .unstaged, statusCode: String(worktreeStatus)))
            }
        }
        return changes.sorted { changeFingerprint($0) < changeFingerprint($1) }
    }

    private func makeChange(path: String, kind: WorktreeChangeKind, statusCode: String) -> WorktreeFileChange {
        WorktreeFileChange(
            id: EvolutionStableID.worktreeFileChange(path: path, kind: kind, statusCode: statusCode),
            path: path,
            kind: kind,
            statusCode: statusCode
        )
    }

    private func parseCommits(_ output: String, repoPath: String) -> [GitEvidenceSummary] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var commits: [GitEvidenceSummary] = []
        var index = 0

        while index < lines.count {
            let fields = lines[index].split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, fields[0].count == 40 else {
                index += 1
                continue
            }

            var changedFiles = 0
            var insertions = 0
            var deletions = 0
            var next = index + 1
            while next < lines.count {
                let candidate = lines[next]
                let nextFields = candidate.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                if nextFields.count == 3, nextFields[0].count == 40 {
                    break
                }
                if candidate.contains("file changed") || candidate.contains("files changed") {
                    changedFiles = integer(matching: #"(\d+) files? changed"#, in: candidate)
                    insertions = integer(matching: #"(\d+) insertions?"#, in: candidate)
                    deletions = integer(matching: #"(\d+) deletions?"#, in: candidate)
                }
                next += 1
            }

            let committedAt = ISO8601Codec.date(from: fields[2]) ?? Date(timeIntervalSince1970: 0)
            commits.append(GitEvidenceSummary(
                id: "git:\(fields[0])",
                repoPath: repoPath,
                commitHash: fields[0],
                commitMessage: fields[1],
                changedFiles: changedFiles,
                insertions: insertions,
                deletions: deletions,
                capturedAt: committedAt
            ))
            index = next
        }
        return commits
    }

    private func integer(matching pattern: String, in text: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              let range = Range(match.range(at: 1), in: text)
        else {
            return 0
        }
        return Int(text[range]) ?? 0
    }

    private func changeFingerprint(_ change: WorktreeFileChange) -> String {
        [change.path, change.kind.rawValue, change.statusCode].joined(separator: "\u{1f}")
    }

    private func checkFingerprint(_ check: VerificationCheck) -> String {
        [
            check.command.joined(separator: "\u{1d}"),
            check.status.rawValue,
            check.summary
        ].joined(separator: "\u{1f}")
    }

    private func commitFingerprint(_ commit: GitEvidenceSummary) -> String {
        [
            commit.repoPath,
            commit.commitHash,
            commit.commitMessage,
            String(commit.changedFiles),
            String(commit.insertions),
            String(commit.deletions),
            commit.buildStatus ?? "",
            commit.testStatus ?? "",
            ISO8601Codec.string(from: commit.capturedAt)
        ].joined(separator: "\u{1f}")
    }

    private func isEarlierNaturalDay(_ candidate: Date, than capturedAt: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar.startOfDay(for: candidate) < calendar.startOfDay(for: capturedAt)
    }
}
