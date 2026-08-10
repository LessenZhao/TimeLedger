import Foundation
import SwiftData
@testable import TimeLedger

enum LegacyThoughtTestModels {
    static let all: [any PersistentModel.Type] = TimeLedgerSchemaV3.models + [
        ThoughtNote.self,
        ThoughtMediaLink.self,
    ]
}


/// 测试目标内的 V2 回归夹具；生产源码不包含此实现。 业务统一由 TimeLedgerEngine 的 Journal 命令承担。
struct ThoughtLinkingService {
    let modelContext: ModelContext

    // MARK: - Quick Capture

    @discardableResult
    func quickCaptureThought(body: String, now: Date = Date()) throws -> ThoughtNote {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let thought = ThoughtNote(
            body: trimmed,
            capturedAt: now,
            anchorAt: now
        )
        modelContext.insert(thought)
        try modelContext.save()
        try tryAutoLinkThought(thought: thought)
        return thought
    }

    // MARK: - Auto Link (single thought)

    @discardableResult
    func tryAutoLinkThought(thought: ThoughtNote) throws -> Bool {
        guard thought.linkSourceEnum == .none else { return false }

        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startAt)]))
        let covering = entries.filter { entry in
            entry.startAt <= thought.anchorAt && entry.endAt >= thought.anchorAt
        }

        guard !covering.isEmpty else { return false }

        // If multiple cover (abnormal), pick the shortest duration; tie → keep unlinked
        if covering.count == 1 {
            let entry = covering[0]
            thought.linkedEntryId = entry.id
            thought.linkSource = ThoughtLinkSource.auto.rawValue
            thought.updatedAt = Date()
            try modelContext.save()
            try ThoughtMediaLinkService(modelContext: modelContext)
                .synchronizeAttachedMedia(for: thought)
            return true
        } else {
            let sorted = covering.sorted { a, b in
                a.durationSeconds < b.durationSeconds
            }
            if sorted[0].durationSeconds == sorted[1].durationSeconds {
                // ambiguous tie → don't link
                return false
            }
            let entry = sorted[0]
            thought.linkedEntryId = entry.id
            thought.linkSource = ThoughtLinkSource.auto.rawValue
            thought.updatedAt = Date()
            try modelContext.save()
            try ThoughtMediaLinkService(modelContext: modelContext)
                .synchronizeAttachedMedia(for: thought)
            return true
        }
    }

    // MARK: - Link Thoughts For New Entry (bulk)

    /// When a new TimeEntry is created, find all unlinked ThoughtNotes whose anchorAt
    /// falls within the entry's time range and auto-link them.
    @discardableResult
    func linkThoughtsForEntry(entry: TimeEntry) throws -> Int {
        let thoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
        let toLink = thoughts.filter { thought in
            thought.linkedEntryId == nil
            && thought.linkSourceEnum == .none
            && thought.anchorAt >= entry.startAt
            && thought.anchorAt <= entry.endAt
        }

        let now = Date()
        for thought in toLink {
            thought.linkedEntryId = entry.id
            thought.linkSource = ThoughtLinkSource.auto.rawValue
            thought.updatedAt = now
        }

        if !toLink.isEmpty {
            try modelContext.save()
            for thought in toLink {
                try ThoughtMediaLinkService(modelContext: modelContext)
                    .synchronizeAttachedMedia(for: thought)
            }
        }
        return toLink.count
    }

    // MARK: - Relink Auto Thoughts For Date

    /// Conservatively re-evaluate auto-linked thoughts for a given date.
    /// Only touches linkSource = .none (tries to link) or .auto whose link is stale.
    /// Manual links are never touched.
    @discardableResult
    func relinkAutoThoughtsForDate(_ date: Date, calendar: Calendar = .current) throws -> Int {
        let dayRange = DateRangeService.naturalDayRange(for: date, calendar: calendar)
        let thoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startAt)]))

        var relinkedCount = 0
        let now = Date()

        for thought in thoughts {
            // Only consider thoughts whose anchorAt falls on this day
            guard thought.anchorAt >= dayRange.lowerBound,
                  thought.anchorAt < dayRange.upperBound else {
                continue
            }

            switch thought.linkSourceEnum {
            case .manual:
                continue
            case .none:
                // Try to auto-link
                let covering = entries.filter { entry in
                    entry.startAt <= thought.anchorAt && entry.endAt >= thought.anchorAt
                }
                if let best = pickBestCovering(covering) {
                    thought.linkedEntryId = best.id
                    thought.linkSource = ThoughtLinkSource.auto.rawValue
                    thought.updatedAt = now
                    relinkedCount += 1
                }
            case .auto:
                // Check if current link is still valid
                if let linkedId = thought.linkedEntryId,
                   let linkedEntry = entries.first(where: { $0.id == linkedId }) {
                    if thought.anchorAt < linkedEntry.startAt || thought.anchorAt > linkedEntry.endAt {
                        // Stale: entry no longer covers anchorAt → try to find a new one
                        let covering = entries.filter { entry in
                            entry.startAt <= thought.anchorAt && entry.endAt >= thought.anchorAt
                        }
                        if let best = pickBestCovering(covering) {
                            thought.linkedEntryId = best.id
                            thought.updatedAt = now
                            relinkedCount += 1
                        } else {
                            // Unlink
                            thought.linkedEntryId = nil
                            thought.linkSource = ThoughtLinkSource.none.rawValue
                            thought.updatedAt = now
                            relinkedCount += 1
                        }
                    }
                } else {
                    // Linked entry no longer exists → try to re-link
                    let covering = entries.filter { entry in
                        entry.startAt <= thought.anchorAt && entry.endAt >= thought.anchorAt
                    }
                    if let best = pickBestCovering(covering) {
                        thought.linkedEntryId = best.id
                        thought.updatedAt = now
                        relinkedCount += 1
                    } else {
                        thought.linkedEntryId = nil
                        thought.linkSource = ThoughtLinkSource.none.rawValue
                        thought.updatedAt = now
                        relinkedCount += 1
                    }
                }
            }
        }

        if relinkedCount > 0 {
            try modelContext.save()
            for thought in thoughts {
                try ThoughtMediaLinkService(modelContext: modelContext)
                    .synchronizeAttachedMedia(for: thought)
            }
        }
        return relinkedCount
    }

    // MARK: - Manual Add / Link / Unlink

    @discardableResult
    func addThought(to entry: TimeEntry, body: String, now: Date = Date()) throws -> ThoughtNote {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let thought = ThoughtNote(
            body: trimmed,
            capturedAt: now,
            anchorAt: now,
            linkedEntryId: entry.id,
            linkSource: .manual
        )
        modelContext.insert(thought)
        try modelContext.save()
        return thought
    }

    func manuallyLinkThought(_ thought: ThoughtNote, to entry: TimeEntry) throws {
        thought.linkedEntryId = entry.id
        thought.linkSource = ThoughtLinkSource.manual.rawValue
        thought.updatedAt = Date()
        try modelContext.save()
        try ThoughtMediaLinkService(modelContext: modelContext)
            .synchronizeAttachedMedia(for: thought)
    }

    func unlinkThought(_ thought: ThoughtNote) throws {
        thought.linkedEntryId = nil
        thought.linkSource = ThoughtLinkSource.none.rawValue
        thought.updatedAt = Date()
        try modelContext.save()
        try ThoughtMediaLinkService(modelContext: modelContext)
            .synchronizeAttachedMedia(for: thought)
    }

    // MARK: - Queries

    func thoughtsForEntry(_ entry: TimeEntry) throws -> [ThoughtNote] {
        let thoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>(
            sortBy: [SortDescriptor(\.capturedAt)]
        ))
        return thoughts.filter { $0.linkedEntryId == entry.id }
    }

    func thoughtCountForEntry(_ entry: TimeEntry) throws -> Int {
        try thoughtsForEntry(entry).count
    }

    func thoughtsCapturedOnDate(_ date: Date, calendar: Calendar = .current) throws -> [ThoughtNote] {
        let dayRange = DateRangeService.naturalDayRange(for: date, calendar: calendar)
        let thoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>(
            sortBy: [SortDescriptor(\.capturedAt)]
        ))
        return thoughts.filter { thought in
            thought.capturedAt >= dayRange.lowerBound && thought.capturedAt < dayRange.upperBound
        }
    }

    func unlinkedThoughtsCapturedOnDate(_ date: Date, calendar: Calendar = .current) throws -> [ThoughtNote] {
        try thoughtsCapturedOnDate(date, calendar: calendar).filter { $0.linkedEntryId == nil }
    }

    // MARK: - Update / Delete

    func updateThought(_ thought: ThoughtNote, body: String) throws {
        thought.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        thought.updatedAt = Date()
        try modelContext.save()
    }

    func deleteThought(_ thought: ThoughtNote) throws {
        try ThoughtMediaLinkService(modelContext: modelContext).removeLinks(for: thought)
        modelContext.delete(thought)
        try modelContext.save()
    }

    // MARK: - Helpers

    private func pickBestCovering(_ entries: [TimeEntry]) -> TimeEntry? {
        guard !entries.isEmpty else { return nil }
        if entries.count == 1 { return entries[0] }
        let sorted = entries.sorted { $0.durationSeconds < $1.durationSeconds }
        if sorted[0].durationSeconds == sorted[1].durationSeconds {
            return nil // ambiguous tie
        }
        return sorted[0]
    }
}


