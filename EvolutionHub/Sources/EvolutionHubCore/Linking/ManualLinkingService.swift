import Foundation
import EvolutionCore

public enum ManualLinkError: Error, LocalizedError, Equatable {
    case entryNotFound
    case eventNotFound
    case alreadyLinked

    public var errorDescription: String? {
        switch self {
        case .entryNotFound: return "找不到时间记录"
        case .eventNotFound: return "找不到上下文事件"
        case .alreadyLinked: return "已存在确认关联"
        }
    }
}

public enum ManualLinkingService {
    /// Creates a user-locked manual EvidenceLink. Does not remove other suggestions.
    public static func link(
        timeEntryId: String,
        contextEventId: String,
        existing: [EvidenceLink],
        now: Date = Date()
    ) throws -> EvidenceLink {
        if existing.contains(where: {
            $0.timeEntryId == timeEntryId
                && $0.contextEventId == contextEventId
                && $0.userState == .confirmed
        }) {
            throw ManualLinkError.alreadyLinked
        }

        return EvidenceLink(
            timeEntryId: timeEntryId,
            contextEventId: contextEventId,
            method: .manual,
            confidence: 1.0,
            userState: .confirmed,
            createdAt: now,
            updatedAt: now
        )
    }

    public static func reject(
        timeEntryId: String,
        contextEventId: String,
        existing: inout [EvidenceLink],
        now: Date = Date()
    ) {
        if let index = existing.firstIndex(where: {
            $0.timeEntryId == timeEntryId && $0.contextEventId == contextEventId
        }) {
            existing[index].userState = .rejected
            existing[index].updatedAt = now
            existing[index].method = .manual
        } else {
            existing.append(
                EvidenceLink(
                    timeEntryId: timeEntryId,
                    contextEventId: contextEventId,
                    method: .manual,
                    confidence: 0,
                    userState: .rejected,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
    }

    public static func confirmedLinks(from links: [EvidenceLink]) -> [EvidenceLink] {
        links.filter { $0.userState == .confirmed }
    }

    public static func unlinkedEvents(
        events: [ContextEvent],
        links: [EvidenceLink]
    ) -> [ContextEvent] {
        let confirmedEventIds = Set(
            links.filter { $0.userState == .confirmed }.map(\.contextEventId)
        )
        let rejectedOnly = Set(
            links.filter { $0.userState == .rejected }.map(\.contextEventId)
        )
        return events.filter { event in
            !confirmedEventIds.contains(event.id) && !rejectedOnly.contains(event.id)
        }
    }
}
