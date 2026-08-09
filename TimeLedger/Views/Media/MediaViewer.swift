import AVFoundation
import AVKit
import Photos
import SwiftData
import SwiftUI
import UIKit

struct MediaViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let moment: MediaMoment

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
           if let image {
                    ZoomableImageView(image: image)
                        .ignoresSafeArea()
              } else if let player {
                    VideoPlayer(player: player)
                        .background(Color.black)
                        .onAppear { player.play() }
                        .onDisappear { player.pause() }
                } else if isLoading {
                    ProgressView("正在读取原件…")
                } else {
                    ContentUnavailableView(
                        "原件不可用",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage ?? "时间点和缩略图仍保留。")
                    )
                }
            }
            .navigationTitle(moment.kind == .photo ? "照片" : "视频")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task {
            await loadOriginal()
        }
    }

    private func loadOriginal() async {
        let service = MediaMomentService(modelContext: modelContext)
        await service.refreshOriginalAvailability(moment)

        if let appPath = moment.appRelativePath,
           await service.fileStore.exists(relativePath: appPath) {
            let url = service.fileStore.url(for: appPath)
            switch moment.kind {
            case .photo:
                image = await Task.detached(priority: .userInitiated) {
                    UIImage(contentsOfFile: url.path)
                }.value
            case .video:
                player = AVPlayer(url: url)
            }
        } else if let identifier = moment.photosAssetIdentifier {
            switch moment.kind {
            case .photo:
                image = await PhotoKitMediaLoader.image(identifier: identifier)
            case .video:
                player = await PhotoKitMediaLoader.player(identifier: identifier)
            }
        }

        isLoading = false
        if image == nil && player == nil {
            errorMessage = "系统相册中的原件可能已被删除，或 App 文件已不可用。"
            await service.refreshOriginalAvailability(moment)
        }
    }
}

enum MediaViewerLayout {
    static func fittedSize(imageSize: CGSize, viewportSize: CGSize) -> CGSize {
        guard imageSize.width > 0,
              imageSize.height > 0,
              viewportSize.width > 0,
              viewportSize.height > 0 else {
            return .zero
        }

        let scale = min(
            viewportSize.width / imageSize.width,
            viewportSize.height / imageSize.height
        )
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }
}

private enum PhotoKitMediaLoader {
    static func image(identifier: String) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    static func player(identifier: String) async -> AVPlayer? {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestPlayerItem(
                forVideo: asset,
                options: options
            ) { playerItem, _ in
                continuation.resume(returning: playerItem.map(AVPlayer.init(playerItem:)))
            }
        }
    }
}
