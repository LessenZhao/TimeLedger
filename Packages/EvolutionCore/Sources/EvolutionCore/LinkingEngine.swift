import Foundation

public struct LinkingConfig: Codable, Sendable, Hashable {
    public var autoLinkThreshold: Double
    public var suggestThreshold: Double

    public static let `default` = LinkingConfig(autoLinkThreshold: 0.90, suggestThreshold: 0.60)

    public init(autoLinkThreshold: Double = 0.90, suggestThreshold: Double = 0.60) {
        self.autoLinkThreshold = autoLinkThreshold
        self.suggestThreshold = suggestThreshold
    }
}

public struct LinkCandidate: Sendable, Hashable {
    public var timeEntryId: String
    public var contextEventId: String
    public var method: EvidenceLinkMethod
    public var confidence: Double
    public var reason: String

    public init(
        timeEntryId: String,
        contextEventId: String,
        method: EvidenceLinkMethod,
        confidence: Double,
        reason: String
    ) {
        self.timeEntryId = timeEntryId
        self.contextEventId = contextEventId
        self.method = method
        self.confidence = confidence
        self.reason = reason
    }
}

public struct TimelineEntryLike: Sendable, Hashable {
    public var id: String
    public var projectId: String
    public var projectName: String
    public var startAt: Date
    public var endAt: Date

    public init(id: String, projectId: String, projectName: String, startAt: Date, endAt: Date) {
        self.id = id
        self.projectId = projectId
        self.projectName = projectName
        self.startAt = startAt
        self.endAt = endAt
    }
}

public enum LinkingEngine {
    /// Suggest links. Never overrides user-locked EvidenceLinks.
    public static func suggest(
        entries: [TimelineEntryLike],
        events: [ContextEvent],
        existingLinks: [EvidenceLink],
        cwdMappings: [String: String] = [:],
        config: LinkingConfig = .default,
        now: Date = Date()
    ) -> (auto: [EvidenceLink], suggested: [EvidenceLink], inboxEventIds: [String]) {
        let lockedEventIds = Set(
            existingLinks.filter(\.isUserLocked).map(\.contextEventId)
        )
        var auto: [EvidenceLink] = []
        var suggested: [EvidenceLink] = []
        var bestByEvent: [String: LinkCandidate] = [:]

        for event in events {
            if lockedEventIds.contains(event.id) { continue }
            var candidates: [LinkCandidate] = []

            for entry in entries {
                if let c = score(entry: entry, event: event, cwdMappings: cwdMappings) {
                    candidates.append(c)
                }
            }
            guard let best = candidates.max(by: { $0.confidence < $1.confidence }) else {
                continue
            }
            bestByEvent[event.id] = best
        }

        var claimedEvents = Set<String>()
        for (eventId, candidate) in bestByEvent {
            if candidate.confidence >= config.autoLinkThreshold {
                auto.append(EvidenceLink(
                    timeEntryId: candidate.timeEntryId,
                    contextEventId: eventId,
                    method: candidate.method,
                    confidence: candidate.confidence,
                    userState: .confirmed,
                    createdAt: now,
                    updatedAt: now
                ))
                claimedEvents.insert(eventId)
            } else if candidate.confidence >= config.suggestThreshold {
                suggested.append(EvidenceLink(
                    timeEntryId: candidate.timeEntryId,
                    contextEventId: eventId,
                    method: candidate.method,
                    confidence: candidate.confidence,
                    userState: .suggested,
                    createdAt: now,
                    updatedAt: now
                ))
                claimedEvents.insert(eventId)
            }
        }

        let inbox = events
            .map(\.id)
            .filter { !lockedEventIds.contains($0) && !claimedEvents.contains($0) }

        return (auto, suggested, inbox)
    }

    public static func score(
        entry: TimelineEntryLike,
        event: ContextEvent,
        cwdMappings: [String: String]
    ) -> LinkCandidate? {
        var best: LinkCandidate?

        // 1. time overlap
        let eventEnd = event.endedAt ?? event.startedAt.addingTimeInterval(30 * 60)
        let overlapStart = max(entry.startAt, event.startedAt)
        let overlapEnd = min(entry.endAt, eventEnd)
        let overlap = max(0, overlapEnd.timeIntervalSince(overlapStart))
        if overlap > 0 {
            let entryDur = max(1, entry.endAt.timeIntervalSince(entry.startAt))
            let ratio = min(1.0, overlap / entryDur)
            let confidence = 0.55 + 0.35 * ratio
            best = pick(best, LinkCandidate(
                timeEntryId: entry.id,
                contextEventId: event.id,
                method: .timeOverlap,
                confidence: confidence,
                reason: "时间重叠 \(Int(overlap / 60)) 分钟"
            ))
        }

        // 2. cwd → project mapping
        if let hint = event.projectHint, !hint.isEmpty {
            for (prefix, projectId) in cwdMappings {
                if hint.hasPrefix(prefix) || prefix.contains(hint) || hint == entry.projectName {
                    if projectId == entry.projectId || hint.localizedCaseInsensitiveContains(entry.projectName) {
                        best = pick(best, LinkCandidate(
                            timeEntryId: entry.id,
                            contextEventId: event.id,
                            method: .cwdMapping,
                            confidence: 0.92,
                            reason: "cwd/项目映射: \(hint)"
                        ))
                    }
                }
            }
            if hint.localizedCaseInsensitiveContains(entry.projectName)
                || entry.projectName.localizedCaseInsensitiveContains(hint)
            {
                best = pick(best, LinkCandidate(
                    timeEntryId: entry.id,
                    contextEventId: event.id,
                    method: .cwdMapping,
                    confidence: 0.91,
                    reason: "projectHint 匹配项目名"
                ))
            }
        }

        // 3. title vs project name
        if event.title.localizedCaseInsensitiveContains(entry.projectName)
            || entry.projectName.localizedCaseInsensitiveContains(event.title)
        {
            best = pick(best, LinkCandidate(
                timeEntryId: entry.id,
                contextEventId: event.id,
                method: .projectName,
                confidence: 0.72,
                reason: "标题与项目名相似"
            ))
        }

        return best
    }

    private static func pick(_ a: LinkCandidate?, _ b: LinkCandidate) -> LinkCandidate {
        guard let a else { return b }
        return b.confidence > a.confidence ? b : a
    }
}
