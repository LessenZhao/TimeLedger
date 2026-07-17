import Foundation

public enum EvolutionQuery: Sendable, Hashable {
    case all
    case day(String)
    case project(String)
}

public struct EvolutionSnapshot: Sendable, Hashable {
    public var projects: [EvolutionProject]
    public var days: [WorkEvolutionDayRecord]
    public var nodes: [EvolutionNode]
    public var annotations: [UserAnnotation]
    public var sourceSessions: [SourceSessionRecord]
    public var worktreeEvidence: [WorktreeEvidenceSnapshot]

    public init(
        projects: [EvolutionProject],
        days: [WorkEvolutionDayRecord],
        nodes: [EvolutionNode],
        annotations: [UserAnnotation],
        sourceSessions: [SourceSessionRecord],
        worktreeEvidence: [WorktreeEvidenceSnapshot]
    ) {
        self.projects = projects
        self.days = days
        self.nodes = nodes
        self.annotations = annotations
        self.sourceSessions = sourceSessions
        self.worktreeEvidence = worktreeEvidence
    }
}

public enum EvolutionUserCommand: Sendable, Hashable {
    case addAnnotation(UserAnnotation)
    case confirmDay(String)
    case confirmProject(String)
    case confirmNode(String)
}

public enum EvolutionLedgerError: Error, Sendable, Hashable {
    case emptyAnnotationBody
    case reflectionRequiresHappenedAt
    case targetNotFound(AnnotationTarget)
}

public enum EvolutionPrepareError: Error, Sendable, Hashable {
    case emptyJobId
    case invalidTimeZone(String)
    case invalidDate(String)
    case cutoffBeforeRequestedDay
}

extension EvolutionPrepareError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyJobId: return "jobId 不能为空。"
        case .invalidTimeZone(let identifier): return "无效时区：\(identifier)。"
        case .invalidDate(let value): return "无效日期：\(value)，必须使用 YYYY-MM-DD。"
        case .cutoffBeforeRequestedDay: return "cutoffAt 不能早于请求日期的自然日起点。"
        }
    }
}

extension EvolutionLedgerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyAnnotationBody:
            return "用户补充内容不能为空。"
        case .reflectionRequiresHappenedAt:
            return "后来认识必须填写事情实际发生的时间。"
        case .targetNotFound(let target):
            return "找不到用户补充目标：\(target.kind.rawValue)/\(target.targetId)。"
        }
    }
}

public final class EvolutionLedger: @unchecked Sendable {
    private let store: any EvolutionDocumentStore
    private let archiveReader: ArchiveEvidenceReader
    private let worktreeAdapter: WorktreeEvidenceAdapter
    private let now: @Sendable () -> Date
    private let proposalValidator: EvolutionProposalValidator
    private let lock = NSLock()

