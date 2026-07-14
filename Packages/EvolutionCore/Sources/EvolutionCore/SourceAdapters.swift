import Foundation

// MARK: - Raw source adapters → ContextThread / ContextMessage / ContextEvent

public enum SourceAdapterError: Error, LocalizedError, Sendable {
    case invalidJSONL(String)
    case missingFile(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSONL(let s): return "JSONL 无效: \(s)"
        case .missingFile(let s): return "缺少文件: \(s)"
        }
    }
}

public struct NormalizedContextPackage: Sendable {
    public var threads: [ContextThread]
    public var messages: [ContextMessage]
    public var events: [ContextEvent]

    public init(threads: [ContextThread] = [], messages: [ContextMessage] = [], events: [ContextEvent] = []) {
        self.threads = threads
        self.messages = messages
        self.events = events
    }
}

public enum CodexClaudeAdapter {
    private struct ThreadIndexRow: Decodable {
        var thread_id: String
        var title: String?
        var cwd: String?
        var created_at: String?
        var updated_at: String?
        var preview: String?
        var source_file: String?
        var model: String?
    }

    private struct EventRow: Decodable {
        var event_id: String
        var thread_id: String
        var role: String
        var text: String?
        var created_at: String?
        var source_file: String?
        var source_line: Int?
    }

    public static func normalize(
        source: ContextSource,
        outputRoot: URL,
        dayWindow: NaturalDayWindow?,
        importedAt: Date = Date()
    ) throws -> NormalizedContextPackage {
        let threadsURL = outputRoot.appendingPathComponent("threads-index.jsonl")
        let eventsURL = outputRoot.appendingPathComponent("events.jsonl")
        guard FileManager.default.fileExists(atPath: threadsURL.path) else {
            throw SourceAdapterError.missingFile(threadsURL.path)
        }

        let threadRows: [ThreadIndexRow] = try readJSONL(threadsURL)
        let eventRows: [EventRow] = FileManager.default.fileExists(atPath: eventsURL.path)
            ? (try readJSONL(eventsURL))
            : []

        var messagesByThread: [String: [EventRow]] = [:]
        for row in eventRows {
            messagesByThread[row.thread_id, default: []].append(row)
        }

        var threads: [ContextThread] = []
        var messages: [ContextMessage] = []
        var events: [ContextEvent] = []

        for row in threadRows {
            let created = parseDate(row.created_at) ?? importedAt
            let updated = parseDate(row.updated_at) ?? created
            let threadMessages = messagesByThread[row.thread_id] ?? []
            let messageTimes = threadMessages.compactMap { parseDate($0.created_at) }

            if let window = dayWindow {
                let active = window.isThreadActiveOnDay(
                    createdAt: created,
                    updatedAt: updated,
                    messageTimes: messageTimes
                )
                if !active { continue }
            }

            let title = row.title?.isEmpty == false ? row.title! : (row.preview ?? row.thread_id)
            let projectHint: String? = {
                guard let cwd = row.cwd, !cwd.isEmpty else { return nil }
                return URL(fileURLWithPath: cwd).lastPathComponent
            }()
            let hash = ContentHasher.hashParts([
                source.rawValue,
                row.thread_id,
                title,
                row.updated_at ?? ""
            ])
            let thread = ContextThread(
                id: "\(source.rawValue):\(row.thread_id)",
                source: source,
                externalId: row.thread_id,
                title: title,
                createdAt: created,
                updatedAt: updated,
                cwd: row.cwd,
                projectHint: projectHint,
                rawPath: row.source_file,
                contentHash: hash,
                importedAt: importedAt
            )
            threads.append(thread)

            for msg in threadMessages {
                let text = msg.text ?? ""
                let createdMsg = parseDate(msg.created_at) ?? created
                let role: ContextMessageRole = {
                    switch msg.role {
                    case "user": return .user
                    case "assistant": return .assistant
                    case "system": return .system
                    default: return .other
                    }
                }()
                messages.append(ContextMessage(
                    id: "\(source.rawValue):\(msg.event_id)",
                    threadId: thread.id,
                    externalId: msg.event_id,
                    role: role,
                    createdAt: createdMsg,
                    text: text,
                    contentHash: ContentHasher.hash(text)
                ))
            }

            let started = messageTimes.min() ?? created
            let ended = messageTimes.max() ?? updated
            let summary: String = {
                let userTexts = threadMessages.filter { $0.role == "user" }.compactMap(\.text)
                return userTexts.first.map { String($0.prefix(160)) } ?? (row.preview ?? "")
            }()
            let rawRef = "raw/\(source.rawValue)/threads-index.jsonl#\(row.thread_id)"
            events.append(ContextEvent(
                id: "\(source.rawValue):event:\(row.thread_id)",
                source: source,
                threadId: thread.id,
                startedAt: started,
                endedAt: ended,
                title: title,
                summary: summary,
                projectHint: projectHint ?? row.cwd,
                rawReference: rawRef,
                importedAt: importedAt
            ))
        }

        return NormalizedContextPackage(threads: threads, messages: messages, events: events)
    }