/// 测试目标内的 V2 回归夹具；生产源码不包含此实现。 内容提交统一经 ContentEditorSession/TimeLedgerEngine。
enum ThoughtComposerCommitError: LocalizedError {
    case emptyDraft
    case missingAttachment

    var errorDescription: String? {
        switch self {
        case .emptyDraft:
            "请先输入文字或添加照片。"
        case .missingAttachment:
            "有附件原件不可用，草稿已保留，请重试。"
        }
    }
}

struct ThoughtComposerCommitResult {
    let thought: ThoughtNote
    let mediaMoments: [MediaMoment]

    var mediaIssues: [MediaMoment] {
        mediaMoments.filter { $0.saveStatus != .saved }
    }
}

@MainActor
struct ThoughtComposerCommitService {
    let modelContext: ModelContext

    let draftStore: ThoughtComposerDraftStore
    let mediaFileStore: MediaFileStore
    let photoLibrary: any MediaPhotoLibraryWriting

    init(
        modelContext: ModelContext,
        draftStore: ThoughtComposerDraftStore = ThoughtComposerDraftStore()
    ) {
        self.modelContext = modelContext
        self.draftStore = draftStore
        self.mediaFileStore = MediaFileStore()
        self.photoLibrary = SystemMediaPhotoLibrary()
    }

