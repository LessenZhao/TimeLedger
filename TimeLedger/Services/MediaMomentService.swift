import Foundation
import Photos
import SwiftData

enum MediaMomentServiceError: LocalizedError {
    case missingRecoverableOriginal
    case photosPermissionDenied
    case photosWriteFailed

    var errorDescription: String? {
        switch self {
        case .missingRecoverableOriginal:
            "找不到可恢复的原件。时间点和缩略图仍会保留。"
        case .photosPermissionDenied:
            "照片库权限未开启，无法把原件保存到系统相册。"
        case .photosWriteFailed:
            "系统相册没有返回已保存的媒体标识。"
        }
    }
}

protocol MediaPhotoLibraryWriting {
    func saveOriginal(at fileURL: URL, kind: MediaKind) async throws -> String
    func assetExists(identifier: String) async -> Bool
}

struct SystemMediaPhotoLibrary: MediaPhotoLibraryWriting {
    func saveOriginal(at fileURL: URL, kind: MediaKind) async throws -> String {
        let authorization = await requestAuthorization()
        guard authorization == .authorized || authorization == .limited else {
            throw MediaMomentServiceError.photosPermissionDenied
        }

        var localIdentifier: String?
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request: PHAssetChangeRequest?
                switch kind {
                case .photo:
                    request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                case .video:
                    request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }
                localIdentifier = request?.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: MediaMomentServiceError.photosWriteFailed)
                }
            }
        }

        guard let localIdentifier else {
            throw MediaMomentServiceError.photosWriteFailed
        }
        return localIdentifier
    }

    func assetExists(identifier: String) async -> Bool {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        return result.firstObject != nil
    }

    private func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

struct MediaFileStore {
    let rootURL: URL

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.rootURL = base.appending(path: "MediaMoments", directoryHint: .isDirectory)
        }
    }

    func stage(originalAt sourceURL: URL, id: UUID, fileExtension: String) async throws -> String {
        let rootURL = rootURL
        return try await Task.detached(priority: .userInitiated) {
            let directory = rootURL.appending(path: "Pending", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let relativePath = "Pending/\(id.uuidString).\(fileExtension)"
            let destination = rootURL.appending(path: relativePath)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return relativePath
        }.value
    }

    func copyToApp(relativePath: String, id: UUID, fileExtension: String) async throws -> String {
        try await copyToApp(
            sourceURL: rootURL.appending(path: relativePath),
            id: id,
            fileExtension: fileExtension
        )
    }

    func copyToApp(sourceURL: URL, id: UUID, fileExtension: String) async throws -> String {
        let rootURL = rootURL
        return try await Task.detached(priority: .userInitiated) {
            let directory = rootURL.appending(path: "Originals", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destinationRelativePath = "Originals/\(id.uuidString).\(fileExtension)"
            let destination = rootURL.appending(path: destinationRelativePath)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destinationRelativePath
        }.value
    }

    func delete(relativePath: String?) async {
        guard let relativePath else { return }
        let rootURL = rootURL
        await Task.detached(priority: .utility) {
            let url = rootURL.appending(path: relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try? FileManager.default.removeItem(at: url)
        }.value
    }

    func delete(absolutePath: String?) async {
        guard let absolutePath else { return }
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: absolutePath) else { return }
            try? FileManager.default.removeItem(atPath: absolutePath)
        }.value
    }

    func exists(relativePath: String?) async -> Bool {
        guard let relativePath else { return false }
        let rootURL = rootURL
        return await Task.detached(priority: .utility) {
            FileManager.default.fileExists(atPath: rootURL.appending(path: relativePath).path)
        }.value
    }

    func url(for relativePath: String) -> URL {
        rootURL.appending(path: relativePath)
    }
}

