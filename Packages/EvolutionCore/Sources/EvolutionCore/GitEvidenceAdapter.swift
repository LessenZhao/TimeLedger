import Foundation

public struct GitEvidenceAdapter {
    public var repoPath: String

    public init(repoPath: String) {
        self.repoPath = repoPath
    }

    /// Lightweight summary only — no full diff stored.
    public func recentCommits(since: Date, limit: Int = 20) throws -> [GitEvidenceSummary] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let sinceStr = formatter.string(from: since)
        let output = try runGit([
            "log",
            "--since=\(sinceStr)",
            "-n", "\(limit)",
            "--pretty=format:%H\t%s\t%aI",
            "--shortstat"
        ])
        return parse(output: output)
    }

    private func runGit(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoPath] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parse(output: String) -> [GitEvidenceSummary] {
        var results: [GitEvidenceSummary] = []
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.contains("\t") {
                let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
                guard parts.count >= 3 else { i += 1; continue }
                let hash = parts[0]
                let message = parts[1]
                let date = ISO8601Codec.date(from: parts[2]) ?? Date()
                var changed = 0
                var ins = 0
                var del = 0
                if i + 1 < lines.count, lines[i + 1].contains("file") {
                    let stat = lines[i + 1]
                    changed = firstInt(in: stat) ?? 0
                    if let range = stat.range(of: #"(\d+) insertions?"#, options: .regularExpression) {
                        ins = firstInt(in: String(stat[range])) ?? 0
                    }
                    if let range = stat.range(of: #"(\d+) deletions?"#, options: .regularExpression) {
                        del = firstInt(in: String(stat[range])) ?? 0
                    }
                    i += 1
                }
                results.append(GitEvidenceSummary(
                    repoPath: repoPath,
                    commitHash: hash,
                    commitMessage: message,
                    changedFiles: changed,
                    insertions: ins,
                    deletions: del,
                    capturedAt: date
                ))
            }
            i += 1
        }
        return results
    }

    private func firstInt(in text: String) -> Int? {
        let pattern = try? NSRegularExpression(pattern: #"(\d+)"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern?.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[r])
    }
}