    init(
        modelContext: ModelContext,
        draftStore: ThoughtComposerDraftStore,
        mediaFileStore: MediaFileStore,
        photoLibrary: any MediaPhotoLibraryWriting
    ) {
        self.modelContext = modelContext
        self.draftStore = draftStore
        self.mediaFileStore = mediaFileStore
        self.photoLibrary = photoLibrary
    }

    func commit(
        _ draft: ThoughtComposerDraft,
        preference: MediaStoragePreference,
        targetEntry: TimeEntry? = nil
    ) async throws -> ThoughtComposerCommitResult {
        guard draft.hasContent else {
            throw ThoughtComposerCommitError.emptyDraft
        }

        let thought = try findOrCreateThought(for: draft, targetEntry: targetEntry)
        let existingMoments = try modelContext.fetch(FetchDescriptor<MediaMoment>())
        var momentByID = Dictionary(uniqueKeysWithValues: existingMoments.map { ($0.id, $0) })
        var committedMoments: [MediaMoment] = []
        let mediaService = MediaMomentService(
            modelContext: modelContext,
            fileStore: mediaFileStore,
            photoLibrary: photoLibrary
        )
        let linkService = ThoughtMediaLinkService(modelContext: modelContext)

        for (index, attachment) in draft.attachments.enumerated() {
            let moment: MediaMoment
            if let existing = momentByID[attachment.id] {
                moment = existing
            } else {
                let originalURL = draftStore.originalURL(for: attachment)
                guard FileManager.default.fileExists(atPath: originalURL.path) else {
                    throw ThoughtComposerCommitError.missingAttachment
                }
                moment = try await mediaService.saveCapture(
                    id: attachment.id,
                    sourceURL: originalURL,
                    kind: attachment.kind,
                    capturedAt: attachment.capturedAt,
                    thumbnailData: attachment.thumbnailData,
                    durationSeconds: attachment.durationSeconds,
                    preference: attachment.cameFromPhotoLibrary ? .app : preference,
                    autoLink: false
                )
                momentByID[moment.id] = moment
            }

            _ = try linkService.link(moment, to: thought, sortOrder: index)
            committedMoments.append(moment)
        }

        try await draftStore.discard()
        return ThoughtComposerCommitResult(
            thought: thought,
            mediaMoments: committedMoments
        )
    }

    private func findOrCreateThought(
        for draft: ThoughtComposerDraft,
        targetEntry: TimeEntry?
    ) throws -> ThoughtNote {
        let thoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
        if let existing = thoughts.first(where: { $0.id == draft.id }) {
            existing.body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.updatedAt = Date()
            try modelContext.save()
            if let targetEntry {
                try ThoughtLinkingService(modelContext: modelContext)
                    .manuallyLinkThought(existing, to: targetEntry)
            }
            return existing
        }

        let anchorAt = draft.anchorAt
            ?? draft.attachments.map(\.capturedAt).min()
            ?? Date()
        let thought = ThoughtNote(
            id: draft.id,
            body: draft.body.trimmingCharacters(in: .whitespacesAndNewlines),
            capturedAt: anchorAt,
            anchorAt: anchorAt
        )
        modelContext.insert(thought)
        try modelContext.save()
        if let targetEntry {
            try ThoughtLinkingService(modelContext: modelContext)
                .manuallyLinkThought(thought, to: targetEntry)
        } else {
            _ = try ThoughtLinkingService(modelContext: modelContext)
                .tryAutoLinkThought(thought: thought)
        }
        return thought
    }
}


