import Foundation

public struct EvolutionMarkdownExporter: Sendable {
    private static let derivedWarning = "<!-- Derived from records/ledger.json. Edit in TimeLedger, not in this file. -->"

    public var layout: EvolutionLedgerLayout

    public init(layout: EvolutionLedgerLayout) {
        self.layout = layout
    }

    public func export(snapshot: EvolutionSnapshot) throws {
        try layout.ensureDirectories()

        let dayKeys = Set(snapshot.days.map(\.date))
            .union(snapshot.nodes.map { Self.dayKey($0.recognizedAt) })
            .union(snapshot.annotations.map { Self.dayKey($0.recognizedAt) })
            .sorted()
        let daysByKey = Dictionary(uniqueKeysWithValues: snapshot.days.map { ($0.date, $0) })
        for dayKey in dayKeys {
            let markdown = dailyMarkdown(for: dayKey, day: daysByKey[dayKey], snapshot: snapshot)
            let url = layout.dailyMapsDirectoryURL.appendingPathComponent("\(dayKey).md")
            try write(markdown, to: url)
        }

        for project in snapshot.projects.sorted(by: { ($0.name, $0.id) < ($1.name, $1.id) }) {
            let markdown = projectMarkdown(for: project, snapshot: snapshot)
            let filename = Self.sanitizedFilenameComponent(project.id)
            let url = layout.projectEvolutionsDirectoryURL.appendingPathComponent("\(filename).md")
            try write(markdown, to: url)
        }
    }

