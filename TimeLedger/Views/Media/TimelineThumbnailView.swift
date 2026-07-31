import SwiftUI
import UIKit

/// Identifies a cached timeline thumbnail. `MediaMoment.thumbnailData` is
/// immutable after creation, so the record UUID plus requested pixel size is
/// the complete display identity.
nonisolated struct TimelineThumbnailKey: Hashable, Sendable {
    let mediaID: UUID
    let pixelWidth: Int
    let pixelHeight: Int

    init(mediaID: UUID, targetPixelSize: CGSize) {
        self.mediaID = mediaID
        pixelWidth = max(1, Int(targetPixelSize.width.rounded(.up)))
        pixelHeight = max(1, Int(targetPixelSize.height.rounded(.up)))
    }

    var targetPixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }
}

/// Main-actor cache for already decoded display images. Its decode task uses
/// only a `Data` snapshot and is cancelled when the requesting card leaves the
/// screen before the result is needed.
@MainActor
final class TimelineThumbnailCache {
    static let shared = TimelineThumbnailCache()

    private let maximumCount: Int
    private let maximumCost: Int
    private var images: [TimelineThumbnailKey: UIImage] = [:]
    private var costs: [TimelineThumbnailKey: Int] = [:]
    private var recency: [TimelineThumbnailKey] = []
    private var totalCost = 0

    init(maximumCount: Int = 80, maximumCost: Int = 32 * 1024 * 1024) {
        self.maximumCount = maximumCount
        self.maximumCost = maximumCost
    }

    func image(for key: TimelineThumbnailKey, data: Data) async -> UIImage? {
        if let image = cachedImage(for: key) {
            return image
        }

        let dataSnapshot = Data(data)
        let decodeTask: Task<CGImage?, Never> = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return nil }
            return TimelineThumbnailDecoder.decode(
                data: dataSnapshot,
                targetPixelSize: key.targetPixelSize
            )
        }

        return await withTaskCancellationHandler {
            guard let cgImage = await decodeTask.value, !Task.isCancelled else {
                return nil
            }
            let image = UIImage(cgImage: cgImage)
            insert(image, for: key)
            return image
        } onCancel: {
            decodeTask.cancel()
        }
    }

    func cachedImage(for key: TimelineThumbnailKey) -> UIImage? {
        guard let image = images[key] else { return nil }
        touch(key)
        return image
    }

    func insert(_ image: UIImage, for key: TimelineThumbnailKey) {
        if let existingCost = costs[key] {
            totalCost -= existingCost
            recency.removeAll { $0 == key }
        }

        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        images[key] = image
        costs[key] = cost
        totalCost += cost
        recency.append(key)
        evictIfNeeded()
    }

    private func touch(_ key: TimelineThumbnailKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func evictIfNeeded() {
        while images.count > maximumCount || totalCost > maximumCost {
            guard let leastRecentlyUsed = recency.first else { return }
            recency.removeFirst()
            totalCost -= costs.removeValue(forKey: leastRecentlyUsed) ?? 0
            images.removeValue(forKey: leastRecentlyUsed)
        }
    }
}

struct TimelineThumbnailView: View {
    let mediaID: UUID
    let thumbnailData: Data
    let kind: MediaKind
    let size: CGSize

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: kind == .photo ? "photo" : "video")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: key) {
            image = nil
            let loadedImage = await TimelineThumbnailCache.shared.image(
                for: key,
                data: thumbnailData
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }

    private var key: TimelineThumbnailKey {
        TimelineThumbnailKey(
            mediaID: mediaID,
            targetPixelSize: CGSize(
                width: size.width * displayScale,
                height: size.height * displayScale
            )
        )
    }
}