    public init(
        store: any EvolutionDocumentStore,
        archiveReader: ArchiveEvidenceReader = ArchiveEvidenceReader(),
        worktreeAdapter: WorktreeEvidenceAdapter = WorktreeEvidenceAdapter(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.archiveReader = archiveReader
        self.worktreeAdapter = worktreeAdapter
        self.now = now
        self.proposalValidator = EvolutionProposalValidator(archiveReader: archiveReader)
    }

    public func prepare(jobId: String, request: EvolutionPrepareRequest) throws -> EvidenceBundle {
        let trimmedJobID = jobId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedJobID.isEmpty else { throw EvolutionPrepareError.emptyJobId }
        guard let timeZone = TimeZone(identifier: request.timeZoneIdentifier) else {
            throw EvolutionPrepareError.invalidTimeZone(request.timeZoneIdentifier)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        guard let requestedDate = Self.parseDay(request.date, calendar: calendar) else {
            throw EvolutionPrepareError.invalidDate(request.date)
        }
        let window = NaturalDayWindow.forDate(requestedDate, calendar: calendar)
        guard request.cutoffAt >= window.start else {
            throw EvolutionPrepareError.cutoffBeforeRequestedDay
        }

        let processorIDs = Set(request.explicitProcessorThreadIds)
        var archiveDays: [PreparedArchiveDay] = []
        var diagnostics: [ProposalDiagnostic] = []
        for location in request.archives {
            let day = try archiveReader.prepareDay(
                location: location,
                date: requestedDate,
                cutoffAt: request.cutoffAt,
                calendar: calendar,
                processorThreadIds: processorIDs
            )
            archiveDays.append(day)
            diagnostics.append(contentsOf: day.diagnostics)
        }
        archiveDays.sort {
            let left = ($0.sessions.first?.source.rawValue ?? "", $0.sessions.first?.canonicalEventsPath ?? "")
            let right = ($1.sessions.first?.source.rawValue ?? "", $1.sessions.first?.canonicalEventsPath ?? "")
            return left < right
        }

        let sourceDigest = EvolutionSourceDigest.make(
            sourceCutoffAt: request.cutoffAt,
            dateIDs: archiveDays.map(\.date),
            sourceSliceIDs: archiveDays.flatMap(\.slices).map(\.id),
            messageIDs: archiveDays.flatMap(\.messages).map(\.id)
        )
        let capturedAt = now()
        let isHistorical = window.start < calendar.startOfDay(for: capturedAt)
        var roots: Set<String> = []
        for session in archiveDays.flatMap(\.sessions).sorted(by: { $0.id < $1.id }) {
            guard let cwd = session.cwd?.trimmingCharacters(in: .whitespacesAndNewlines), !cwd.isEmpty else {
                diagnostics.append(Self.diagnostic(
                    code: "prepare_missing_cwd",
                    message: "来源会话没有 cwd，无法核实工作树。",
                    relatedIds: [session.id]
                ))
                continue
            }
            do {
                roots.insert(try worktreeAdapter.repositoryRoot(for: cwd))
            } catch {
                diagnostics.append(Self.diagnostic(
                    code: "prepare_not_git_repository",
                    message: "来源会话 cwd 不是可核实的 Git 仓库：\(cwd)。",
                    relatedIds: [session.id]
                ))
            }
        }

        var worktrees: [WorktreeEvidenceSnapshot] = []
        for root in roots.sorted() {
            do {
                let snapshot = try worktreeAdapter.snapshot(
                    repoPath: root,
                    since: window.start,
                    capturedAt: capturedAt,
                    historicalDate: isHistorical ? requestedDate : nil
                )
                worktrees.append(snapshot)
                if isHistorical {
                    diagnostics.append(Self.diagnostic(
                        code: "prepare_historical_worktree_limit",
                        message: snapshot.limitation ?? "历史日期只能核实提交，无法还原当时未提交工作树。",
                        relatedIds: [snapshot.id]
                    ))
                }
            } catch {
                diagnostics.append(Self.diagnostic(
                    code: "prepare_worktree_snapshot_failed",
                    message: "Git 工作树核实失败：\(root)。",
                    relatedIds: []
                ))
            }
        }
        worktrees.sort { $0.id < $1.id }
        diagnostics.sort { ($0.code, $0.id) < ($1.code, $1.id) }
        var bundle = EvidenceBundle(
            jobId: trimmedJobID,
            request: request,
            archiveDays: archiveDays,
            worktrees: worktrees,
            diagnostics: diagnostics,
            sourceDigest: sourceDigest,
            contentHash: ""
        )
        bundle.contentHash = bundle.recomputedContentHash()
        return bundle
    }

    private static func parseDay(_ value: String, calendar: Calendar) -> Date? {
        guard value.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let result = formatter.date(from: value), formatter.string(from: result) == value else { return nil }
        return result
    }

    private static func diagnostic(code: String, message: String, relatedIds: [String]) -> ProposalDiagnostic {
        ProposalDiagnostic(
            id: EvolutionStableID.proposalDiagnostic(code: code, message: message, relatedIds: relatedIds),
            severity: .warning,
            code: code,
            message: message,
            relatedIds: relatedIds.sorted()
        )
    }

    public func read(_ query: EvolutionQuery) throws -> EvolutionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return project(try store.load(), for: query)
    }

    public func apply(_ command: EvolutionUserCommand) throws -> EvolutionSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var document = try store.load()
        switch command {
        case .addAnnotation(let annotation):
            try add(annotation, to: &document)
        case .confirmDay(let date):
            guard let index = document.days.firstIndex(where: { $0.date == date }) else {
                throw EvolutionLedgerError.targetNotFound(
                    AnnotationTarget(kind: .day, targetId: date)
                )
            }
            document.days[index].reviewState = .confirmed
            document.days[index].updatedAt = Date()
        case .confirmProject(let id):
            guard let index = document.projects.firstIndex(where: { $0.id == id }) else {
                throw EvolutionLedgerError.targetNotFound(
                    AnnotationTarget(kind: .project, targetId: id)
                )
            }
            document.projects[index].reviewState = .confirmed
            document.projects[index].updatedAt = Date()
        case .confirmNode(let id):
            guard let index = document.nodes.firstIndex(where: { $0.id == id }) else {
                throw EvolutionLedgerError.targetNotFound(
                    AnnotationTarget(kind: .evolutionNode, targetId: id)
                )
            }
            document.nodes[index].reviewState = .confirmed
            let projectId = document.nodes[index].projectId
            if let projectIndex = document.projects.firstIndex(where: { $0.id == projectId }) {
                document.projects[projectIndex].updatedAt = Date()
            }
        }
        document.updatedAt = Date()
        try store.save(document)
        return project(document, for: .all)
    }

