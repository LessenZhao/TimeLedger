import Foundation

/// Mac is a mirror: bookkeeping is allowed only while a phone session is connected.
public enum MirrorConnectionState: String, Codable, Sendable, Hashable {
    case disconnected
    case connecting
    case connected
    case syncing
    case error
}

public struct MirrorCursor: Codable, Sendable, Hashable {
    public var cursorAt: Date
    public var updatedAt: Date
    public var revision: Int

    public init(cursorAt: Date, updatedAt: Date = Date(), revision: Int = 1) {
        self.cursorAt = cursorAt
        self.updatedAt = updatedAt
        self.revision = revision
    }

    public func unclassifiedDuration(now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(cursorAt))
    }
}

public struct MirrorProject: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var categoryName: String
    public var sortOrder: Int
    public var isArchived: Bool
    public var revision: Int
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        categoryName: String,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        revision: Int = 1,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.categoryName = categoryName
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

public struct MirrorTimeEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var projectId: String
    public var projectNameSnapshot: String
    public var categoryNameSnapshot: String
    public var startAt: Date
    public var endAt: Date
    public var note: String
    public var status: String
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        projectNameSnapshot: String,
        categoryNameSnapshot: String,
        startAt: Date,
        endAt: Date,
        note: String = "",
        status: String = "draft",
        revision: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.projectNameSnapshot = projectNameSnapshot
        self.categoryNameSnapshot = categoryNameSnapshot
        self.startAt = startAt
        self.endAt = endAt
        self.note = note
        self.status = status
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isDraft: Bool { status == "draft" }
    public var isConfirmed: Bool { status == "confirmed" }
}

public struct MirrorThought: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var body: String
    public var capturedAt: Date
    public var anchorAt: Date
    public var linkedEntryId: String?
    public var linkSource: String
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        body: String,
        capturedAt: Date = Date(),
        anchorAt: Date? = nil,
        linkedEntryId: String? = nil,
        linkSource: String = "none",
        revision: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.body = body
        self.capturedAt = capturedAt
        self.anchorAt = anchorAt ?? capturedAt
        self.linkedEntryId = linkedEntryId
        self.linkSource = linkSource
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Full ledger image shared between phone and Mac while mirrored.
public struct MirrorLedgerSnapshot: Codable, Sendable, Hashable {
    public var protocolVersion: String
    public var phoneDeviceId: String
    public var macDeviceId: String?
    public var snapshotRevision: Int
    public var exportedAt: Date
    public var cursor: MirrorCursor
    public var projects: [MirrorProject]
    public var timeEntries: [MirrorTimeEntry]
    public var thoughts: [MirrorThought]

    public init(
        protocolVersion: String = EvolutionSchema.protocolVersion,
        phoneDeviceId: String,
        macDeviceId: String? = nil,
        snapshotRevision: Int = 1,
        exportedAt: Date = Date(),
        cursor: MirrorCursor,
        projects: [MirrorProject] = [],
        timeEntries: [MirrorTimeEntry] = [],
        thoughts: [MirrorThought] = []
    ) {
        self.protocolVersion = protocolVersion
        self.phoneDeviceId = phoneDeviceId
        self.macDeviceId = macDeviceId
        self.snapshotRevision = snapshotRevision
        self.exportedAt = exportedAt
        self.cursor = cursor
        self.projects = projects
        self.timeEntries = timeEntries
        self.thoughts = thoughts
    }
}

public enum MirrorLedgerError: Error, LocalizedError, Equatable {
    case notConnected
    case emptySegment
    case projectNotFound
    case entryNotFound
    case cannotModifyConfirmed
    case overlap
    case invalidRange

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "未连接 iPhone，无法记账。请先建立镜像连接。"
        case .emptySegment: return "当前未记录时间不足，无法生成记录。"
        case .projectNotFound: return "项目不存在。"
        case .entryNotFound: return "记录不存在。"
        case .cannotModifyConfirmed: return "已确认记录需先取消确认。"
        case .overlap: return "时间与其他记录重叠。"
        case .invalidRange: return "结束时间必须晚于开始时间。"
        }
    }
}
