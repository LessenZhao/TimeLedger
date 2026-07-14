import Foundation

/// In-memory mirror ledger. Mutations require `connectionState == .connected` (or `.syncing` for inbound apply).
public struct MirrorLedgerEngine: Sendable {
    public var connectionState: MirrorConnectionState
    public var phoneDeviceId: String?
    public var macDeviceId: String
    public var snapshotRevision: Int
    public var cursor: MirrorCursor?
    public var projects: [MirrorProject]
    public var timeEntries: [MirrorTimeEntry]
    public var thoughts: [MirrorThought]
    /// Local mutations waiting to push to phone.
    public var pendingOutbound: [AnySyncEnvelope]
    public var lastError: String?

    public init(
        connectionState: MirrorConnectionState = .disconnected,
        phoneDeviceId: String? = nil,
        macDeviceId: String = UUID().uuidString,
        snapshotRevision: Int = 0,
        cursor: MirrorCursor? = nil,
        projects: [MirrorProject] = [],
        timeEntries: [MirrorTimeEntry] = [],
        thoughts: [MirrorThought] = [],
        pendingOutbound: [AnySyncEnvelope] = [],
        lastError: String? = nil
    ) {
        self.connectionState = connectionState
        self.phoneDeviceId = phoneDeviceId
        self.macDeviceId = macDeviceId
        self.snapshotRevision = snapshotRevision
        self.cursor = cursor
        self.projects = projects
        self.timeEntries = timeEntries
        self.thoughts = thoughts
        self.pendingOutbound = pendingOutbound
        self.lastError = lastError
    }

    public var isConnected: Bool {
        connectionState == .connected || connectionState == .syncing
    }

    public var canBookkeep: Bool {
        connectionState == .connected && cursor != nil
    }

    public mutating func disconnect() {
        connectionState = .disconnected
        // Keep last snapshot for display? Spec: no independent bookkeeping — clear mutable session.
        phoneDeviceId = nil
        cursor = nil
        projects = []
        timeEntries = []
        thoughts = []
        snapshotRevision = 0
        pendingOutbound = []
        lastError = nil
    }

    /// Establish mirror from phone full snapshot (file or network).
    public mutating func connect(with snapshot: MirrorLedgerSnapshot) {
        connectionState = .connected
        phoneDeviceId = snapshot.phoneDeviceId
        snapshotRevision = snapshot.snapshotRevision
        cursor = snapshot.cursor
        projects = snapshot.projects.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
        timeEntries = snapshot.timeEntries.sorted { $0.startAt < $1.startAt }
        thoughts = snapshot.thoughts.sorted { $0.capturedAt < $1.capturedAt }
        pendingOutbound = []
        lastError = nil
    }

    public func unclassifiedDuration(now: Date = Date()) -> TimeInterval {
        cursor?.unclassifiedDuration(now: now) ?? 0
    }

    public func drafts(on day: Date, calendar: Calendar = .current) -> [MirrorTimeEntry] {
        entries(on: day, calendar: calendar).filter(\.isDraft)
    }

    public func confirmed(on day: Date, calendar: Calendar = .current) -> [MirrorTimeEntry] {
        entries(on: day, calendar: calendar).filter(\.isConfirmed)
    }

    public func entries(on day: Date, calendar: Calendar = .current) -> [MirrorTimeEntry] {
        let window = NaturalDayWindow.forDate(day, calendar: calendar)
        return timeEntries
            .filter { $0.startAt < window.end && $0.endAt > window.start }
            .sorted { $0.startAt < $1.startAt }
    }

