import Foundation
import SwiftData

/// 历史发布版冻结模型，仅用于 migration 门禁与历史库读取。
/// 实体名与旧版 SwiftData 持久化一致；禁止业务代码读写这些类型。
enum LegacyMigration {
    enum TimeEntryStatus: String, CaseIterable {
        case draft
        case confirmed
    }

    enum ThoughtLinkSource: String, CaseIterable {
        case none
        case auto
        case manual
    }

    enum MediaKind: String, CaseIterable {
        case photo
        case video
    }

    enum MediaStoragePreference: String, CaseIterable {
        case photosLibrary
        case app
        case both
    }

    enum MediaStoredLocation: String, CaseIterable {
        case none
        case photosLibrary
        case app
        case both
    }

    enum MediaMomentStatus: String, CaseIterable {
        case pending
        case saved
        case partial
        case failed
    }

    enum MediaOriginalAvailability: String, CaseIterable {
        case unknown
        case available
        case unavailable
    }

    @Model
    final class AppSettings {
        @Attribute(.unique) var id: UUID
        var longUnclassifiedThresholdMinutes: Int
        var exportOnlyConfirmed: Bool
        var includeDraftInTodaySummary: Bool
        var mediaStoragePreference: String

        init(
            id: UUID = UUID(),
            longUnclassifiedThresholdMinutes: Int = 90,
            exportOnlyConfirmed: Bool = true,
            includeDraftInTodaySummary: Bool = true,
            mediaStoragePreference: MediaStoragePreference = .photosLibrary
        ) {
            self.id = id
            self.longUnclassifiedThresholdMinutes = longUnclassifiedThresholdMinutes
            self.exportOnlyConfirmed = exportOnlyConfirmed
            self.includeDraftInTodaySummary = includeDraftInTodaySummary
            self.mediaStoragePreference = mediaStoragePreference.rawValue
        }
    }

