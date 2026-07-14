import Foundation
import EvolutionCore

/// Snapshot of a TimeLedger TimeEntry for Hub (not SwiftData).
public struct ImportedTimeEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var projectId: String
    public var projectNameSnapshot: String
    public var categoryNameSnapshot: String
    public var startAt: Date
    public var endAt: Date
    public var note: String
    public var status: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        projectId: String,
        projectNameSnapshot: String,
        categoryNameSnapshot: String,
        startAt: Date,
        endAt: Date,
        note: String,
        status: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.projectId = projectId
        self.projectNameSnapshot = projectNameSnapshot
        self.categoryNameSnapshot = categoryNameSnapshot
        self.startAt = startAt
        self.endAt = endAt
        self.note = note
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ImportedThoughtNote: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var body: String
    public var capturedAt: Date
    public var anchorAt: Date
    public var linkedEntryId: String?
    public var linkSource: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        body: String,
        capturedAt: Date,
        anchorAt: Date,
        linkedEntryId: String?,
        linkSource: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.body = body
        self.capturedAt = capturedAt
        self.anchorAt = anchorAt
        self.linkedEntryId = linkedEntryId
        self.linkSource = linkSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ImportedProject: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var categoryName: String

    public init(id: String, name: String, categoryName: String) {
        self.id = id
        self.name = name
        self.categoryName = categoryName
    }
}

public struct HubSettings: Codable, Sendable, Hashable {
    public var rawVaultPath: String
    public var agentSessionArchivePath: String
    public var chatgptArchiveRoot: String
    public var companionStatus: String
    public var iPhoneSyncStatus: String
    public var privacyExcludeRules: [String]

    public init(
        rawVaultPath: String = RawVaultLayout.defaultApplicationSupport().rootURL.path,
        agentSessionArchivePath: String = "",
        chatgptArchiveRoot: String = "",
        companionStatus: String = "未连接（V3.1 仅展示）",
        iPhoneSyncStatus: String = "未同步（V3.1 仅文件导入）",
        privacyExcludeRules: [String] = []
    ) {
        self.rawVaultPath = rawVaultPath
        self.agentSessionArchivePath = agentSessionArchivePath
        self.chatgptArchiveRoot = chatgptArchiveRoot
        self.companionStatus = companionStatus
        self.iPhoneSyncStatus = iPhoneSyncStatus
        self.privacyExcludeRules = privacyExcludeRules
    }
}