    public mutating func quickRecord(projectId: String, now: Date = Date()) throws -> MirrorTimeEntry {
        try requireBookkeep()
        guard var cursor else { throw MirrorLedgerError.notConnected }
        guard let project = projects.first(where: { $0.id == projectId }) else {
            throw MirrorLedgerError.projectNotFound
        }
        guard now > cursor.cursorAt else { throw MirrorLedgerError.emptySegment }
        try validateNoOverlap(start: cursor.cursorAt, end: now, excludingId: nil)

        let entry = MirrorTimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: cursor.cursorAt,
            endAt: now,
            status: "draft",
            revision: 1,
            createdAt: now,
            updatedAt: now
        )
        timeEntries.append(entry)
        cursor.cursorAt = now
        cursor.updatedAt = now
        cursor.revision += 1
        self.cursor = cursor
        try queueOutbound(entry: entry)
        try queueOutboundCursor(cursor)
        return entry
    }

    public mutating func confirmEntry(id: String, now: Date = Date()) throws {
        try requireBookkeep()
        guard let idx = timeEntries.firstIndex(where: { $0.id == id }) else {
            throw MirrorLedgerError.entryNotFound
        }
        timeEntries[idx].status = "confirmed"
        timeEntries[idx].revision += 1
        timeEntries[idx].updatedAt = now
        try queueOutbound(entry: timeEntries[idx])
    }

    public mutating func unconfirmEntry(id: String, now: Date = Date()) throws {
        try requireBookkeep()
        guard let idx = timeEntries.firstIndex(where: { $0.id == id }) else {
            throw MirrorLedgerError.entryNotFound
        }
        timeEntries[idx].status = "draft"
        timeEntries[idx].revision += 1
        timeEntries[idx].updatedAt = now
        try queueOutbound(entry: timeEntries[idx])
    }

    public mutating func deleteDraft(id: String) throws {
        try requireBookkeep()
        guard let idx = timeEntries.firstIndex(where: { $0.id == id }) else {
            throw MirrorLedgerError.entryNotFound
        }
        guard timeEntries[idx].isDraft else { throw MirrorLedgerError.cannotModifyConfirmed }
        let removed = timeEntries.remove(at: idx)
        let env = AnySyncEnvelope(
            deviceId: macDeviceId,
            entityType: .timeEntry,
            entityId: removed.id,
            operation: .delete,
            revision: removed.revision + 1,
            updatedAt: Date(),
            payloadJSON: "{}"
        )
        pendingOutbound.append(env)
    }

    /// Edit draft time range / note. Confirmed entries must be unconfirmed first.
    public mutating func updateDraftEntry(
        id: String,
        startAt: Date,
        endAt: Date,
        note: String,
        now: Date = Date()
    ) throws {
        try requireBookkeep()
        guard let idx = timeEntries.firstIndex(where: { $0.id == id }) else {
            throw MirrorLedgerError.entryNotFound
        }
        guard timeEntries[idx].isDraft else { throw MirrorLedgerError.cannotModifyConfirmed }
        try validateNoOverlap(start: startAt, end: endAt, excludingId: id)
        timeEntries[idx].startAt = startAt
        timeEntries[idx].endAt = endAt
        timeEntries[idx].note = note
        timeEntries[idx].revision += 1
        timeEntries[idx].updatedAt = now
        try queueOutbound(entry: timeEntries[idx])
    }

    public mutating func addThought(body: String, now: Date = Date()) throws -> MirrorThought {
        try requireBookkeep()
        let thought = MirrorThought(body: body, capturedAt: now, anchorAt: now, linkSource: "none")
        // Auto-link to covering entry
        if let entry = timeEntries.first(where: { $0.startAt <= now && now < $0.endAt }) {
            var linked = thought
            linked.linkedEntryId = entry.id
            linked.linkSource = "auto"
            thoughts.append(linked)
            try queueOutbound(thought: linked)
            return linked
        }
        thoughts.append(thought)
        try queueOutbound(thought: thought)
        return thought
    }

    /// Apply phone→Mac incremental envelopes while connected.
    public mutating func applyInbound(envelopes: [AnySyncEnvelope]) throws {
        guard isConnected else { throw MirrorLedgerError.notConnected }
        connectionState = .syncing
        defer { connectionState = .connected }

        for env in envelopes {
            switch env.entityType {
            case .timeEntry:
                if env.operation == .delete {
                    timeEntries.removeAll { $0.id == env.entityId }
                    continue
                }
                let p = try env.decodePayload(TimeEntrySyncPayload.self)
                upsertEntry(from: p, revision: env.revision)
            case .thoughtNote:
                if env.operation == .delete {
                    thoughts.removeAll { $0.id == env.entityId }
                    continue
                }
                let p = try env.decodePayload(ThoughtNoteSyncPayload.self)
                upsertThought(from: p, revision: env.revision)
            case .project:
                let p = try env.decodePayload(ProjectSyncPayload.self)
                upsertProject(from: p, revision: env.revision)
            case .timeCursor:
                let p = try env.decodePayload(TimeCursorSyncPayload.self)
                if let current = cursor, p.revision < current.revision { continue }
                cursor = MirrorCursor(cursorAt: p.cursorAt, updatedAt: p.updatedAt, revision: p.revision)
            default:
                break
            }
        }
    }

    public mutating func drainOutbound() -> [AnySyncEnvelope] {
        let batch = pendingOutbound
        pendingOutbound = []
        return batch
    }

    public func makeSnapshot() -> MirrorLedgerSnapshot? {
        guard let cursor, let phoneDeviceId else { return nil }
        return MirrorLedgerSnapshot(
            phoneDeviceId: phoneDeviceId,
            macDeviceId: macDeviceId,
            snapshotRevision: snapshotRevision,
            cursor: cursor,
            projects: projects,
            timeEntries: timeEntries,
            thoughts: thoughts
        )
    }

    // MARK: - Private

    private func requireBookkeep() throws {
        guard canBookkeep else { throw MirrorLedgerError.notConnected }
    }

    private func validateNoOverlap(start: Date, end: Date, excludingId: String?) throws {
        guard end > start else { throw MirrorLedgerError.invalidRange }
        for entry in timeEntries {
            if let excludingId, entry.id == excludingId { continue }
            if start < entry.endAt && entry.startAt < end {
                throw MirrorLedgerError.overlap
            }
        }
    }

    private mutating func upsertEntry(from p: TimeEntrySyncPayload, revision: Int) {
        let entry = MirrorTimeEntry(
            id: p.id,
            projectId: p.projectId,
            projectNameSnapshot: p.projectNameSnapshot,
            categoryNameSnapshot: p.categoryNameSnapshot,
            startAt: p.startAt,
            endAt: p.endAt,
            note: p.note,
            status: p.status,
            revision: revision,
            createdAt: p.createdAt,
            updatedAt: p.updatedAt
        )
        if let idx = timeEntries.firstIndex(where: { $0.id == p.id }) {
            if timeEntries[idx].revision > revision { return }
            timeEntries[idx] = entry
        } else {
            timeEntries.append(entry)
        }
    }

    private mutating func upsertThought(from p: ThoughtNoteSyncPayload, revision: Int) {
        let thought = MirrorThought(
            id: p.id,
            body: p.body,
            capturedAt: p.capturedAt,
            anchorAt: p.anchorAt,
            linkedEntryId: p.linkedEntryId,
            linkSource: p.linkSource,
            revision: revision,
            createdAt: p.createdAt,
            updatedAt: p.updatedAt
        )
        if let idx = thoughts.firstIndex(where: { $0.id == p.id }) {
            if thoughts[idx].revision > revision { return }
            thoughts[idx] = thought
        } else {
            thoughts.append(thought)
        }
    }

    private mutating func upsertProject(from p: ProjectSyncPayload, revision: Int) {
        let project = MirrorProject(
            id: p.id,
            name: p.name,
            categoryName: p.categoryName,
            isArchived: p.isArchived,
            revision: revision,
            updatedAt: p.updatedAt
        )
        if let idx = projects.firstIndex(where: { $0.id == p.id }) {
            if projects[idx].revision > revision { return }
            projects[idx] = project
        } else {
            projects.append(project)
        }
    }

    private mutating func queueOutbound(entry: MirrorTimeEntry) throws {
        let payload = TimeEntrySyncPayload(
            id: entry.id,
            projectId: entry.projectId,
            projectNameSnapshot: entry.projectNameSnapshot,
            categoryNameSnapshot: entry.categoryNameSnapshot,
            startAt: entry.startAt,
            endAt: entry.endAt,
            note: entry.note,
            status: entry.status,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt
        )
        pendingOutbound.append(try AnySyncEnvelope(
            deviceId: macDeviceId,
            entityType: .timeEntry,
            entityId: entry.id,
            revision: entry.revision,
            updatedAt: entry.updatedAt,
            payload: payload
        ))
    }

    private mutating func queueOutbound(thought: MirrorThought) throws {
        let payload = ThoughtNoteSyncPayload(
            id: thought.id,
            body: thought.body,
            capturedAt: thought.capturedAt,
            anchorAt: thought.anchorAt,
            linkedEntryId: thought.linkedEntryId,
            linkSource: thought.linkSource,
            createdAt: thought.createdAt,
            updatedAt: thought.updatedAt
        )
        pendingOutbound.append(try AnySyncEnvelope(
            deviceId: macDeviceId,
            entityType: .thoughtNote,
            entityId: thought.id,
            revision: thought.revision,
            updatedAt: thought.updatedAt,
            payload: payload
        ))
    }

    private mutating func queueOutboundCursor(_ cursor: MirrorCursor) throws {
        let payload = TimeCursorSyncPayload(
            cursorAt: cursor.cursorAt,
            updatedAt: cursor.updatedAt,
            revision: cursor.revision
        )
        pendingOutbound.append(try AnySyncEnvelope(
            deviceId: macDeviceId,
            entityType: .timeCursor,
            entityId: "cursor",
            revision: cursor.revision,
            updatedAt: cursor.updatedAt,
            payload: payload
        ))
    }
}

