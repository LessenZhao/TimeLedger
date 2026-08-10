import Foundation
import SwiftData

nonisolated enum ComposerDraftStoreFactory {
    static func newTimeEntry(
        projectID: UUID,
        draftsRootURL: URL? = nil
    ) -> ThoughtComposerDraftStore {
        store(in: "TimeEntry-New-\(projectID.uuidString)", draftsRootURL: draftsRootURL)
    }

    static func timeEntry(
        _ entryID: UUID,
        draftsRootURL: URL? = nil
    ) -> ThoughtComposerDraftStore {
        store(in: "TimeEntry-\(entryID.uuidString)", draftsRootURL: draftsRootURL)
    }

    static func thoughtForEntry(
        _ entryID: UUID,
        draftsRootURL: URL? = nil
    ) -> ThoughtComposerDraftStore {
        store(in: "Thought-Entry-\(entryID.uuidString)", draftsRootURL: draftsRootURL)
    }

    private static func store(
        in directoryName: String,
        draftsRootURL: URL?
    ) -> ThoughtComposerDraftStore {
        let root = draftsRootURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "ComposerDrafts", directoryHint: .isDirectory)
        return ThoughtComposerDraftStore(
            rootURL: root.appending(path: directoryName, directoryHint: .isDirectory)
        )
    }
}

enum TimeEntryAttachmentError: LocalizedError {
    case missingStagedOriginal

    var errorDescription: String? {
        switch self {
        case .missingStagedOriginal:
            "找不到可恢复的照片原件，请重新添加。"
        }
    }
}