    private func dailyMarkdown(
        for dayKey: String,
        day: WorkEvolutionDayRecord?,
        snapshot: EvolutionSnapshot
    ) -> String {
        let coverage = day?.coverage ?? SourceCoverage(
            expectedSessionCount: 0,
            includedSessionIds: [],
            pendingSessionIds: [],
            excludedSessionIds: [],
            processorSessionIds: []
        )
        var lines = [
            Self.derivedWarning,
            "# Daily Map: \(inline(dayKey))",
            "",
            "Source cutoff: \(day.map { timestamp($0.sourceCutoffAt) } ?? "—")",
            "",
            "## Source Coverage",
            "",
            "Expected sessions: \(coverage.expectedSessionCount)",
            "",
        ]
        appendCoverageBucket("Included", ids: coverage.includedSessionIds, to: &lines)
        appendCoverageBucket("Pending", ids: coverage.pendingSessionIds, to: &lines)
        appendCoverageBucket("Excluded", ids: coverage.excludedSessionIds, to: &lines)
        appendCoverageBucket("Processor", ids: coverage.processorSessionIds, to: &lines)

        lines += ["## Projects", ""]
        let projectsByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0) })
        let routesByID = Dictionary(uniqueKeysWithValues: snapshot.projects.flatMap(\.routes).map { ($0.id, $0) })
        let slices = (day?.projectSlices ?? []).sorted {
            let leftName = projectsByID[$0.projectId]?.name ?? $0.projectId
            let rightName = projectsByID[$1.projectId]?.name ?? $1.projectId
            return (leftName, $0.projectId, $0.id) < (rightName, $1.projectId, $1.id)
        }
        if slices.isEmpty {
            lines += ["- None", ""]
        } else {
            for slice in slices {
                let name = projectsByID[slice.projectId]?.name ?? slice.projectId
                lines += [
                    "### \(inline(name)) (\(inline(slice.projectId)))",
                    "",
                    "Purpose: \(inline(slice.purpose))",
                    "",
                    "Progress: \(inline(slice.progress))",
                    "",
                    "Fact level: \(slice.factLevel.rawValue)",
                    "",
                    "Routes: \(joinedOrDash(slice.routeIds.sorted().map { routesByID[$0]?.name ?? $0 }))",
                    "",
                    "#### Actions",
                    "",
                ]
                appendBullets(slice.actions.sorted(), to: &lines)
                lines += ["#### Decisions", ""]
                appendDecisions(slice.decisions, to: &lines)
                lines += ["#### Errors and Learnings", ""]
                appendLearnings(slice.learnings, to: &lines)
                appendValues(slice.values, headingLevel: 4, to: &lines)
            }
        }

        lines += ["## Independent Thoughts", ""]
        let thoughts = (day?.independentThoughts ?? []).sorted { ($0.title, $0.id) < ($1.title, $1.id) }
        if thoughts.isEmpty {
            lines += ["- None", ""]
        } else {
            for thought in thoughts {
                lines += [
                    "### \(inline(thought.title))",
                    "",
                    inline(thought.body),
                    "",
                    "Fact level: \(thought.factLevel.rawValue)",
                    "",
                ]
                if !thought.decisions.isEmpty {
                    lines += ["#### Decisions", ""]
                    appendDecisions(thought.decisions, to: &lines)
                }
                if !thought.learnings.isEmpty {
                    lines += ["#### Learnings", ""]
                    appendLearnings(thought.learnings, to: &lines)
                }
                if !thought.values.isEmpty {
                    appendValues(thought.values, headingLevel: 4, to: &lines)
                }
            }
        }

        lines += ["## Evolution Nodes Recognized Today", ""]
        let recognizedNodes = snapshot.nodes
            .filter { Self.dayKey($0.recognizedAt) == dayKey }
            .sorted(by: nodeOrdering)
        appendNodes(recognizedNodes, to: &lines)

        lines += ["## User Annotations", ""]
        let annotations = snapshot.annotations
            .filter { Self.dayKey($0.recognizedAt) == dayKey }
            .sorted(by: annotationOrdering)
        appendAnnotations(annotations, to: &lines)

        lines += ["## Source Sessions", ""]
        let sourceSlices = day?.sourceSlices ?? []
        let sourceSliceSessionIDs = sourceSlices.map(\.sessionId)
        let coverageSessionIDs = coverage.includedSessionIds
            + coverage.pendingSessionIds
            + coverage.excludedSessionIds
            + coverage.processorSessionIds
        let sessionIDs = Set(sourceSliceSessionIDs + coverageSessionIDs).sorted()
        let sessionsByID = Dictionary(uniqueKeysWithValues: snapshot.sourceSessions.map { ($0.id, $0) })
        let slicesBySessionID = Dictionary(grouping: sourceSlices, by: \.sessionId)
        if sessionIDs.isEmpty {
            lines += ["- None", ""]
        } else {
            for sessionID in sessionIDs {
                let classifications = Set((slicesBySessionID[sessionID] ?? []).map(\.classification.rawValue)).sorted()
                if let session = sessionsByID[sessionID] {
                    lines.append("- \(inline(session.id)) | \(session.source.rawValue) | \(inline(session.externalThreadId)) | \(inline(session.title)) | \(joinedOrDash(classifications))")
                } else {
                    lines.append("- \(inline(sessionID)) | metadata unavailable | \(joinedOrDash(classifications))")
                }
            }
            lines.append("")
        }

        return finalized(lines)
    }

    private func projectMarkdown(
        for project: EvolutionProject,
        snapshot: EvolutionSnapshot
    ) -> String {
        var lines = [
            Self.derivedWarning,
            "# Project Evolution: \(inline(project.name))",
            "",
            "Project ID: \(inline(project.id))",
            "",
            "Goal: \(inline(project.goal))",
            "",
            "Aliases: \(joinedOrDash(project.aliases.sorted()))",
            "",
            "Progress status: \(project.progressStatus.rawValue)",
            "",
            "End mode: \(project.endMode?.rawValue ?? "—")",
            "",
            "Artifact status: \(project.artifactStatus.rawValue)",
            "",
            "Review state: \(project.reviewState.rawValue)",
            "",
            "## Routes",
            "",
        ]

        let routes = project.routes.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id < $1.id
        }
        if routes.isEmpty {
            lines += ["- None", ""]
        } else {
            for route in routes {
                lines += [
                    "### \(inline(route.name))",
                    "",
                    "- ID: \(inline(route.id))",
                    "- Status: \(route.status.rawValue)",
                    "- Started: \(timestamp(route.startedAt))",
                    "- Ended: \(route.endedAt.map(timestamp) ?? "—")",
                    "- Summary: \(inline(route.summary))",
                    "- Repositories: \(joinedOrDash(route.repoPaths.sorted()))",
                    "",
                ]
            }
        }

        lines += ["## Evolution Timeline", ""]
        let nodes = snapshot.nodes.filter { $0.projectId == project.id }.sorted(by: nodeOrdering)
        appendNodes(nodes, to: &lines)

        lines += ["## Daily Contributions", ""]
        let contributions = snapshot.days.flatMap { day in
            day.projectSlices.filter { $0.projectId == project.id }
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }
        if contributions.isEmpty {
            lines += ["- None", ""]
        } else {
            for slice in contributions {
                lines += [
                    "### \(inline(slice.date))",
                    "",
                    "- Purpose: \(inline(slice.purpose))",
                    "- Actions: \(joinedOrDash(slice.actions.sorted()))",
                    "- Progress: \(inline(slice.progress))",
                    "- Routes: \(joinedOrDash(slice.routeIds.sorted()))",
                    "",
                ]
                lines += ["#### Decisions", ""]
                appendDecisions(slice.decisions, to: &lines)
                lines += ["#### Errors and Learnings", ""]
                appendLearnings(slice.learnings, to: &lines)
                appendValues(slice.values, headingLevel: 4, to: &lines)
            }
        }

        lines += ["## User Annotations", ""]
        let annotations = snapshot.annotations.filter {
            annotation($0, belongsTo: project.id, snapshot: snapshot)
        }.sorted(by: annotationOrdering)
        appendAnnotations(annotations, to: &lines)

        return finalized(lines)
    }

    private func annotation(
        _ annotation: UserAnnotation,
        belongsTo projectID: String,
        snapshot: EvolutionSnapshot
    ) -> Bool {
        switch annotation.target.kind {
        case .project:
            return annotation.target.targetId == projectID
        case .projectDaySlice:
            return snapshot.days.flatMap(\.projectSlices).contains {
                $0.id == annotation.target.targetId && $0.projectId == projectID
            }
        case .evolutionNode:
            return snapshot.nodes.contains {
                $0.id == annotation.target.targetId && $0.projectId == projectID
            }
        case .sourceSession:
            return snapshot.days.flatMap(\.sourceSlices).contains {
                $0.sessionId == annotation.target.targetId && $0.projectIds.contains(projectID)
            }
        case .day:
            // A day can contain several projects, so a day-level note cannot be
            // assigned to one project without inventing a relationship.
            return false
        }
    }

    private func appendCoverageBucket(_ title: String, ids: [String], to lines: inout [String]) {
        lines += ["### \(title)", ""]
        appendBullets(Set(ids).sorted(), to: &lines)
    }

    private func appendDecisions(_ decisions: [DecisionRecord], to lines: inout [String]) {
        let sorted = decisions.sorted { ($0.title, $0.id) < ($1.title, $1.id) }
        if sorted.isEmpty {
            lines += ["- None", ""]
            return
        }
        for decision in sorted {
            lines += [
                "- \(inline(decision.title))",
                "  - Decision: \(inline(decision.decision))",
                "  - Reason: \(inline(decision.reason))",
                "  - Alternatives: \(joinedOrDash(decision.alternatives.sorted()))",
                "  - Fact level: \(decision.factLevel.rawValue)",
            ]
        }
        lines.append("")
    }

    private func appendLearnings(_ learnings: [LearningRecord], to lines: inout [String]) {
        let sorted = learnings.sorted { ($0.kind.rawValue, $0.observation, $0.id) < ($1.kind.rawValue, $1.observation, $1.id) }
        if sorted.isEmpty {
            lines += ["- None", ""]
            return
        }
        for learning in sorted {
            lines += [
                "- [\(learning.kind.rawValue)] \(inline(learning.observation))",
                "  - Lesson: \(inline(learning.lesson))",
                "  - Reusable principle: \(learning.reusablePrinciple.map(inline) ?? "—")",
                "  - Fact level: \(learning.factLevel.rawValue)",
            ]
        }
        lines.append("")
    }

    private func appendValues(_ values: [ValueRecord], headingLevel: Int, to lines: inout [String]) {
        let heading = String(repeating: "#", count: headingLevel)
        let sections: [(ValueKind, String)] = [
            (.project, "Project Value"),
            (.process, "Process Value"),
            (.crossProject, "Cross-project Value"),
        ]
        for (kind, title) in sections {
            lines += ["\(heading) \(title)", ""]
            let records = values.filter { $0.kind == kind }.sorted { ($0.title, $0.id) < ($1.title, $1.id) }
            if records.isEmpty {
                lines += ["- None", ""]
                continue
            }
            for value in records {
                lines += [
                    "- \(inline(value.title)): \(inline(value.detail))",
                    "  - Status: \(value.status.rawValue)",
                    "  - Fact level: \(value.factLevel.rawValue)",
                ]
            }
            lines.append("")
        }
    }

    private func appendNodes(_ nodes: [EvolutionNode], to lines: inout [String]) {
        if nodes.isEmpty {
            lines += ["- None", ""]
            return
        }
        for node in nodes {
            lines += [
                "### \(timestamp(node.happenedAt)) — \(inline(node.title))",
                "",
                "- Kind: \(node.kind.rawValue)",
                "- Detail: \(inline(node.detail))",
                "- Reason: \(inline(node.reason))",
                "- Routes: \(joinedOrDash(node.routeIds.sorted()))",
                "- Origin: \(node.origin.rawValue)",
                "- Fact level: \(node.factLevel.rawValue)",
                "- Recognized: \(timestamp(node.recognizedAt))",
                "",
            ]
        }
    }

    private func appendAnnotations(_ annotations: [UserAnnotation], to lines: inout [String]) {
        if annotations.isEmpty {
            lines += ["- None", ""]
            return
        }
        for annotation in annotations {
            lines += [
                "- [\(annotation.kind.rawValue)] \(inline(annotation.body))",
                "  - Target: \(annotation.target.kind.rawValue)/\(inline(annotation.target.targetId))",
                "  - Happened: \(annotation.happenedAt.map(timestamp) ?? "—")",
                "  - Recognized: \(timestamp(annotation.recognizedAt))",
            ]
        }
        lines.append("")
    }

    private func appendBullets(_ values: [String], to lines: inout [String]) {
        if values.isEmpty {
            lines += ["- None", ""]
        } else {
            lines += values.map { "- \(inline($0))" }
            lines.append("")
        }
    }

    private func write(_ markdown: String, to url: URL) throws {
        try Data(markdown.utf8).write(to: url, options: .atomic)
    }

    private func finalized(_ lines: [String]) -> String {
        var result = lines.joined(separator: "\n")
        while result.hasSuffix("\n\n") { result.removeLast() }
        if !result.hasSuffix("\n") { result.append("\n") }
        return result
    }

    private func inline(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func joinedOrDash(_ values: [String]) -> String {
        values.isEmpty ? "—" : values.map(inline).joined(separator: ", ")
    }

    private func timestamp(_ date: Date) -> String {
        ISO8601Codec.string(from: date)
    }

    private func nodeOrdering(_ lhs: EvolutionNode, _ rhs: EvolutionNode) -> Bool {
        if lhs.happenedAt != rhs.happenedAt { return lhs.happenedAt < rhs.happenedAt }
        if lhs.recognizedAt != rhs.recognizedAt { return lhs.recognizedAt < rhs.recognizedAt }
        return lhs.id < rhs.id
    }

    private func annotationOrdering(_ lhs: UserAnnotation, _ rhs: UserAnnotation) -> Bool {
        if lhs.recognizedAt != rhs.recognizedAt { return lhs.recognizedAt < rhs.recognizedAt }
        return lhs.id < rhs.id
    }

    private static func sanitizedFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let sanitized = String(scalars)
        return sanitized.isEmpty ? "project" : sanitized
    }

    private static func dayKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
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