public struct TimeCursorSyncPayload: Codable, Sendable, Hashable {
    public var cursorAt: Date
    public var updatedAt: Date
    public var revision: Int

    public init(cursorAt: Date, updatedAt: Date, revision: Int) {
        self.cursorAt = cursorAt
        self.updatedAt = updatedAt
        self.revision = revision
    }
}

/// Converts phone SyncBatchFile / TimeLedger export into a mirror snapshot.
public enum MirrorSnapshotBuilder {
    public static func fromSyncBatch(_ batch: SyncBatchFile, phoneDeviceId: String? = nil) throws -> MirrorLedgerSnapshot {
        var projects: [MirrorProject] = []
        var entries: [MirrorTimeEntry] = []
        var thoughts: [MirrorThought] = []
        var cursor = MirrorCursor(cursorAt: Date(), revision: 1)

        for env in batch.envelopes {
            switch env.entityType {
            case .project:
                let p = try env.decodePayload(ProjectSyncPayload.self)
                projects.append(MirrorProject(
                    id: p.id,
                    name: p.name,
                    categoryName: p.categoryName,
                    isArchived: p.isArchived,
                    revision: env.revision,
                    updatedAt: p.updatedAt
                ))
            case .timeEntry:
                let p = try env.decodePayload(TimeEntrySyncPayload.self)
                entries.append(MirrorTimeEntry(
                    id: p.id,
                    projectId: p.projectId,
                    projectNameSnapshot: p.projectNameSnapshot,
                    categoryNameSnapshot: p.categoryNameSnapshot,
                    startAt: p.startAt,
                    endAt: p.endAt,
                    note: p.note,
                    status: p.status,
                    revision: env.revision,
                    createdAt: p.createdAt,
                    updatedAt: p.updatedAt
                ))
            case .thoughtNote:
                let p = try env.decodePayload(ThoughtNoteSyncPayload.self)
                thoughts.append(MirrorThought(
                    id: p.id,
                    body: p.body,
                    capturedAt: p.capturedAt,
                    anchorAt: p.anchorAt,
                    linkedEntryId: p.linkedEntryId,
                    linkSource: p.linkSource,
                    revision: env.revision,
                    createdAt: p.createdAt,
                    updatedAt: p.updatedAt
                ))
            case .timeCursor:
                let p = try env.decodePayload(TimeCursorSyncPayload.self)
                cursor = MirrorCursor(cursorAt: p.cursorAt, updatedAt: p.updatedAt, revision: p.revision)
            default:
                break
            }
        }

        // If no cursor envelope, derive from max entry end or now
        if !batch.envelopes.contains(where: { $0.entityType == .timeCursor }) {
            let maxEnd = entries.map(\.endAt).max() ?? Date()
            cursor = MirrorCursor(cursorAt: maxEnd, updatedAt: Date(), revision: 1)
        }

        return MirrorLedgerSnapshot(
            phoneDeviceId: phoneDeviceId ?? batch.deviceId,
            snapshotRevision: batch.envelopes.map(\.revision).max() ?? 1,
            exportedAt: batch.exportedAt,
            cursor: cursor,
            projects: projects,
            timeEntries: entries,
            thoughts: thoughts
        )
    }
}