/// 测试目标内的 V2 回归夹具；生产源码不包含此实现。 附件归属统一使用 ContentAttachment。
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

    func hasAttachedMedia(for thought: ThoughtNote) throws -> Bool {
        let thoughtID = thought.id
        var descriptor = FetchDescriptor<ThoughtMediaLink>(
            predicate: #Predicate { $0.thoughtId == thoughtID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first != nil
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

/// 测试目标内的 V2 回归夹具；生产源码不包含此实现。 编辑器附件统一使用 ContentAttachment。
@MainActor
struct TimeEntryAttachmentService {
    let modelContext: ModelContext

    let mediaFileStore: MediaFileStore
    let photoLibrary: any MediaPhotoLibraryWriting

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.mediaFileStore = MediaFileStore()
        self.photoLibrary = SystemMediaPhotoLibrary()
    }

    init(
        modelContext: ModelContext,
        mediaFileStore: MediaFileStore,
        photoLibrary: any MediaPhotoLibraryWriting
    ) {
        self.modelContext = modelContext
        self.mediaFileStore = mediaFileStore
        self.photoLibrary = photoLibrary
    }

    func noteAttachments(
        for entry: TimeEntry,
        moments: [MediaMoment]? = nil,
        thoughtLinks: [ThoughtMediaLink]? = nil
    ) throws -> [MediaMoment] {
        let allMoments = try moments ?? modelContext.fetch(FetchDescriptor<MediaMoment>())
        let allThoughtLinks = try thoughtLinks
            ?? modelContext.fetch(FetchDescriptor<ThoughtMediaLink>())
        let thoughtMediaIDs = Set(allThoughtLinks.map(\.mediaMomentId))

        return allMoments
            .filter {
                $0.linkedEntryId == entry.id
                    && !thoughtMediaIDs.contains($0.id)
            }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    func removeFromNote(_ moment: MediaMoment, entry: TimeEntry) throws {
        guard moment.linkedEntryId == entry.id else { return }
        moment.linkedEntryId = nil
        // Manual standalone ownership prevents later auto-reconciliation from
        // silently attaching this preserved media to another card.
        moment.linkSource = ThoughtLinkSource.manual.rawValue
        moment.updatedAt = Date()
        try modelContext.save()
    }

    func storagePreference() throws -> MediaStoragePreference {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        if let settings = try modelContext.fetch(descriptor).first {
            return MediaStoragePreference(rawValue: settings.mediaStoragePreference)
                ?? .photosLibrary
        }
        let settings = AppSettings()
        modelContext.insert(settings)
        try modelContext.save()
        return MediaStoragePreference(rawValue: settings.mediaStoragePreference)
            ?? .photosLibrary
    }

    @discardableResult
    func commit(
        _ attachment: ThoughtComposerDraftAttachment,
        from draftStore: ThoughtComposerDraftStore,
        to entry: TimeEntry,
        preference: MediaStoragePreference
    ) async throws -> MediaMoment {
        let mediaService = MediaMomentService(
            modelContext: modelContext,
            fileStore: mediaFileStore,
            photoLibrary: photoLibrary
        )
        let moments = try modelContext.fetch(FetchDescriptor<MediaMoment>())
        let moment: MediaMoment

        if let existing = moments.first(where: { $0.id == attachment.id }) {
            moment = existing
            if moment.saveStatus != .saved {
                await mediaService.retry(moment)
            }
        } else {
            let originalURL = draftStore.originalURL(for: attachment)
            guard FileManager.default.fileExists(atPath: originalURL.path) else {
                throw TimeEntryAttachmentError.missingStagedOriginal
            }
            moment = try await mediaService.saveCapture(
                id: attachment.id,
                sourceURL: originalURL,
                kind: attachment.kind,
                capturedAt: attachment.capturedAt,
                thumbnailData: attachment.thumbnailData,
                durationSeconds: attachment.durationSeconds,
                preference: attachment.cameFromPhotoLibrary ? .app : preference,
                autoLink: false
            )
        }

        try MediaLinkingService(modelContext: modelContext).manuallyLink(moment, to: entry)
        return moment
    }
}
