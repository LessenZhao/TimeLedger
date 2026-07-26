import Foundation

public struct SourceArchiveLocation: Codable, Sendable, Hashable {
    public var source: ContextSource
    public var eventsPath: String
    public var threadsPath: String

    public init(source: ContextSource, eventsPath: String, threadsPath: String) {
        self.source = source
        self.eventsPath = eventsPath
        self.threadsPath = threadsPath
    }
}

public struct PreparedMessage: Codable, Sendable, Hashable, Identifiable {
    public var id: String { reference.id }
    public var reference: MessageReference
    public var text: String

    public init(reference: MessageReference, text: String) {
        self.reference = reference
        self.text = text
    }
}

public struct PreparedArchiveDay: Codable, Sendable, Hashable {
    public var date: String
    public var sessions: [SourceSessionRecord]
    public var slices: [DailySessionSlice]
    public var messages: [PreparedMessage]
    public var coverage: SourceCoverage
    public var diagnostics: [ProposalDiagnostic]
    public var sourceDigest: String

    public init(
        date: String,
        sessions: [SourceSessionRecord],
        slices: [DailySessionSlice],
        messages: [PreparedMessage],
        coverage: SourceCoverage,
        diagnostics: [ProposalDiagnostic],
        sourceDigest: String
    ) {
        self.date = date
        self.sessions = sessions
        self.slices = slices
        self.messages = messages
        self.coverage = coverage
        self.diagnostics = diagnostics
        self.sourceDigest = sourceDigest
    }
}

public enum ArchiveEvidenceReaderError: Error, Equatable {
    case unreadableFile(String)
    case invalidJSON(path: String, line: Int)
    case invalidDate(path: String, line: Int, value: String)
}

public struct ArchiveEvidenceReader: Sendable {
    public init() {}

    public func prepareDay(
        location: SourceArchiveLocation,
        date: Date,
        cutoffAt: Date,
        calendar: Calendar,
        processorThreadIds: Set<String>
    ) throws -> PreparedArchiveDay {
        let allMessages = try readMessages(path: location.eventsPath, source: location.source)
        let threadRows = try readThreadRows(path: location.threadsPath)
        let metadataByThread = Dictionary(threadRows.map { ($0.threadId, $0) }, uniquingKeysWith: { _, newest in newest })
        let window = NaturalDayWindow.forDate(date, calendar: calendar)
        let dateString = localDateString(window.start, calendar: calendar)
        let selectedMessages = allMessages
            .filter { window.contains($0.reference.createdAt) && $0.reference.createdAt <= cutoffAt }
            .sorted(by: messageOrder)
        let selectedThreadIds = Set(selectedMessages.map(\.reference.threadId))
        let allMessagesByThread = Dictionary(grouping: allMessages, by: \.reference.threadId)

        var diagnostics: [ProposalDiagnostic] = []
        for message in selectedMessages {
            if message.reference.sourceFile.isEmpty {
                diagnostics.append(diagnostic(
                    code: "archive_missing_source_file",
                    message: "Canonical archive message is missing source_file.",
                    relatedIds: [message.id]
                ))
            }
            if message.reference.sourceLine < 0 {
                diagnostics.append(diagnostic(
                    code: "archive_missing_source_line",
                    message: "Canonical archive message is missing source_line.",
                    relatedIds: [message.id]
                ))
            }
        }

        var sessions: [SourceSessionRecord] = []
        var slices: [DailySessionSlice] = []
        for threadId in selectedThreadIds.sorted() {
            let dayMessages = selectedMessages.filter { $0.reference.threadId == threadId }
            guard !dayMessages.isEmpty else { continue }
            let conversation = (allMessagesByThread[threadId] ?? []).sorted(by: messageOrder)
            let metadata = metadataByThread[threadId]
            let sessionId = EvolutionStableID.sourceSession(source: location.source, externalThreadId: threadId)
            let createdAt = parsedDate(metadata?.createdAt)
                ?? conversation.map(\.reference.createdAt).min()
                ?? dayMessages[0].reference.createdAt
            let updatedAt = parsedDate(metadata?.updatedAt)
                ?? conversation.map(\.reference.createdAt).max()
                ?? dayMessages[dayMessages.count - 1].reference.createdAt
            let session = SourceSessionRecord(
                id: sessionId,
                source: location.source,
                externalThreadId: threadId,
                title: nonEmpty(metadata?.title) ?? dayMessages[0].reference.excerpt,
                cwd: nonEmpty(metadata?.cwd),
                createdAt: createdAt,
                updatedAt: updatedAt,
                canonicalEventsPath: location.eventsPath,
                canonicalThreadsPath: location.threadsPath,
                contentHash: ContentHasher.hashParts(conversation.map(\.reference.id).sorted())
            )
            let isProcessor = processorThreadIds.contains(threadId)
                || processorThreadIds.contains(sessionId)
                || processorCommandDetected(in: conversation)
            let classification: DailySourceClassification = isProcessor ? .processor : .pending
            let slice = DailySessionSlice(
                id: EvolutionStableID.dailySession(date: dateString, sessionId: sessionId),
                date: dateString,
                sessionId: sessionId,
                classification: classification,
                projectIds: [],
                messageReferences: dayMessages.map(\.reference),
                exclusionReason: nil
            )
            sessions.append(session)
            slices.append(slice)
        }

        sessions.sort { $0.id < $1.id }
        slices.sort { $0.sessionId < $1.sessionId }
        diagnostics.sort { ($0.code, $0.id) < ($1.code, $1.id) }
        let processors = slices.filter { $0.classification == .processor }.map(\.sessionId).sorted()
        let pending = slices.filter { $0.classification == .pending }.map(\.sessionId).sorted()
        let coverage = SourceCoverage(
            expectedSessionCount: slices.count,
            includedSessionIds: [],
            pendingSessionIds: pending,
            excludedSessionIds: [],
            processorSessionIds: processors
        )
        let sourceDigest = ContentHasher.hashParts(
            [ISO8601Codec.string(from: cutoffAt)] + selectedMessages.map(\.reference.id).sorted()
        )

        return PreparedArchiveDay(
            date: dateString,
            sessions: sessions,
            slices: slices,
            messages: selectedMessages,
            coverage: coverage,
            diagnostics: diagnostics,
            sourceDigest: sourceDigest
        )
    }

