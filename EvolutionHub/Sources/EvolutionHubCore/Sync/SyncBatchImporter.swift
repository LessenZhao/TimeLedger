import Foundation
import EvolutionCore

public enum SyncBatchImporter {
    public static func importFile(at url: URL) throws -> SyncBatchFile {
        let data = try Data(contentsOf: url)
        return try ISO8601Codec.decoder.decode(SyncBatchFile.self, from: data)
    }

    @MainActor
    public static func applyToStore(
        batch: SyncBatchFile,
        store: HubStore
    ) throws -> (accepted: Int, conflicts: Int) {
        var existing = store.revisionState
        // Seed missing keys from current entities at revision 0 so first import always accepts.
        for entry in store.timeEntries {
            let key = "timeEntry:\(entry.id)"
            if existing[key] == nil {
                existing[key] = RevisionedRecord(revision: 0, updatedAt: entry.updatedAt)
            }
        }
        for thought in store.thoughtNotes {
            let key = "thoughtNote:\(thought.id)"
            if existing[key] == nil {
                existing[key] = RevisionedRecord(revision: 0, updatedAt: thought.updatedAt)
            }
        }
        for project in store.projects {
            let key = "project:\(project.id)"
            if existing[key] == nil {
                existing[key] = RevisionedRecord(revision: 0, updatedAt: Date.distantPast)
            }
        }

        let (accepted, conflicts, nextState) = SyncMerger.apply(envelopes: batch.envelopes, existing: existing)
        store.revisionState = nextState

        for env in accepted {
            switch env.entityType {
            case .timeEntry:
                let p = try env.decodePayload(TimeEntrySyncPayload.self)
                store.upsertTimeEntry(from: p)
            case .thoughtNote:
                let p = try env.decodePayload(ThoughtNoteSyncPayload.self)
                store.upsertThought(from: p)
            case .project:
                let p = try env.decodePayload(ProjectSyncPayload.self)
                store.upsertProject(from: p)
            case .dailyReview:
                let p = try env.decodePayload(DailyReviewSyncPayload.self)
                if p.date == store.dailyReviewDraft.date {
                    store.dailyReviewDraft.mainFocus = p.mainFocus
                    store.dailyReviewDraft.verifiedOutputs = p.verifiedOutputs
                    store.dailyReviewDraft.mainDeviation = p.mainDeviation
                    store.dailyReviewDraft.nextAdjustment = p.nextAdjustment
                }
                store.yesterdayAdjustmentByDate[p.date] = p.nextAdjustment
            default:
                break
            }
        }

        store.settings.iPhoneSyncStatus = "已导入 SyncBatch \(batch.deviceId) · 接受 \(accepted.count) · 冲突 \(conflicts.count)"
        store.lastMessage = "同步包导入：接受 \(accepted.count)，冲突/跳过 \(conflicts.count)"
        store.mergeConflicts = conflicts
        return (accepted.count, conflicts.count)
    }
}
