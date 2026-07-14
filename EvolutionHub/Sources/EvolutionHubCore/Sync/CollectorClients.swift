import Foundation
import EvolutionCore

public struct TodaySyncResult: Sendable {
    public var timeEntryCount: Int
    public var thoughtCount: Int
    public var codexThreads: Int
    public var claudeThreads: Int
    public var chatgptThreads: Int
    public var autoLinks: Int
    public var suggestedLinks: Int
    public var inboxCount: Int
    public var failures: [String]
    public var warnings: [String]
    public var chatgptWaiting: Bool
    public var reviewMarkdown: String

    public init(
        timeEntryCount: Int = 0,
        thoughtCount: Int = 0,
        codexThreads: Int = 0,
        claudeThreads: Int = 0,
        chatgptThreads: Int = 0,
        autoLinks: Int = 0,
        suggestedLinks: Int = 0,
        inboxCount: Int = 0,
        failures: [String] = [],
        warnings: [String] = [],
        chatgptWaiting: Bool = false,
        reviewMarkdown: String = ""
    ) {
        self.timeEntryCount = timeEntryCount
        self.thoughtCount = thoughtCount
        self.codexThreads = codexThreads
        self.claudeThreads = claudeThreads
        self.chatgptThreads = chatgptThreads
        self.autoLinks = autoLinks
        self.suggestedLinks = suggestedLinks
        self.inboxCount = inboxCount
        self.failures = failures
        self.warnings = warnings
        self.chatgptWaiting = chatgptWaiting
        self.reviewMarkdown = reviewMarkdown
    }

    public var summaryCard: String {
        var lines = [
            "今日上下文同步完成",
            "",
            "iPhone 时间记录：\(timeEntryCount) 条",
            "ThoughtNote：\(thoughtCount) 条",
            "Codex：\(codexThreads) 个会话",
            "Claude：\(claudeThreads) 个会话",
            "ChatGPT：\(chatgptThreads) 个会话",
            "自动关联：\(autoLinks) 个",
            "待确认：\(suggestedLinks + inboxCount) 个",
            "失败：\(failures.count) 个"
        ]
        if chatgptWaiting {
            lines.append("")
            lines.append("Codex / Claude 已完成")
            lines.append("ChatGPT：等待浏览器扩展")
        }
        if !failures.isEmpty {
            lines.append("")
            lines.append(contentsOf: failures.map { "错误：\($0)" })
        }
        return lines.joined(separator: "\n")
    }
}

public enum CollectorProcessRunner {
    public struct RunOutput: Sendable {
        public var exitCode: Int32
        public var stdout: String
        public var stderr: String
    }

    /// Runs process with explicit argument array (never shell-string concatenation).
    public static func run(
        executable: String,
        arguments: [String],
        currentDirectory: String? = nil,
        timeoutSeconds: TimeInterval = 600
    ) throws -> RunOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw CollectorRunnerError.timeout
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return RunOutput(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}

public enum CollectorRunnerError: Error, LocalizedError {
    case timeout
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .timeout: return "Collector 超时"
        case .failed(let s): return s
        }
    }
}

public struct SessionCollectorClient {
    public var archiveRepoPath: String
    public var pythonPath: String

    public init(archiveRepoPath: String, pythonPath: String = "/usr/bin/python3") {
        self.archiveRepoPath = archiveRepoPath
        self.pythonPath = pythonPath
    }

    public func run(
        source: ContextSource,
        startAt: Date,
        endAt: Date,
        outputRoot: String
    ) throws -> CollectorResult {
        let requestId = UUID().uuidString
        let resultPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("pee-collector-\(requestId).json").path
        let cli = (archiveRepoPath as NSString).appendingPathComponent("tools/collector_cli.py")
        let started = Date()
        let output = try CollectorProcessRunner.run(
            executable: pythonPath,
            arguments: [
                cli,
                "--source", source.rawValue,
                "--start-at", ISO8601Codec.string(from: startAt),
                "--end-at", ISO8601Codec.string(from: endAt),
                "--output-root", outputRoot,
                "--result-json", resultPath
            ],
            currentDirectory: archiveRepoPath
        )
        if FileManager.default.fileExists(atPath: resultPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: resultPath)),
           let result = try? ISO8601Codec.decoder.decode(CollectorResult.self, from: data)
        {
            return result
        }
        let finished = Date()
        let status: CollectorStatus = output.exitCode == 0 ? .succeeded : .failed
        return CollectorResult(
            requestId: requestId,
            source: source,
            status: status,
            startedAt: started,
            finishedAt: finished,
            warnings: output.stdout.isEmpty ? [] : [String(output.stdout.prefix(200))],
            errors: output.exitCode == 0 ? [] : [String(output.stderr.prefix(400))]
        )
    }
}

public struct ChatGPTCompanionClient {
    public var baseURL: URL
    public var session: URLSession

    public init(baseURL: URL = URL(string: "http://127.0.0.1:18795")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func health() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    public func createPEEJob(archiveRoot: String, baselineDate: String, requestId: String) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent("jobs/pee-sync")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "archiveRoot": archiveRoot,
            "baselineDate": baselineDate,
            "requestId": requestId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CollectorRunnerError.failed("ChatGPT companion 无响应")
        }
        if http.statusCode == 404 {
            throw CollectorRunnerError.failed("companion 不支持 /jobs/pee-sync，请升级归档项目")
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw CollectorRunnerError.failed("ChatGPT 任务创建失败：\(msg)")
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    public func currentJob() async throws -> [String: Any]? {
        let url = baseURL.appendingPathComponent("jobs/current")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    public func mapToCollectorResult(job: [String: Any], requestId: String, startedAt: Date) -> CollectorResult {
        let statusRaw = (job["status"] as? String) ?? "queued"
        let status: CollectorStatus = {
            switch statusRaw {
            case "completed", "succeeded": return .succeeded
            case "failed": return .failed
            case "waitingForBrowser", "queued", "paused": return .waitingForBrowser
            case "running", "partial": return .partial
            case "cancelled": return .cancelled
            default: return .waitingForBrowser
            }
        }()
        let items = job["items"] as? [[String: Any]] ?? []
        let exported = items.filter { ($0["status"] as? String) == "exported" }.count
        return CollectorResult(
            requestId: requestId,
            source: .chatgpt,
            status: status,
            startedAt: startedAt,
            finishedAt: Date(),
            threadsFound: items.count,
            threadsChanged: exported,
            messagesImported: 0,
            outputPaths: items.compactMap { $0["outputPath"] as? String },
            warnings: status == .waitingForBrowser
                ? ["ChatGPT 同步等待中：请打开已登录 ChatGPT 的 Chrome / Edge。"]
                : [],
            errors: status == .failed ? ["ChatGPT 同步失败"] : []
        )
    }
}