    public func conversation(session: SourceSessionRecord) throws -> [PreparedMessage] {
        try readMessages(path: session.canonicalEventsPath, source: session.source)
            .filter { $0.reference.threadId == session.externalThreadId }
            .sorted(by: messageOrder)
    }

    public func contains(_ reference: MessageReference, in session: SourceSessionRecord) throws -> Bool {
        guard reference.source == session.source,
              reference.threadId == session.externalThreadId else {
            return false
        }
        return try conversation(session: session).contains {
            reference.matchesCanonical($0.reference)
        }
    }

    private func readMessages(path: String, source: ContextSource) throws -> [PreparedMessage] {
        let rows: [ArchiveEventRow] = try readJSONLines(path: path)
        return try rows.enumerated().map { offset, row in
            guard let createdAt = ISO8601Codec.date(from: row.createdAt) else {
                throw ArchiveEvidenceReaderError.invalidDate(path: path, line: offset + 1, value: row.createdAt)
            }
            let sourceFile = row.sourceFile ?? ""
            let sourceLine = row.sourceLine ?? -1
            let contentHash = ContentHasher.hash(row.text)
            let reference = MessageReference(
                id: EvolutionStableID.message(
                    source: source,
                    threadId: row.threadId,
                    eventId: row.eventId,
                    sourceFile: sourceFile,
                    sourceLine: sourceLine,
                    contentHash: contentHash
                ),
                source: source,
                threadId: row.threadId,
                eventId: row.eventId,
                createdAt: createdAt,
                role: ContextMessageRole(rawValue: row.role) ?? .other,
                sourceFile: sourceFile,
                sourceLine: sourceLine,
                excerpt: String(row.text.prefix(160)),
                contentHash: contentHash
            )
            return PreparedMessage(reference: reference, text: row.text)
        }
    }

    private func readThreadRows(path: String) throws -> [ArchiveThreadRow] {
        try readJSONLines(path: path)
    }

    private func readJSONLines<Row: Decodable>(path: String) throws -> [Row] {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8) else {
            throw ArchiveEvidenceReaderError.unreadableFile(path)
        }
        let lines = contents.split(whereSeparator: \.isNewline)
        let decoder = JSONDecoder()
        return try lines.enumerated().map { offset, line in
            do {
                return try decoder.decode(Row.self, from: Data(line.utf8))
            } catch {
                throw ArchiveEvidenceReaderError.invalidJSON(path: path, line: offset + 1)
            }
        }
    }

    private func processorCommandDetected(in messages: [PreparedMessage]) -> Bool {
        guard let firstUserText = messages.first(where: { $0.reference.role == .user })?.text else {
            return false
        }
        let normalized = firstUserText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("$evolution-ledger")
            || normalized.hasPrefix("[$evolution-ledger]")
    }

    private func diagnostic(code: String, message: String, relatedIds: [String]) -> ProposalDiagnostic {
        ProposalDiagnostic(
            id: EvolutionStableID.proposalDiagnostic(code: code, message: message, relatedIds: relatedIds),
            severity: .warning,
            code: code,
            message: message,
            relatedIds: relatedIds
        )
    }

    private func localDateString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func parsedDate(_ raw: String?) -> Date? {
        raw.flatMap(ISO8601Codec.date(from:))
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func messageOrder(_ lhs: PreparedMessage, _ rhs: PreparedMessage) -> Bool {
        if lhs.reference.createdAt != rhs.reference.createdAt {
            return lhs.reference.createdAt < rhs.reference.createdAt
        }
        if lhs.reference.sourceLine != rhs.reference.sourceLine {
            return lhs.reference.sourceLine < rhs.reference.sourceLine
        }
        return lhs.reference.id < rhs.reference.id
    }
}

private struct ArchiveEventRow: Decodable {
    var eventId: String
    var threadId: String
    var createdAt: String
    var role: String
    var text: String
    var sourceFile: String?
    var sourceLine: Int?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case threadId = "thread_id"
        case createdAt = "created_at"
        case role
        case text
        case sourceFile = "source_file"
        case sourceLine = "source_line"
    }
}

private struct ArchiveThreadRow: Decodable {
    var threadId: String
    var title: String?
    var cwd: String?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case title
        case cwd
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
