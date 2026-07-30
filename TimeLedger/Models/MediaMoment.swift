import Foundation
import SwiftData

enum MediaKind: String, CaseIterable {
    case photo
    case video
}

enum MediaStoragePreference: String, CaseIterable, Identifiable {
    case photosLibrary
    case app
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photosLibrary:
            "系统相册"
        case .app:
            "TimeLedger"
        case .both:
            "两边"
        }
    }
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
