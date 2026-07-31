import Testing
import UIKit
@testable import TimeLedger

@MainActor
struct TimelineThumbnailCacheTests {
    @Test func cacheKeySeparatesTheSameMediaAtDifferentPixelSizes() {
        let cache = TimelineThumbnailCache(maximumCount: 2, maximumCost: .max)
        let mediaID = UUID()
        let small = TimelineThumbnailKey(mediaID: mediaID, targetPixelSize: CGSize(width: 276, height: 216))
        let large = TimelineThumbnailKey(mediaID: mediaID, targetPixelSize: CGSize(width: 312, height: 234))
        let image = testImage(color: .red)

        cache.insert(image, for: small)

        #expect(cache.cachedImage(for: small) === image)
        #expect(cache.cachedImage(for: large) == nil)
    }

    @Test func cacheEvictsTheLeastRecentlyUsedImageAtItsCountLimit() {
        let cache = TimelineThumbnailCache(maximumCount: 2, maximumCost: .max)
        let first = TimelineThumbnailKey(mediaID: UUID(), targetPixelSize: CGSize(width: 312, height: 234))
        let second = TimelineThumbnailKey(mediaID: UUID(), targetPixelSize: CGSize(width: 312, height: 234))
        let third = TimelineThumbnailKey(mediaID: UUID(), targetPixelSize: CGSize(width: 312, height: 234))
        let firstImage = testImage(color: .red)
        let secondImage = testImage(color: .green)
        let thirdImage = testImage(color: .blue)

        cache.insert(firstImage, for: first)
        cache.insert(secondImage, for: second)
        _ = cache.cachedImage(for: first)
        cache.insert(thirdImage, for: third)

        #expect(cache.cachedImage(for: first) === firstImage)
        #expect(cache.cachedImage(for: second) == nil)
        #expect(cache.cachedImage(for: third) === thirdImage)
    }

    private func testImage(color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 12), format: format).image { _ in
            color.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 16, height: 12))
        }
    }
}
