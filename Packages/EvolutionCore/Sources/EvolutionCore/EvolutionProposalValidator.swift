import Foundation

public enum EvolutionProposalValidationError: Error, Sendable, Equatable {
    case unsupportedSchema(Int)
    case emptyRequiredField(String)
    case proposalContainsUserAnnotations
    case proposalContainsErrorDiagnostic(String)
    case proposalContainsConfirmed(String, String)
    case invalidScopeDates
    case invalidDate(String, String)
    case cutoffViolation(String)
    case sourceDigestMismatch
    case duplicateIdentifier(String, String)
    case duplicateCoverageMembership(String)
    case coverageCountMismatch(String)
    case coverageIdentityMismatch(String)
    case classificationCoverageMismatch(String, String)
    case missingReference(String, String)
    case stableIDMismatch(String, String)
    case canonicalMessageMismatch(String)
    case ineligibleSourceContribution(String)
    case ownerEvidenceMismatch(String, String)
    case sourceProjectMismatch(String, String)
    case historicalWorktreeOverclaim(String)
    case invalidWorktreeEvidence(String)
}

extension EvolutionProposalValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): return "Unsupported proposal schema: \(version)."
        case .emptyRequiredField(let field): return "Proposal field is empty: \(field)."
        case .proposalContainsUserAnnotations: return "A generated proposal cannot contain user annotations."
        case .proposalContainsErrorDiagnostic(let id): return "Proposal contains an unresolved error diagnostic: \(id)."
        case let .proposalContainsConfirmed(kind, id): return "Generated \(kind) must be candidate: \(id)."
        case .invalidScopeDates: return "Proposal scope dates do not exactly match its day records."
        case let .invalidDate(kind, id): return "Invalid or inconsistent \(kind) date: \(id)."
        case .cutoffViolation(let id): return "Source message is outside its natural day or after cutoff: \(id)."
        case .sourceDigestMismatch: return "Proposal source digest does not match its selected source facts."
        case let .duplicateIdentifier(kind, id): return "Duplicate \(kind) identifier: \(id)."
        case .duplicateCoverageMembership(let date): return "A source belongs to multiple coverage buckets on \(date)."
        case .coverageCountMismatch(let date): return "Coverage count does not match expected count on \(date)."
        case .coverageIdentityMismatch(let date): return "Coverage identities do not match visible sources on \(date)."
        case let .classificationCoverageMismatch(date, id): return "Source classification and coverage bucket disagree on \(date): \(id)."
        case let .missingReference(kind, id): return "Missing \(kind) reference: \(id)."
        case let .stableIDMismatch(kind, id): return "Invalid stable \(kind) identifier: \(id)."
        case .canonicalMessageMismatch(let id): return "Message is not an exact canonical archive fact: \(id)."
        case .ineligibleSourceContribution(let id): return "Pending, excluded, or processor source contributed generated value: \(id)."
        case let .ownerEvidenceMismatch(owner, evidence): return "Evidence \(evidence) is not declared by owner \(owner)."
        case let .sourceProjectMismatch(owner, source): return "Source \(source) does not belong to the project of owner \(owner)."
        case .historicalWorktreeOverclaim(let id): return "Historical worktree evidence overclaims current state as verified: \(id)."
        case .invalidWorktreeEvidence(let id): return "Invalid worktree evidence: \(id)."
        }
    }
}

public struct EvolutionProposalValidator: Sendable {
    private let archiveReader: ArchiveEvidenceReader

    public init(archiveReader: ArchiveEvidenceReader = ArchiveEvidenceReader()) {
        self.archiveReader = archiveReader
    }

