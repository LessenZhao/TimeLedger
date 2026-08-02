import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

nonisolated enum PhotoLibraryMediaImportError: LocalizedError {
    case unsupportedMedia
    case invalidPhoto
    case invalidVideo

    var errorDescription: String? {
        switch self {
        case .unsupportedMedia:
            "无法识别所选媒体类型。"
        case .invalidPhoto:
            "无法读取所选照片。"
        case .invalidVideo:
            "无法读取所选视频。"
        }
    }
}

/// `PhotosPickerItem` may hand us a provider-owned temporary file. Copy it
/// before returning so the draft store can stage a recoverable original.
nonisolated struct PhotoLibraryVideoTransfer: Transferable {
    let fileURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let fileExtension = received.file.pathExtension.isEmpty
                ? "mov"
                : received.file.pathExtension.lowercased()
            let destination = FileManager.default.temporaryDirectory
                .appending(path: "TimeLedger-Library-\(UUID().uuidString).\(fileExtension)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(fileURL: destination)
        }
    }
}

@MainActor
enum PhotoLibraryMediaImportService {
    static func add(
        _ item: PhotosPickerItem,
        to draftStore: ThoughtComposerDraftStore,
        capturedAt: Date = Date()
    ) async throws -> ThoughtComposerDraft {
        let contentTypes = item.supportedContentTypes
        if contentTypes.contains(where: { $0.conforms(to: .movie) }) {
            return try await addVideo(
                item,
                to: draftStore,
                capturedAt: capturedAt
            )
        }
        if contentTypes.contains(where: { $0.conforms(to: .image) }) {
            return try await addPhoto(
                item,
                to: draftStore,
                capturedAt: capturedAt
            )
        }
        throw PhotoLibraryMediaImportError.unsupportedMedia
    }

    private static func addPhoto(
        _ item: PhotosPickerItem,
        to draftStore: ThoughtComposerDraftStore,
        capturedAt: Date
    ) async throws -> ThoughtComposerDraft {
        guard let data = try await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let thumbnailData = MediaThumbnailFactory.thumbnailData(for: image) else {
            throw PhotoLibraryMediaImportError.invalidPhoto
        }
        let fileExtension = item.supportedContentTypes
            .first(where: { $0.conforms(to: .image) })?
            .preferredFilenameExtension
            ?? "jpg"
        return try await draftStore.addPhotoData(
            data,
            thumbnailData: thumbnailData,
            fileExtension: fileExtension,
            capturedAt: capturedAt
        )
    }

    private static func addVideo(
        _ item: PhotosPickerItem,
        to draftStore: ThoughtComposerDraftStore,
        capturedAt: Date
    ) async throws -> ThoughtComposerDraft {
        guard let transfer = try await item.loadTransferable(type: PhotoLibraryVideoTransfer.self) else {
            throw PhotoLibraryMediaImportError.invalidVideo
        }
        defer { try? FileManager.default.removeItem(at: transfer.fileURL) }

        let capture = try await MediaCapturePreparation.prepareVideo(
            at: transfer.fileURL,
            capturedAt: capturedAt
        )
        return try await draftStore.addLibraryCapture(capture)
    }
}