    public func apply(
        _ proposal: EvolutionProposalEnvelope,
        proposalDigest: String
    ) throws -> ImportReceipt {
        // Validation deliberately happens before the store is even loaded. An invalid
        // package must not observe or partially mutate authoritative user data.
        try proposalValidator.validate(proposal)
        guard !proposalDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EvolutionProposalValidationError.emptyRequiredField("proposalDigest")
        }

        lock.lock()
        defer { lock.unlock() }

        var document = try store.load()
        let now = Date()
        if let previous = document.imports.first(where: { $0.jobId == proposal.jobId }) {
            if previous.proposalDigest == proposalDigest {
                return ImportReceipt(
                    jobId: proposal.jobId,
                    proposalDigest: proposalDigest,
                    status: .noOp,
                    acceptedDayIds: [],
                    skippedLockedIds: [],
                    warnings: previous.warnings,
                    errors: [],
                    importedAt: now
                )
            }
            // A conflict is returned to the caller but intentionally not persisted:
            // persisting it would change the authoritative bytes for a rejected job.
            return conflictReceipt(
                proposal: proposal,
                proposalDigest: proposalDigest,
                reason: "jobId \(proposal.jobId) already exists with another digest",
                importedAt: now
            )
        }
        if let conflict = preflightConflict(proposal, document: document) {
            return conflictReceipt(
                proposal: proposal,
                proposalDigest: proposalDigest,
                reason: conflict,
                importedAt: now
            )
        }

        var acceptedDayIDs: [String] = []
        var skippedLockedIDs: [String] = []

        mergeSessions(proposal.sessions, into: &document.sourceSessions)
        mergeWorktreeEvidence(proposal.worktreeEvidence, into: &document.worktreeEvidence)
        mergeProjects(proposal.projects, into: &document.projects, skippedLockedIDs: &skippedLockedIDs)
        mergeDays(
            proposal.days,
            into: &document.days,
            acceptedDayIDs: &acceptedDayIDs,
            skippedLockedIDs: &skippedLockedIDs
        )
        mergeNodes(proposal.nodes, into: &document.nodes, skippedLockedIDs: &skippedLockedIDs)