    public func validate(_ proposal: EvolutionProposalEnvelope) throws {
        guard proposal.schemaVersion == EvolutionSchema.current else {
            throw EvolutionProposalValidationError.unsupportedSchema(proposal.schemaVersion)
        }
        guard !proposal.jobId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EvolutionProposalValidationError.emptyRequiredField("jobId")
        }
        guard !proposal.sourceDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EvolutionProposalValidationError.emptyRequiredField("sourceDigest")
        }
        guard proposal.userAnnotations.isEmpty else {
            throw EvolutionProposalValidationError.proposalContainsUserAnnotations
        }

        let scopeDates = proposal.scope.dates
        let dayDates = proposal.days.map(\.date)
        guard !scopeDates.isEmpty,
              Set(scopeDates).count == scopeDates.count,
              Set(dayDates).count == dayDates.count,
              Set(scopeDates) == Set(dayDates),
              proposal.scope.kind != .day || scopeDates.count == 1 else {
            throw EvolutionProposalValidationError.invalidScopeDates
        }
        guard proposal.sourceDigest == EvolutionSourceDigest.make(
            sourceCutoffAt: proposal.sourceCutoffAt,
            days: proposal.days
        ) else {
            throw EvolutionProposalValidationError.sourceDigestMismatch
        }

        try requireUnique(proposal.sessions.map(\.id), kind: "session")
        try requireUnique(proposal.projects.map(\.id), kind: "project")
        try requireUnique(proposal.nodes.map(\.id), kind: "node")
        try requireUnique(proposal.worktreeEvidence.map(\.id), kind: "worktree evidence")
        try requireUnique(proposal.diagnostics.map(\.id), kind: "diagnostic")

        let sessionByID = Dictionary(uniqueKeysWithValues: proposal.sessions.map { ($0.id, $0) })
        let projectByID = Dictionary(uniqueKeysWithValues: proposal.projects.map { ($0.id, $0) })
        let worktreeByID = Dictionary(uniqueKeysWithValues: proposal.worktreeEvidence.map { ($0.id, $0) })

        var canonicalMessagesBySession: [String: [String: MessageReference]] = [:]
        for session in proposal.sessions {
            let expected = EvolutionStableID.sourceSession(source: session.source, externalThreadId: session.externalThreadId)
            guard session.id == expected else {
                throw EvolutionProposalValidationError.stableIDMismatch("session", session.id)
            }
            guard !session.canonicalEventsPath.isEmpty, !session.canonicalThreadsPath.isEmpty else {
                throw EvolutionProposalValidationError.emptyRequiredField("canonical archive path for \(session.id)")
            }
            let canonicalConversation = try archiveReader.conversation(session: session)
            guard session.contentHash == ContentHasher.hashParts(canonicalConversation.map(\.reference.id).sorted()) else {
                throw EvolutionProposalValidationError.canonicalMessageMismatch(session.id)
            }
            canonicalMessagesBySession[session.id] = Dictionary(
                uniqueKeysWithValues: canonicalConversation.map { ($0.reference.id, $0.reference) }
            )
        }

        var routesByID: [String: (projectId: String, route: ProjectRoute)] = [:]
        for project in proposal.projects {
            try requireCandidate(project.reviewState, kind: "project", id: project.id)
            try requireUnique(project.routes.map(\.id), kind: "route")
            for route in project.routes {
                try requireCandidate(route.reviewState, kind: "route", id: route.id)
                guard routesByID[route.id] == nil else {
                    throw EvolutionProposalValidationError.duplicateIdentifier("route", route.id)
                }
                let expected = EvolutionStableID.route(projectId: project.id, name: route.name, repoPaths: route.repoPaths)
                guard route.id == expected else {
                    throw EvolutionProposalValidationError.stableIDMismatch("route", route.id)
                }
                routesByID[route.id] = (project.id, route)
            }
        }

        for snapshot in proposal.worktreeEvidence {
            try validate(snapshot, proposalCreatedAt: proposal.createdAt)
        }
        for diagnostic in proposal.diagnostics {
            let expected = EvolutionStableID.proposalDiagnostic(code: diagnostic.code, message: diagnostic.message, relatedIds: diagnostic.relatedIds)
            guard diagnostic.id == expected else {
                throw EvolutionProposalValidationError.stableIDMismatch("diagnostic", diagnostic.id)
            }
            guard diagnostic.severity != .error else {
                throw EvolutionProposalValidationError.proposalContainsErrorDiagnostic(diagnostic.id)
            }
        }

        var allSourceSlices: [String: DailySessionSlice] = [:]
        var messageClassification: [String: DailySourceClassification] = [:]
        var messageIDs = Set<String>()
        for day in proposal.days {
            try requireCandidate(day.reviewState, kind: "day", id: day.date)
            let interval = try naturalDayInterval(day.date)
            guard day.sourceCutoffAt <= proposal.sourceCutoffAt else {
                throw EvolutionProposalValidationError.cutoffViolation(day.date)
            }
            try validateCoverage(day)
            try requireUnique(day.sourceSlices.map(\.id), kind: "daily source")
            try requireUnique(day.sourceSlices.map(\.sessionId), kind: "daily session")
            try requireUnique(day.projectSlices.map(\.id), kind: "project-day slice")
            try requireUnique(day.independentThoughts.map(\.id), kind: "independent thought")

            for slice in day.sourceSlices {
                guard slice.date == day.date else {
                    throw EvolutionProposalValidationError.invalidDate("source slice", slice.id)
                }
                guard let session = sessionByID[slice.sessionId] else {
                    throw EvolutionProposalValidationError.missingReference("session", slice.sessionId)
                }
                let expected = EvolutionStableID.dailySession(date: day.date, sessionId: slice.sessionId)
                guard slice.id == expected else {
                    throw EvolutionProposalValidationError.stableIDMismatch("daily source", slice.id)
                }
                guard allSourceSlices.updateValue(slice, forKey: slice.id) == nil else {
                    throw EvolutionProposalValidationError.duplicateIdentifier("daily source", slice.id)
                }
                guard !slice.messageReferences.isEmpty else {
                    throw EvolutionProposalValidationError.emptyRequiredField("messageReferences for \(slice.id)")
                }
                for projectID in slice.projectIds where projectByID[projectID] == nil {
                    throw EvolutionProposalValidationError.missingReference("project", projectID)
                }
                try requireUnique(slice.projectIds, kind: "source project reference")
                try requireUnique(slice.messageReferences.map(\.id), kind: "message")
                for message in slice.messageReferences {
                    guard message.source == session.source,
                          message.threadId == session.externalThreadId,
                          message.createdAt >= interval.start,
                          message.createdAt < interval.end,
                          message.createdAt <= day.sourceCutoffAt,
                          message.createdAt <= proposal.sourceCutoffAt else {
                        throw EvolutionProposalValidationError.cutoffViolation(message.id)
                    }
                    guard let canonical = canonicalMessagesBySession[session.id]?[message.id],
                          message.matchesCanonical(canonical) else {
                        throw EvolutionProposalValidationError.canonicalMessageMismatch(message.id)
                    }
                    let expectedMessageID = EvolutionStableID.message(
                        source: message.source,
                        threadId: message.threadId,
                        eventId: message.eventId,
                        sourceFile: message.sourceFile,
                        sourceLine: message.sourceLine,
                        contentHash: message.contentHash
                    )
                    guard message.id == expectedMessageID else {
                        throw EvolutionProposalValidationError.stableIDMismatch("message", message.id)
                    }
                    guard messageIDs.insert(message.id).inserted else {
                        throw EvolutionProposalValidationError.duplicateIdentifier("message", message.id)
                    }
                    messageClassification[message.id] = slice.classification
                }
            }

            for projectSlice in day.projectSlices {
                try requireCandidate(projectSlice.reviewState, kind: "project-day slice", id: projectSlice.id)
                guard projectSlice.date == day.date else {
                    throw EvolutionProposalValidationError.invalidDate("project-day slice", projectSlice.id)
                }
                guard projectByID[projectSlice.projectId] != nil else {
                    throw EvolutionProposalValidationError.missingReference("project", projectSlice.projectId)
                }
                let expected = EvolutionStableID.projectDaySlice(date: day.date, projectId: projectSlice.projectId)
                guard projectSlice.id == expected else {
                    throw EvolutionProposalValidationError.stableIDMismatch("project-day slice", projectSlice.id)
                }
                try requireUnique(projectSlice.routeIds, kind: "project-day route reference")
                try requireUnique(projectSlice.sourceSliceIds, kind: "project-day source reference")
                try requireUnique(projectSlice.evidenceIds, kind: "project-day evidence reference")
                try validateRoutes(projectSlice.routeIds, projectId: projectSlice.projectId, routesByID: routesByID)
            }
            for thought in day.independentThoughts {
                try requireCandidate(thought.reviewState, kind: "independent thought", id: thought.id)
                guard thought.date == day.date else {
                    throw EvolutionProposalValidationError.invalidDate("independent thought", thought.id)
                }
                let expected = EvolutionStableID.independentThought(date: thought.date, title: thought.title, body: thought.body)
                guard thought.id == expected else {
                    throw EvolutionProposalValidationError.stableIDMismatch("independent thought", thought.id)
                }
                try requireUnique(thought.sourceSliceIds, kind: "thought source reference")
                try requireUnique(thought.evidenceIds, kind: "thought evidence reference")
            }
        }

        guard Set(proposal.sessions.map(\.id)) == Set(allSourceSlices.values.map(\.sessionId)) else {
            throw EvolutionProposalValidationError.coverageIdentityMismatch("proposal")
        }

        let validEvidenceIDs = messageIDs.union(worktreeByID.keys)
        for day in proposal.days {
            let localSourceIDs = Set(day.sourceSlices.map(\.id))
            for slice in day.projectSlices {
                try validateSourceContributions(
                    slice.sourceSliceIds,
                    allowed: [.project, .crossProject],
                    known: allSourceSlices,
                    owner: slice.id,
                    localSourceIDs: localSourceIDs
                )
                try validateGeneratedRecords(
                    parentID: slice.id,
                    decisions: slice.decisions,
                    learnings: slice.learnings,
                    values: slice.values,
                    directEvidenceIDs: slice.evidenceIds,
                    validEvidenceIDs: validEvidenceIDs,
                    messageClassification: messageClassification,
                    ownerMessageEvidenceIDs: messageEvidenceIDs(
                        sourceSliceIDs: slice.sourceSliceIds,
                        known: allSourceSlices
                    )
                )
                try validateHistoricalEvidence(
                    day: day.date,
                    evidenceIDs: allEvidenceIDs(in: slice),
                    worktrees: worktreeByID,
                    proposalCreatedAt: proposal.createdAt
                )
            }
            for thought in day.independentThoughts {
                try validateSourceContributions(
                    thought.sourceSliceIds,
                    allowed: [.independentThought, .crossProject],
                    known: allSourceSlices,
                    owner: thought.id,
                    localSourceIDs: localSourceIDs
                )
                try validateGeneratedRecords(
                    parentID: thought.id,
                    decisions: thought.decisions,
                    learnings: thought.learnings,
                    values: thought.values,
                    directEvidenceIDs: thought.evidenceIds,
                    validEvidenceIDs: validEvidenceIDs,
                    messageClassification: messageClassification,
                    ownerMessageEvidenceIDs: messageEvidenceIDs(
                        sourceSliceIDs: thought.sourceSliceIds,
                        known: allSourceSlices
                    )
                )
                try validateHistoricalEvidence(
                    day: day.date,
                    evidenceIDs: allEvidenceIDs(in: thought),
                    worktrees: worktreeByID,
                    proposalCreatedAt: proposal.createdAt
                )
            }
            try validateClassificationProjectIdentities(day)
        }

        for node in proposal.nodes {
            try requireCandidate(node.reviewState, kind: "node", id: node.id)
            guard projectByID[node.projectId] != nil else {
                throw EvolutionProposalValidationError.missingReference("project", node.projectId)
            }
            try validateRoutes(node.routeIds, projectId: node.projectId, routesByID: routesByID)
            let expected = EvolutionStableID.evolutionNode(projectId: node.projectId, kind: node.kind, happenedAt: node.happenedAt, title: node.title)
            guard node.id == expected else {
                throw EvolutionProposalValidationError.stableIDMismatch("node", node.id)
            }
            try requireUnique(node.routeIds, kind: "node route reference")
            try requireUnique(node.sourceSliceIds, kind: "node source reference")
            try requireUnique(node.evidenceIds, kind: "node evidence reference")
            try validateSourceContributions(
                node.sourceSliceIds,
                allowed: [.project, .crossProject, .independentThought],
                known: allSourceSlices,
                owner: node.id,
                localSourceIDs: nil
            )
            for sourceSliceID in node.sourceSliceIds {
                guard let sourceSlice = allSourceSlices[sourceSliceID] else { continue }
                if sourceSlice.classification == .project || sourceSlice.classification == .crossProject,
                   !sourceSlice.projectIds.contains(node.projectId) {
                    throw EvolutionProposalValidationError.sourceProjectMismatch(node.id, sourceSliceID)
                }
            }
            try validateEvidence(
                node.evidenceIds,
                validEvidenceIDs: validEvidenceIDs,
                messageClassification: messageClassification,
                owner: node.id,
                ownerMessageEvidenceIDs: messageEvidenceIDs(
                    sourceSliceIDs: node.sourceSliceIds,
                    known: allSourceSlices
                )
            )
            try validateHistoricalEvidence(
                day: dayKey(node.happenedAt),
                evidenceIDs: node.evidenceIds,
                worktrees: worktreeByID,
                proposalCreatedAt: proposal.createdAt
            )
        }
    }

    private func validateCoverage(_ day: WorkEvolutionDayRecord) throws {
        let buckets = [
            day.coverage.includedSessionIds,
            day.coverage.pendingSessionIds,
            day.coverage.excludedSessionIds,
            day.coverage.processorSessionIds,
        ]
        let flattened = buckets.flatMap { $0 }
        guard Set(flattened).count == flattened.count else {
            throw EvolutionProposalValidationError.duplicateCoverageMembership(day.date)
        }
        guard flattened.count == day.coverage.expectedSessionCount else {
            throw EvolutionProposalValidationError.coverageCountMismatch(day.date)
        }
        let visibleSessionIDs = day.sourceSlices.map(\.sessionId)
        guard Set(visibleSessionIDs).count == visibleSessionIDs.count,
              Set(flattened) == Set(visibleSessionIDs) else {
            throw EvolutionProposalValidationError.coverageIdentityMismatch(day.date)
        }
        let included = Set(day.coverage.includedSessionIds)
        let pending = Set(day.coverage.pendingSessionIds)
        let excluded = Set(day.coverage.excludedSessionIds)
        let processor = Set(day.coverage.processorSessionIds)
        for slice in day.sourceSlices {
            let correct: Bool
            switch slice.classification {
            case .project, .crossProject, .independentThought: correct = included.contains(slice.sessionId)
            case .pending: correct = pending.contains(slice.sessionId)
            case .excluded: correct = excluded.contains(slice.sessionId)
            case .processor: correct = processor.contains(slice.sessionId)
            }
            guard correct else {
                throw EvolutionProposalValidationError.classificationCoverageMismatch(day.date, slice.sessionId)
            }
        }
    }

    private func validateClassificationProjectIdentities(
        _ day: WorkEvolutionDayRecord
    ) throws {
        var referencedProjectIDsBySource: [String: Set<String>] = [:]
        for projectSlice in day.projectSlices {
            for sourceSliceID in projectSlice.sourceSliceIds {
                referencedProjectIDsBySource[sourceSliceID, default: []].insert(projectSlice.projectId)
            }
        }

        for sourceSlice in day.sourceSlices {
            let declared = Set(sourceSlice.projectIds)
            let referenced = referencedProjectIDsBySource[sourceSlice.id] ?? []
            let validCardinality: Bool
            switch sourceSlice.classification {
            case .project:
                validCardinality = declared.count == 1
            case .crossProject:
                validCardinality = declared.count >= 2
            case .independentThought, .pending, .excluded, .processor:
                validCardinality = declared.isEmpty
            }
            guard validCardinality, declared == referenced else {
                throw EvolutionProposalValidationError.classificationCoverageMismatch(
                    day.date,
                    sourceSlice.id
                )
            }
        }
    }

    private func validate(
        _ snapshot: WorktreeEvidenceSnapshot,
        proposalCreatedAt: Date
    ) throws {
        try requireUnique(snapshot.changes.map(\.id), kind: "worktree change")
        try requireUnique(snapshot.checks.map(\.id), kind: "verification check")
        try requireUnique(snapshot.relevantCommits.map(\.id), kind: "git commit")
        for change in snapshot.changes {
            guard change.id == EvolutionStableID.worktreeFileChange(path: change.path, kind: change.kind, statusCode: change.statusCode) else {
                throw EvolutionProposalValidationError.stableIDMismatch("worktree change", change.id)
            }
        }
        for check in snapshot.checks {
            guard check.id == EvolutionStableID.verificationCheck(command: check.command) else {
                throw EvolutionProposalValidationError.stableIDMismatch("verification check", check.id)
            }
        }
        for commit in snapshot.relevantCommits {
            guard commit.id == "git:\(commit.commitHash)", commit.repoPath == snapshot.repoPath else {
                throw EvolutionProposalValidationError.invalidWorktreeEvidence(snapshot.id)
            }
        }
        let changes = snapshot.changes.map(changeFingerprint).sorted()
        let checks = snapshot.checks.map(checkFingerprint).sorted()
        let commits = snapshot.relevantCommits.map(commitFingerprint).sorted()
        guard snapshot.id == EvolutionStableID.worktree(
            repoPath: snapshot.repoPath,
            branch: snapshot.branch,
            head: snapshot.head,
            verificationStatus: snapshot.verificationStatus,
            limitation: snapshot.limitation,
            sortedChanges: changes,
            sortedChecks: checks,
            sortedCommits: commits
        ),
        snapshot.contentHash == EvolutionStableID.worktreeContentHash(
            repoPath: snapshot.repoPath,
            branch: snapshot.branch,
            head: snapshot.head,
            verificationStatus: snapshot.verificationStatus,
            limitation: snapshot.limitation,
            sortedChanges: changes,
            sortedChecks: checks,
            sortedCommits: commits
        ),
        snapshot.capturedAt <= proposalCreatedAt.addingTimeInterval(300) else {
            throw EvolutionProposalValidationError.invalidWorktreeEvidence(snapshot.id)
        }
        if snapshot.verificationStatus == .partial,
           snapshot.limitation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw EvolutionProposalValidationError.invalidWorktreeEvidence(snapshot.id)
        }
    }

    private func validateRoutes(
        _ routeIDs: [String],
        projectId: String,
        routesByID: [String: (projectId: String, route: ProjectRoute)]
    ) throws {
        for id in routeIDs {
            guard let route = routesByID[id] else {
                throw EvolutionProposalValidationError.missingReference("route", id)
            }
            guard route.projectId == projectId else {
                throw EvolutionProposalValidationError.missingReference("route for project \(projectId)", id)
            }
        }
    }

    private func validateGeneratedRecords(
        parentID: String,
        decisions: [DecisionRecord],
        learnings: [LearningRecord],
        values: [ValueRecord],
        directEvidenceIDs: [String],
        validEvidenceIDs: Set<String>,
        messageClassification: [String: DailySourceClassification],
        ownerMessageEvidenceIDs: Set<String>
    ) throws {
        try requireUnique(decisions.map(\.id), kind: "decision")
        try requireUnique(learnings.map(\.id), kind: "learning")
        try requireUnique(values.map(\.id), kind: "value")
        for decision in decisions {
            let expected = EvolutionStableID.decision(projectDaySliceId: parentID, decision: decision.decision, reason: decision.reason)
            guard decision.id == expected else { throw EvolutionProposalValidationError.stableIDMismatch("decision", decision.id) }
            try requireUnique(decision.evidenceIds, kind: "decision evidence reference")
            try validateEvidence(decision.evidenceIds, validEvidenceIDs: validEvidenceIDs, messageClassification: messageClassification, owner: decision.id, ownerMessageEvidenceIDs: ownerMessageEvidenceIDs)
        }
        for learning in learnings {
            let expected = EvolutionStableID.learning(projectDaySliceId: parentID, observation: learning.observation, lesson: learning.lesson)
            guard learning.id == expected else { throw EvolutionProposalValidationError.stableIDMismatch("learning", learning.id) }
            try requireUnique(learning.evidenceIds, kind: "learning evidence reference")
            try validateEvidence(learning.evidenceIds, validEvidenceIDs: validEvidenceIDs, messageClassification: messageClassification, owner: learning.id, ownerMessageEvidenceIDs: ownerMessageEvidenceIDs)
        }
        for value in values {
            let expected = EvolutionStableID.value(projectDaySliceId: parentID, kind: value.kind, title: value.title, detail: value.detail)
            guard value.id == expected else { throw EvolutionProposalValidationError.stableIDMismatch("value", value.id) }
            try requireUnique(value.evidenceIds, kind: "value evidence reference")
            try validateEvidence(value.evidenceIds, validEvidenceIDs: validEvidenceIDs, messageClassification: messageClassification, owner: value.id, ownerMessageEvidenceIDs: ownerMessageEvidenceIDs)
        }
        try validateEvidence(directEvidenceIDs, validEvidenceIDs: validEvidenceIDs, messageClassification: messageClassification, owner: parentID, ownerMessageEvidenceIDs: ownerMessageEvidenceIDs)
    }

    private func validateEvidence(
        _ evidenceIDs: [String],
        validEvidenceIDs: Set<String>,
        messageClassification: [String: DailySourceClassification],
        owner: String,
        ownerMessageEvidenceIDs: Set<String>
    ) throws {
        for evidenceID in evidenceIDs {
            guard validEvidenceIDs.contains(evidenceID) else {
                throw EvolutionProposalValidationError.missingReference("evidence", evidenceID)
            }
            if let classification = messageClassification[evidenceID],
               !Self.eligibleClassifications.contains(classification) {
                throw EvolutionProposalValidationError.ineligibleSourceContribution(owner)
            }
            if messageClassification[evidenceID] != nil,
               !ownerMessageEvidenceIDs.contains(evidenceID) {
                throw EvolutionProposalValidationError.ownerEvidenceMismatch(owner, evidenceID)
            }
        }
    }

    private func validateSourceContributions(
        _ sourceSliceIDs: [String],
        allowed: Set<DailySourceClassification>,
        known: [String: DailySessionSlice],
        owner: String,
        localSourceIDs: Set<String>?
    ) throws {
        for id in sourceSliceIDs {
            guard let slice = known[id] else {
                throw EvolutionProposalValidationError.missingReference("source slice", id)
            }
            if let localSourceIDs, !localSourceIDs.contains(id) {
                throw EvolutionProposalValidationError.missingReference("same-day source slice", id)
            }
            guard allowed.contains(slice.classification) else {
                throw EvolutionProposalValidationError.ineligibleSourceContribution(owner)
            }
        }
    }

    private func validateHistoricalEvidence(
        day: String,
        evidenceIDs: [String],
        worktrees: [String: WorktreeEvidenceSnapshot],
        proposalCreatedAt: Date
    ) throws {
        let interval = try naturalDayInterval(day)
        for id in Set(evidenceIDs) {
            guard let snapshot = worktrees[id] else { continue }
            if interval.start < taipeiStartOfDay(proposalCreatedAt),
               (snapshot.verificationStatus != .partial
                   || snapshot.limitation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false) {
                throw EvolutionProposalValidationError.historicalWorktreeOverclaim(id)
            }
        }
    }

    private func messageEvidenceIDs(
        sourceSliceIDs: [String],
        known: [String: DailySessionSlice]
    ) -> Set<String> {
        Set(sourceSliceIDs.flatMap { known[$0]?.messageReferences.map(\.id) ?? [] })
    }

    private func allEvidenceIDs(in slice: ProjectDaySlice) -> [String] {
        slice.evidenceIds
            + slice.decisions.flatMap(\.evidenceIds)
            + slice.learnings.flatMap(\.evidenceIds)
            + slice.values.flatMap(\.evidenceIds)
    }

    private func allEvidenceIDs(in thought: IndependentThought) -> [String] {
        thought.evidenceIds
            + thought.decisions.flatMap(\.evidenceIds)
            + thought.learnings.flatMap(\.evidenceIds)
            + thought.values.flatMap(\.evidenceIds)
    }

    private func requireUnique(_ ids: [String], kind: String) throws {
        var seen = Set<String>()
        for id in ids where !seen.insert(id).inserted {
            throw EvolutionProposalValidationError.duplicateIdentifier(kind, id)
        }
    }

    private func requireCandidate(_ state: ReviewState, kind: String, id: String) throws {
        guard state == .candidate else {
            throw EvolutionProposalValidationError.proposalContainsConfirmed(kind, id)
        }
    }

    private func naturalDayInterval(_ key: String) throws -> DateInterval {
        let pieces = key.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3,
              String(format: "%04d-%02d-%02d", pieces[0], pieces[1], pieces[2]) == key else {
            throw EvolutionProposalValidationError.invalidDate("day", key)
        }
        let calendar = Self.taipeiCalendar
        guard let start = calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2])),
              dayKey(start) == key,
              let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw EvolutionProposalValidationError.invalidDate("day", key)
        }
        return DateInterval(start: start, end: end)
    }

    private func dayKey(_ date: Date) -> String {
        let components = Self.taipeiCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func taipeiStartOfDay(_ date: Date) -> Date {
        Self.taipeiCalendar.startOfDay(for: date)
    }

    private func changeFingerprint(_ change: WorktreeFileChange) -> String {
        [change.path, change.kind.rawValue, change.statusCode].joined(separator: "\u{1f}")
    }

    private func checkFingerprint(_ check: VerificationCheck) -> String {
        [check.command.joined(separator: "\u{1d}"), check.status.rawValue, check.summary].joined(separator: "\u{1f}")
    }

    private func commitFingerprint(_ commit: GitEvidenceSummary) -> String {
        [
            commit.repoPath, commit.commitHash, commit.commitMessage,
            String(commit.changedFiles), String(commit.insertions), String(commit.deletions),
            commit.buildStatus ?? "", commit.testStatus ?? "", ISO8601Codec.string(from: commit.capturedAt),
        ].joined(separator: "\u{1f}")
    }

    private static let eligibleClassifications: Set<DailySourceClassification> = [
        .project, .crossProject, .independentThought,
    ]

    private static var taipeiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }
}