    private static func readJSONL<T: Decodable>(_ url: URL) throws -> [T] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var rows: [T] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            let data = Data(line.utf8)
            do {
                rows.append(try JSONDecoder().decode(T.self, from: data))
            } catch {
                throw SourceAdapterError.invalidJSONL("\(url.lastPathComponent):\(index + 1)")
            }
        }
        return rows
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return ISO8601Codec.date(from: raw)
    }
}

public enum ChatGPTAdapter {
    private struct ManifestEntry: Decodable {
        var createdAt: String
        var lastActivityAt: String
        var lastSnapshotFilename: String
    }

    public static func normalize(
        archiveRoot: URL,
        dayWindow: NaturalDayWindow?,
        importedAt: Date = Date()
    ) throws -> NormalizedContextPackage {
        let indexURL = archiveRoot.appendingPathComponent("_archive-index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            throw SourceAdapterError.missingFile(indexURL.path)
        }
        let data = try Data(contentsOf: indexURL)
        let manifest = try JSONDecoder().decode([String: ManifestEntry].self, from: data)

        var threads: [ContextThread] = []
        var events: [ContextEvent] = []

        for (conversationId, entry) in manifest {
            let created = ISO8601Codec.date(from: entry.createdAt) ?? importedAt
            let updated = ISO8601Codec.date(from: entry.lastActivityAt) ?? created
            if let window = dayWindow {
                let active = window.isThreadActiveOnDay(
                    createdAt: created,
                    updatedAt: updated,
                    messageTimes: [updated]
                )
                if !active { continue }
            }

            let title = entry.lastSnapshotFilename
                .replacingOccurrences(of: #"^\d{4}-\d{2}-\d{2}--"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: ".md", with: "")
            let rawPath = archiveRoot.appendingPathComponent(entry.lastSnapshotFilename).path
            let hash = ContentHasher.hashParts(["chatgpt", conversationId, entry.lastActivityAt])
            let thread = ContextThread(
                id: "chatgpt:\(conversationId)",
                source: .chatgpt,
                externalId: conversationId,
                title: title,
                createdAt: created,
                updatedAt: updated,
                cwd: nil,
                projectHint: nil,
                rawPath: rawPath,
                contentHash: hash,
                importedAt: importedAt
            )
            threads.append(thread)
            events.append(ContextEvent(
                id: "chatgpt:event:\(conversationId)",
                source: .chatgpt,
                threadId: thread.id,
                startedAt: created,
                endedAt: updated,
                title: title,
                summary: "ChatGPT 会话 · 最近活动 \(entry.lastActivityAt)",
                projectHint: nil,
                rawReference: rawPath,
                importedAt: importedAt
            ))
        }

        return NormalizedContextPackage(threads: threads, messages: [], events: events)
    }
}