    @Model
    final class Project {
        @Attribute(.unique) var id: UUID
        var name: String
        var categoryName: String
        var emoji: String?
        var colorHex: String?
        var sortOrder: Int
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            name: String,
            categoryName: String,
            emoji: String? = nil,
            colorHex: String? = nil,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.name = name
            self.categoryName = categoryName
            self.emoji = emoji
            self.colorHex = colorHex
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class TimeCursor {
        @Attribute(.unique) var id: UUID
        var cursorAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            cursorAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.cursorAt = cursorAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class TimeEntry {
        @Attribute(.unique) var id: UUID
        var projectId: UUID
        var projectNameSnapshot: String
        var categoryNameSnapshot: String
        var startAt: Date
        var endAt: Date
        var note: String
        var status: String
        var createdAt: Date
        var updatedAt: Date

        var entryStatus: TimeEntryStatus {
            TimeEntryStatus(rawValue: status) ?? .draft
        }

        init(
            id: UUID = UUID(),
            projectId: UUID,
            projectNameSnapshot: String,
            categoryNameSnapshot: String,
            startAt: Date,
            endAt: Date,
            note: String = "",
            status: TimeEntryStatus = .draft,
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
            self.status = status.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class ThoughtNote {
        @Attribute(.unique) var id: UUID
        var body: String
        var capturedAt: Date
        var anchorAt: Date
        var linkedEntryId: UUID?
        var linkSource: String
        var createdAt: Date
        var updatedAt: Date

        var linkSourceEnum: ThoughtLinkSource {
            ThoughtLinkSource(rawValue: linkSource) ?? .none
        }

        init(
            id: UUID = UUID(),
            body: String,
            capturedAt: Date = Date(),
            anchorAt: Date? = nil,
            linkedEntryId: UUID? = nil,
            linkSource: ThoughtLinkSource = .none,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.body = body
            self.capturedAt = capturedAt
            self.anchorAt = anchorAt ?? capturedAt
            self.linkedEntryId = linkedEntryId
            self.linkSource = linkSource.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class ActionItem {
        @Attribute(.unique) var id: UUID
        var title: String
        var sortOrder: Int
        var isArchived: Bool
        var activeCycleStartedAt: Date?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            title: String,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            activeCycleStartedAt: Date? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.activeCycleStartedAt = activeCycleStartedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class ActionCompletion {
        @Attribute(.unique) var id: UUID
        var actionItemId: UUID
        var actionTitleSnapshot: String
        var completedAt: Date
        var dayStart: Date
        var linkedEntryId: UUID?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            actionItemId: UUID,
            actionTitleSnapshot: String,
            completedAt: Date,
            dayStart: Date,
            linkedEntryId: UUID? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.actionItemId = actionItemId
            self.actionTitleSnapshot = actionTitleSnapshot
            self.completedAt = completedAt
            self.dayStart = dayStart
            self.linkedEntryId = linkedEntryId
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class ThoughtMediaLink {
        @Attribute(.unique) var id: UUID
        var thoughtId: UUID
        @Attribute(.unique) var mediaMomentId: UUID
        var sortOrder: Int
        var createdAt: Date

        init(
            id: UUID = UUID(),
            thoughtId: UUID,
            mediaMomentId: UUID,
            sortOrder: Int,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.thoughtId = thoughtId
            self.mediaMomentId = mediaMomentId
            self.sortOrder = sortOrder
            self.createdAt = createdAt
        }
    }

    @Model
    final class MediaMoment {
        @Attribute(.unique) var id: UUID
        var mediaType: String
        var capturedAt: Date
        var anchorAt: Date
        var linkedEntryId: UUID?
        var linkSource: String
        var requestedStorage: String
        var storedLocation: String
        var appRelativePath: String?
        var photosAssetIdentifier: String?
        var pendingRelativePath: String?
        var sourceTemporaryPath: String?
        var thumbnailData: Data
        var durationSeconds: Double
        var status: String
        var lastError: String?
        var originalAvailability: String
        var createdAt: Date
        var updatedAt: Date

        var kind: MediaKind {
            MediaKind(rawValue: mediaType) ?? .photo
        }

        var linkSourceEnum: ThoughtLinkSource {
            ThoughtLinkSource(rawValue: linkSource) ?? .none
        }

        var storagePreference: MediaStoragePreference {
            MediaStoragePreference(rawValue: requestedStorage) ?? .photosLibrary
        }

        var storedLocationEnum: MediaStoredLocation {
            MediaStoredLocation(rawValue: storedLocation) ?? .none
        }

        var saveStatus: MediaMomentStatus {
            MediaMomentStatus(rawValue: status) ?? .failed
        }

        var availability: MediaOriginalAvailability {
            MediaOriginalAvailability(rawValue: originalAvailability) ?? .unknown
        }

        init(
            id: UUID = UUID(),
            kind: MediaKind,
            capturedAt: Date = Date(),
            anchorAt: Date? = nil,
            linkedEntryId: UUID? = nil,
            linkSource: ThoughtLinkSource = .none,
            requestedStorage: MediaStoragePreference,
            storedLocation: MediaStoredLocation = .none,
            appRelativePath: String? = nil,
            photosAssetIdentifier: String? = nil,
            pendingRelativePath: String? = nil,
            sourceTemporaryPath: String? = nil,
            thumbnailData: Data,
            durationSeconds: Double = 0,
            status: MediaMomentStatus = .pending,
            lastError: String? = nil,
            originalAvailability: MediaOriginalAvailability = .unknown,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.mediaType = kind.rawValue
            self.capturedAt = capturedAt
            self.anchorAt = anchorAt ?? capturedAt
            self.linkedEntryId = linkedEntryId
            self.linkSource = linkSource.rawValue
            self.requestedStorage = requestedStorage.rawValue
            self.storedLocation = storedLocation.rawValue
            self.appRelativePath = appRelativePath
            self.photosAssetIdentifier = photosAssetIdentifier
            self.pendingRelativePath = pendingRelativePath
            self.sourceTemporaryPath = sourceTemporaryPath
            self.thumbnailData = thumbnailData
            self.durationSeconds = durationSeconds
            self.status = status.rawValue
            self.lastError = lastError
            self.originalAvailability = originalAvailability.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}