        let warnings = proposal.diagnostics
            .filter { $0.severity != .error }
            .map(\.message)
        let receipt = ImportReceipt(
            jobId: proposal.jobId,
            proposalDigest: proposalDigest,
            status: .imported,
            acceptedDayIds: Array(Set(acceptedDayIDs)).sorted(),
            skippedLockedIds: Array(Set(skippedLockedIDs)).sorted(),
            warnings: warnings,
            errors: [],
            importedAt: now
        )
        document.imports.append(receipt)
        document.schemaVersion = EvolutionSchema.current
        document.updatedAt = now
        try store.save(document)
        return receipt
    }

    private func mergeSessions(
        _ incoming: [SourceSessionRecord],
        into existing: inout [SourceSessionRecord]
    ) {
        for session in incoming {
            if let index = existing.firstIndex(where: { $0.id == session.id }) {
                existing[index] = session
            } else {
                existing.append(session)
            }
        }
    }

    private func mergeWorktreeEvidence(
        _ incoming: [WorktreeEvidenceSnapshot],
        into existing: inout [WorktreeEvidenceSnapshot]
    ) {
        for snapshot in incoming {
            if existing.contains(where: { $0.id == snapshot.id }) {
                // Evidence identity is immutable. Preflight already proved that the
                // hashes are identical, so keep the exact previously accepted bytes.
                continue
            } else {
                existing.append(snapshot)
            }
        }
    }

    private func preflightConflict(
        _ proposal: EvolutionProposalEnvelope,
        document: EvolutionLedgerDocument
    ) -> String? {
        for incoming in proposal.worktreeEvidence {
            if let existing = document.worktreeEvidence.first(where: { $0.id == incoming.id }),
               existing.contentHash != incoming.contentHash {
                return "worktree evidence \(incoming.id) already exists with another content hash"
            }
        }

        for incoming in proposal.sessions {
            if let existing = document.sourceSessions.first(where: { $0.id == incoming.id }) {
                if existing.source != incoming.source
                    || existing.externalThreadId != incoming.externalThreadId
                    || existing.canonicalEventsPath != incoming.canonicalEventsPath
                    || existing.canonicalThreadsPath != incoming.canonicalThreadsPath {
                    return "source session \(incoming.id) changed immutable archive identity"
                }
            }
        }

        for incoming in proposal.projects {
            let normalizedGoal = EvolutionStableID.normalizeProjectGoal(incoming.goal)
            let existingByID = document.projects.first { $0.id == incoming.id }
            if existingByID == nil,
               incoming.id != EvolutionStableID.newProject(normalizedGoal: incoming.goal) {
                return "new project \(incoming.id) does not match its normalized goal identity"
            }
            if let split = document.projects.first(where: {
                $0.id != incoming.id
                    && EvolutionStableID.normalizeProjectGoal($0.goal) == normalizedGoal
            }) {
                return "project goal would split identity between \(split.id) and \(incoming.id)"
            }
        }
        return nil
    }

    private func conflictReceipt(
        proposal: EvolutionProposalEnvelope,
        proposalDigest: String,
        reason: String,
        importedAt: Date
    ) -> ImportReceipt {
        ImportReceipt(
            jobId: proposal.jobId,
            proposalDigest: proposalDigest,
            status: .conflict,
            acceptedDayIds: [],
            skippedLockedIds: [],
            warnings: [],
            errors: [reason],
            importedAt: importedAt
        )
    }

    private func mergeProjects(
        _ incoming: [EvolutionProject],
        into existing: inout [EvolutionProject],
        skippedLockedIDs: inout [String]
    ) {
        for proposedProject in incoming {
            guard let index = existing.firstIndex(where: { $0.id == proposedProject.id }) else {
                existing.append(proposedProject)
                continue
            }

            let current = existing[index]
            var mergedRoutes = current.routes
            mergeRoutes(
                proposedProject.routes,
                into: &mergedRoutes,
                skippedLockedIDs: &skippedLockedIDs
            )
            if current.reviewState == .confirmed {
                skippedLockedIDs.append(current.id)
                existing[index].routes = mergedRoutes
            } else {
                var replacement = proposedProject
                replacement.routes = mergedRoutes
                existing[index] = replacement
            }
        }
    }

    private func mergeRoutes(
        _ incoming: [ProjectRoute],
        into existing: inout [ProjectRoute],
        skippedLockedIDs: inout [String]
    ) {
        for route in incoming {
            guard let index = existing.firstIndex(where: { $0.id == route.id }) else {
                existing.append(route)
                continue
            }
            if existing[index].reviewState == .confirmed {
                skippedLockedIDs.append(route.id)
            } else {
                existing[index] = route
            }
        }
    }

    private func mergeDays(
        _ incoming: [WorkEvolutionDayRecord],
        into existing: inout [WorkEvolutionDayRecord],
        acceptedDayIDs: inout [String],
        skippedLockedIDs: inout [String]
    ) {
        for day in incoming {
            guard let index = existing.firstIndex(where: { $0.id == day.id }) else {
                existing.append(day)
                acceptedDayIDs.append(day.id)
                continue
            }
            if existing[index].reviewState == .confirmed {
                skippedLockedIDs.append(day.id)
            } else {
                existing[index] = day
                acceptedDayIDs.append(day.id)
            }
        }
    }

    private func mergeNodes(
        _ incoming: [EvolutionNode],
        into existing: inout [EvolutionNode],
        skippedLockedIDs: inout [String]
    ) {
        for node in incoming {
            guard let index = existing.firstIndex(where: { $0.id == node.id }) else {
                existing.append(node)
                continue
            }
            if existing[index].reviewState == .confirmed {
                skippedLockedIDs.append(node.id)
            } else {
                existing[index] = node
            }
        }
    }

    private func add(_ annotation: UserAnnotation, to document: inout EvolutionLedgerDocument) throws {
        let trimmedBody = annotation.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            throw EvolutionLedgerError.emptyAnnotationBody
        }
        if annotation.kind == .reflection, annotation.happenedAt == nil {
            throw EvolutionLedgerError.reflectionRequiresHappenedAt
        }
        guard targetExists(annotation.target, in: document) else {
            throw EvolutionLedgerError.targetNotFound(annotation.target)
        }

        var stored = annotation
        stored.body = trimmedBody
        if let index = document.annotations.firstIndex(where: { $0.id == stored.id }) {
            stored.createdAt = document.annotations[index].createdAt
            document.annotations[index] = stored
        } else {
            document.annotations.append(stored)
        }
    }

    private func targetExists(_ target: AnnotationTarget, in document: EvolutionLedgerDocument) -> Bool {
        switch target.kind {
        case .day:
            return document.days.contains { $0.date == target.targetId }
        case .project:
            return document.projects.contains { $0.id == target.targetId }
        case .projectDaySlice:
            return document.days.contains { day in
                day.projectSlices.contains { $0.id == target.targetId }
            }
        case .evolutionNode:
            return document.nodes.contains { $0.id == target.targetId }
        case .sourceSession:
            return document.sourceSessions.contains { $0.id == target.targetId }
        }
    }

    private func project(_ document: EvolutionLedgerDocument, for query: EvolutionQuery) -> EvolutionSnapshot {
        switch query {
        case .all:
            return EvolutionSnapshot(
                projects: document.projects.sorted(by: projectOrdering),
                days: document.days.sorted(by: dayOrdering),
                nodes: document.nodes.sorted(by: EvolutionOrdering.nodes),
                annotations: document.annotations.sorted(by: EvolutionOrdering.annotations),
                sourceSessions: document.sourceSessions.sorted { $0.id < $1.id },
                worktreeEvidence: document.worktreeEvidence.sorted { $0.id < $1.id }
            )

        case .day(let key):
            let days = document.days.filter { $0.date == key }.sorted(by: dayOrdering)
            let nodes = document.nodes
                .filter { EvolutionDayKey.make($0.recognizedAt) == key }
                .sorted(by: EvolutionOrdering.nodes)
            let annotations = document.annotations
                .filter { EvolutionDayKey.make($0.recognizedAt) == key }
                .sorted(by: EvolutionOrdering.annotations)
            let projectIds = Set(days.flatMap(\.projectSlices).map(\.projectId))
                .union(nodes.map(\.projectId))
                .union(annotations.flatMap { resolvedProjectIds(for: $0, document: document) })
            let annotationSessionIds = annotations.compactMap { annotation -> String? in
                annotation.target.kind == .sourceSession ? annotation.target.targetId : nil
            }
            let sourceSessionIds = Set(days.flatMap(\.sourceSlices).map(\.sessionId))
                .union(annotationSessionIds)
                .union(sessionIds(forSourceSliceIds: nodes.flatMap(\.sourceSliceIds), document: document))
            let evidenceIds = referencedEvidenceIds(in: days)
                .union(nodes.flatMap(\.evidenceIds))
            return EvolutionSnapshot(
                projects: document.projects.filter { projectIds.contains($0.id) }.sorted(by: projectOrdering),
                days: days,
                nodes: nodes,
                annotations: annotations,
                sourceSessions: document.sourceSessions.filter { sourceSessionIds.contains($0.id) }.sorted { $0.id < $1.id },
                worktreeEvidence: document.worktreeEvidence.filter { evidenceIds.contains($0.id) }.sorted { $0.id < $1.id }
            )

        case .project(let id):
            let days = document.days.compactMap { day -> WorkEvolutionDayRecord? in
                var projected = day
                projected.projectSlices = day.projectSlices.filter { $0.projectId == id }
                let relevantSourceSliceIds = Set(projected.projectSlices.flatMap(\.sourceSliceIds))
                projected.sourceSlices = day.sourceSlices.filter {
                    $0.projectIds.contains(id) || relevantSourceSliceIds.contains($0.id)
                }
                projected.independentThoughts = []
                let relevantSessionIds = Set(projected.sourceSlices.map(\.sessionId))
                projected.coverage = SourceCoverage(
                    expectedSessionCount: relevantSessionIds.count,
                    includedSessionIds: day.coverage.includedSessionIds.filter(relevantSessionIds.contains),
                    pendingSessionIds: day.coverage.pendingSessionIds.filter(relevantSessionIds.contains),
                    excludedSessionIds: day.coverage.excludedSessionIds.filter(relevantSessionIds.contains),
                    processorSessionIds: day.coverage.processorSessionIds.filter(relevantSessionIds.contains)
                )
                guard !projected.projectSlices.isEmpty else { return nil }
                return projected
            }.sorted(by: dayOrdering)
            let nodes = document.nodes.filter { $0.projectId == id }.sorted(by: EvolutionOrdering.nodes)
            let annotations = document.annotations.filter {
                annotationBelongsToProject($0, projectId: id, document: document)
            }.sorted(by: EvolutionOrdering.annotations)
            let sourceSessionIds = Set(days.flatMap(\.sourceSlices).map(\.sessionId))
                .union(sessionIds(forSourceSliceIds: nodes.flatMap(\.sourceSliceIds), document: document))
            let evidenceIds = referencedEvidenceIds(in: days)
                .union(nodes.flatMap(\.evidenceIds))
            return EvolutionSnapshot(
                projects: document.projects.filter { $0.id == id },
                days: days,
                nodes: nodes,
                annotations: annotations,
                sourceSessions: document.sourceSessions.filter { sourceSessionIds.contains($0.id) }.sorted { $0.id < $1.id },
                worktreeEvidence: document.worktreeEvidence.filter { evidenceIds.contains($0.id) }.sorted { $0.id < $1.id }
            )
        }
    }

    private func annotationBelongsToProject(
        _ annotation: UserAnnotation,
        projectId: String,
        document: EvolutionLedgerDocument
    ) -> Bool {
        switch annotation.target.kind {
        case .project:
            return annotation.target.targetId == projectId
        case .projectDaySlice:
            return document.days.lazy.flatMap(\.projectSlices).contains {
                $0.id == annotation.target.targetId && $0.projectId == projectId
            }
        case .evolutionNode:
            return document.nodes.contains {
                $0.id == annotation.target.targetId && $0.projectId == projectId
            }
        case .sourceSession:
            return document.days.lazy.flatMap(\.sourceSlices).contains { slice in
                slice.sessionId == annotation.target.targetId && slice.projectIds.contains(projectId)
            }
        case .day:
            return false
        }
    }

    private func resolvedProjectIds(
        for annotation: UserAnnotation,
        document: EvolutionLedgerDocument
    ) -> Set<String> {
        switch annotation.target.kind {
        case .project:
            return [annotation.target.targetId]
        case .projectDaySlice:
            return Set(document.days.lazy.flatMap(\.projectSlices).compactMap { slice in
                slice.id == annotation.target.targetId ? slice.projectId : nil
            })
        case .evolutionNode:
            return Set(document.nodes.compactMap { node in
                node.id == annotation.target.targetId ? node.projectId : nil
            })
        case .sourceSession:
            return Set(document.days.lazy.flatMap(\.sourceSlices).flatMap { slice in
                slice.sessionId == annotation.target.targetId ? slice.projectIds : []
            })
        case .day:
            return []
        }
    }

    private func sessionIds(
        forSourceSliceIds sourceSliceIds: [String],
        document: EvolutionLedgerDocument
    ) -> Set<String> {
        let wanted = Set(sourceSliceIds)
        return Set(document.days.lazy.flatMap(\.sourceSlices).compactMap { slice in
            wanted.contains(slice.id) ? slice.sessionId : nil
        })
    }

    private func referencedEvidenceIds(in days: [WorkEvolutionDayRecord]) -> Set<String> {
        let sliceIDs = days.flatMap(\.projectSlices).flatMap { slice -> [String] in
            let decisionIDs = slice.decisions.flatMap(\.evidenceIds)
            let learningIDs = slice.learnings.flatMap(\.evidenceIds)
            let valueIDs = slice.values.flatMap(\.evidenceIds)
            return slice.evidenceIds + decisionIDs + learningIDs + valueIDs
        }
        let thoughtIDs = days.flatMap(\.independentThoughts).flatMap { thought -> [String] in
            let decisionIDs = thought.decisions.flatMap(\.evidenceIds)
            let learningIDs = thought.learnings.flatMap(\.evidenceIds)
            let valueIDs = thought.values.flatMap(\.evidenceIds)
            return thought.evidenceIds + decisionIDs + learningIDs + valueIDs
        }
        return Set(sliceIDs + thoughtIDs)
    }
}

private func projectOrdering(_ lhs: EvolutionProject, _ rhs: EvolutionProject) -> Bool {
    if lhs.name != rhs.name { return lhs.name < rhs.name }
    return lhs.id < rhs.id
}

private func dayOrdering(_ lhs: WorkEvolutionDayRecord, _ rhs: WorkEvolutionDayRecord) -> Bool {
    if lhs.date != rhs.date { return lhs.date < rhs.date }
    return lhs.id < rhs.id
}

private enum EvolutionDayKey {
    static func make(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