@MainActor
struct MediaMomentService {
    let modelContext: ModelContext
    let fileStore: MediaFileStore
    let photoLibrary: any MediaPhotoLibraryWriting

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.fileStore = MediaFileStore()
        self.photoLibrary = SystemMediaPhotoLibrary()
    }

    init(
        modelContext: ModelContext,
        fileStore: MediaFileStore,
        photoLibrary: any MediaPhotoLibraryWriting
    ) {
        self.modelContext = modelContext
        self.fileStore = fileStore
        self.photoLibrary = photoLibrary
    }

    @discardableResult
    func saveCapture(
        id: UUID = UUID(),
        sourceURL: URL,
        kind: MediaKind,
        capturedAt: Date,
        thumbnailData: Data,
        durationSeconds: Double = 0,
        preference: MediaStoragePreference,
        autoLink: Bool = true
    ) async throws -> MediaMoment {
        let fileExtension = preferredExtension(sourceURL: sourceURL, kind: kind)
        let pendingRelativePath = try await fileStore.stage(
            originalAt: sourceURL,
            id: id,
            fileExtension: fileExtension
        )
        let moment = MediaMoment(
            id: id,
            kind: kind,
            capturedAt: capturedAt,
            requestedStorage: preference,
            pendingRelativePath: pendingRelativePath,
            sourceTemporaryPath: sourceURL.path,
            thumbnailData: thumbnailData,
            durationSeconds: durationSeconds
        )
        modelContext.insert(moment)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(moment)
            await fileStore.delete(relativePath: pendingRelativePath)
            throw error
        }
        if autoLink {
            _ = try? MediaLinkingService(modelContext: modelContext).tryAutoLink(moment)
        }
        await completeDestinations(for: moment)
        return moment
    }

    func retry(_ moment: MediaMoment) async {
        moment.status = MediaMomentStatus.pending.rawValue
        moment.lastError = nil
        moment.updatedAt = Date()
        try? modelContext.save()
        await completeDestinations(for: moment)
    }

    func saveToAppInstead(_ moment: MediaMoment) async {
        moment.requestedStorage = MediaStoragePreference.app.rawValue
        await retry(moment)
    }

    func refreshOriginalAvailability(_ moment: MediaMoment) async {
        if await fileStore.exists(relativePath: moment.appRelativePath) {
            setAvailability(.available, for: moment)
            return
        }
        if let identifier = moment.photosAssetIdentifier,
           await photoLibrary.assetExists(identifier: identifier) {
            setAvailability(.available, for: moment)
        } else {
            setAvailability(.unavailable, for: moment)
        }
    }

    func deleteRecord(_ moment: MediaMoment) async {
        await fileStore.delete(relativePath: moment.appRelativePath)
        await fileStore.delete(relativePath: moment.pendingRelativePath)
        await fileStore.delete(absolutePath: moment.sourceTemporaryPath)
        try? ThoughtMediaLinkService(modelContext: modelContext).removeLinks(for: moment)
        modelContext.delete(moment)
        try? modelContext.save()
    }

    func recoverableURL(for moment: MediaMoment) async -> URL? {
        if let appPath = moment.appRelativePath,
           await fileStore.exists(relativePath: appPath) {
            return fileStore.url(for: appPath)
        }
        if let pendingPath = moment.pendingRelativePath,
           await fileStore.exists(relativePath: pendingPath) {
            return fileStore.url(for: pendingPath)
        }
        if let sourceTemporaryPath = moment.sourceTemporaryPath,
           FileManager.default.fileExists(atPath: sourceTemporaryPath) {
            return URL(filePath: sourceTemporaryPath)
        }
        return nil
    }

    private func completeDestinations(for moment: MediaMoment) async {
        guard let sourceURL = await recoverableURL(for: moment) else {
            mark(moment, status: .failed, errors: [MediaMomentServiceError.missingRecoverableOriginal])
            return
        }

        let preference = moment.storagePreference
        let needsApp = preference == .app || preference == .both
        let needsPhotos = preference == .photosLibrary || preference == .both
        var appSucceeded = moment.appRelativePath != nil
        var photosSucceeded = moment.photosAssetIdentifier != nil
        var errors: [Error] = []
        let fileExtension = preferredExtension(sourceURL: sourceURL, kind: moment.kind)

        if needsApp && !appSucceeded {
            do {
                moment.appRelativePath = try await fileStore.copyToApp(
                    sourceURL: sourceURL,
                    id: moment.id,
                    fileExtension: fileExtension
                )
                appSucceeded = true
            } catch {
                errors.append(error)
            }
        }

        if needsPhotos && !photosSucceeded {
            do {
                moment.photosAssetIdentifier = try await photoLibrary.saveOriginal(
                    at: sourceURL,
                    kind: moment.kind
                )
                photosSucceeded = true
            } catch {
                errors.append(error)
            }
        }

        let status: MediaMomentStatus
        switch preference {
        case .app:
            status = appSucceeded ? .saved : .failed
        case .photosLibrary:
            status = photosSucceeded ? .saved : .failed
        case .both:
            if appSucceeded && photosSucceeded {
                status = .saved
            } else if appSucceeded || photosSucceeded {
                status = .partial
            } else {
                status = .failed
            }
        }

        updateStoredLocation(moment, appSucceeded: appSucceeded, photosSucceeded: photosSucceeded)
        mark(moment, status: status, errors: errors)
        if status == .saved {
            await fileStore.delete(relativePath: moment.pendingRelativePath)
            await fileStore.delete(absolutePath: moment.sourceTemporaryPath)
            moment.pendingRelativePath = nil
            moment.sourceTemporaryPath = nil
            try? modelContext.save()
        }
    }

    private func updateStoredLocation(
        _ moment: MediaMoment,
        appSucceeded: Bool,
        photosSucceeded: Bool
    ) {
        let location: MediaStoredLocation
        switch (appSucceeded, photosSucceeded) {
        case (true, true):
            location = .both
        case (true, false):
            location = .app
        case (false, true):
            location = .photosLibrary
        case (false, false):
            location = .none
        }
        moment.storedLocation = location.rawValue
    }

    private func mark(_ moment: MediaMoment, status: MediaMomentStatus, errors: [Error]) {
        moment.status = status.rawValue
        moment.lastError = errors.isEmpty
            ? nil
            : errors.map(\.localizedDescription).joined(separator: "\n")
        moment.originalAvailability = status == .failed
            ? MediaOriginalAvailability.unknown.rawValue
            : MediaOriginalAvailability.available.rawValue
        moment.updatedAt = Date()
        try? modelContext.save()
    }

    private func setAvailability(_ availability: MediaOriginalAvailability, for moment: MediaMoment) {
        guard moment.originalAvailability != availability.rawValue else { return }
        moment.originalAvailability = availability.rawValue
        moment.updatedAt = Date()
        try? modelContext.save()
    }

    private func preferredExtension(sourceURL: URL, kind: MediaKind) -> String {
        let value = sourceURL.pathExtension
        if !value.isEmpty {
            return value.lowercased()
        }
        return kind == .photo ? "jpg" : "mov"
    }
}
