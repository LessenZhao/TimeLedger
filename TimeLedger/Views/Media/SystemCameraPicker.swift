import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum SystemCameraConfiguration {
    static let mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
    static let videoMaximumDuration: TimeInterval = 60
    static let videoQuality: UIImagePickerController.QualityType = .typeHigh
}

nonisolated struct CameraCapture: Sendable {
    let sourceURL: URL
    let kind: MediaKind
    let capturedAt: Date
    let thumbnailData: Data
    let durationSeconds: Double
}

struct SystemCameraPicker: UIViewControllerRepresentable {
    let mediaTypes: [String]
    let completion: (Result<CameraCapture, Error>?) -> Void

    init(
        mediaTypes: [String] = SystemCameraConfiguration.mediaTypes,
        completion: @escaping (Result<CameraCapture, Error>?) -> Void
    ) {
        self.mediaTypes = mediaTypes
        self.completion = completion
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = mediaTypes
        picker.videoMaximumDuration = SystemCameraConfiguration.videoMaximumDuration
        picker.videoQuality = SystemCameraConfiguration.videoQuality
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (Result<CameraCapture, Error>?) -> Void

        init(completion: @escaping (Result<CameraCapture, Error>?) -> Void) {
            self.completion = completion
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            Task {
                do {
                    let capture = try await MediaCapturePreparation.prepare(info: info)
                    completion(.success(capture))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
}

enum MediaCapturePreparation {
    enum PreparationError: LocalizedError {
        case missingCapture
        case invalidImage
        case invalidVideo

        var errorDescription: String? {
            switch self {
            case .missingCapture:
                "系统相机没有返回照片或视频。"
            case .invalidImage:
                "无法读取刚拍摄的照片。"
            case .invalidVideo:
                "无法读取刚拍摄的视频。"
            }
        }
    }

    static func prepare(
        info: [UIImagePickerController.InfoKey: Any]
    ) async throws -> CameraCapture {
        let mediaType = info[.mediaType] as? String
        if mediaType == UTType.image.identifier,
           let image = info[.originalImage] as? UIImage {
            return try await preparePhoto(image)
        }
        if mediaType == UTType.movie.identifier,
           let movieURL = info[.mediaURL] as? URL {
            return try await prepareVideo(at: movieURL)
        }
        throw PreparationError.missingCapture
    }

    private static func preparePhoto(_ image: UIImage) async throws -> CameraCapture {
        try await Task.detached(priority: .userInitiated) {
            guard let originalData = image.jpegData(compressionQuality: 0.96),
                  let thumbnailData = MediaThumbnailFactory.thumbnailData(for: image) else {
                throw PreparationError.invalidImage
            }
            let url = FileManager.default.temporaryDirectory
                .appending(path: "TimeLedger-Capture-\(UUID().uuidString).jpg")
            try originalData.write(to: url, options: .atomic)
            return CameraCapture(
                sourceURL: url,
                kind: .photo,
                capturedAt: Date(),
                thumbnailData: thumbnailData,
                durationSeconds: 0
            )
        }.value
    }

    static func prepareVideo(
        at movieURL: URL,
        capturedAt: Date = Date()
    ) async throws -> CameraCapture {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: movieURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)
            let cgImage = try await generator.image(at: .zero).image
            let image = UIImage(cgImage: cgImage)
            guard let thumbnailData = MediaThumbnailFactory.thumbnailData(for: image) else {
                throw PreparationError.invalidVideo
            }
            let durationTime = try await asset.load(.duration)
            let duration = max(0, CMTimeGetSeconds(durationTime))
            return CameraCapture(
                sourceURL: movieURL,
                kind: .video,
                capturedAt: capturedAt,
                thumbnailData: thumbnailData,
                durationSeconds: duration.isFinite ? duration : 0
            )
        }.value
    }

}

nonisolated enum MediaThumbnailFactory {
    static func thumbnailData(for image: UIImage) -> Data? {
        let maximum: CGFloat = 360
        let ratio = min(maximum / max(image.size.width, 1), maximum / max(image.size.height, 1), 1)
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: size)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.72)
    }
}
