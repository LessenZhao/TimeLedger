import Foundation
import SwiftData

struct ThoughtMediaLinkService {
    let modelContext: ModelContext

    @discardableResult
    func link(
        _ moment: MediaMoment,
        to thought: ThoughtNote,
        sortOrder: Int
    ) throws -> ThoughtMediaLink {
        let links = try modelContext.fetch(FetchDescriptor<ThoughtMediaLink>())
        if let existing = links.first(where: { $0.mediaMomentId == moment.id }) {
            existing.thoughtId = thought.id
            existing.sortOrder = sortOrder
            synchronize(moment, with: thought)
            try modelContext.save()
            return existing
        }

        let link = ThoughtMediaLink(
            thoughtId: thought.id,
            mediaMomentId: moment.id,
            sortOrder: sortOrder
        )
        modelContext.insert(link)
        synchronize(moment, with: thought)
        try modelContext.save()
        return link
    }

    func mediaMoments(
        for thought: ThoughtNote,
        links: [ThoughtMediaLink]? = nil,
        moments: [MediaMoment]? = nil
    ) throws -> [MediaMoment] {
        let allLinks = try links ?? modelContext.fetch(FetchDescriptor<ThoughtMediaLink>())
        let allMoments = try moments ?? modelContext.fetch(FetchDescriptor<MediaMoment>())
        let orderByMediaID = Dictionary(
            uniqueKeysWithValues: allLinks
                .filter { $0.thoughtId == thought.id }
                .map { ($0.mediaMomentId, $0.sortOrder) }
        )
        return allMoments
            .filter { orderByMediaID[$0.id] != nil }
            .sorted {
                orderByMediaID[$0.id, default: 0] < orderByMediaID[$1.id, default: 0]
            }
    }

    func synchronizeAttachedMedia(for thought: ThoughtNote) throws {
        let moments = try mediaMoments(for: thought)
        for moment in moments {
            synchronize(moment, with: thought)
        }
        if !moments.isEmpty {
            try modelContext.save()
        }
    }

    func removeLinks(for thought: ThoughtNote) throws {
        let links = try modelContext.fetch(FetchDescriptor<ThoughtMediaLink>())
            .filter { $0.thoughtId == thought.id }
        for link in links {
            modelContext.delete(link)
        }
        if !links.isEmpty {
            try modelContext.save()
        }
    }

    func removeLinks(for moment: MediaMoment) throws {
        let links = try modelContext.fetch(FetchDescriptor<ThoughtMediaLink>())
            .filter { $0.mediaMomentId == moment.id }
        for link in links {
            modelContext.delete(link)
        }
        if !links.isEmpty {
            try modelContext.save()
        }
    }

    private func synchronize(_ moment: MediaMoment, with thought: ThoughtNote) {
        moment.anchorAt = thought.anchorAt
        moment.linkedEntryId = thought.linkedEntryId
        moment.linkSource = thought.linkSource
        moment.updatedAt = Date()
    }
}
