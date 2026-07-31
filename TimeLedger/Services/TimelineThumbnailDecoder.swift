import Foundation
import ImageIO

/// Decodes a display-sized image from an immutable thumbnail data snapshot.
/// Callers choose when to run this work off the main actor; this module never
/// receives SwiftData-managed objects or performs storage writes.
nonisolated enum TimelineThumbnailDecoder {
    /// Produces enough pixels to fill `targetPixelSize` without decoding the
    /// source thumbnail at its original size. Invalid data or an invalid target
    /// produces `nil`.
    static func decode(data: Data, targetPixelSize: CGSize) -> CGImage? {
        guard targetPixelSize.width > 0, targetPixelSize.height > 0,
              let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let maximumPixelSize = maximumPixelSize(
                for: source,
                targetPixelSize: targetPixelSize
              ),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
              ) else {
            return nil
        }

        return cgImage
    }

    private static func maximumPixelSize(
        for source: CGImageSource,
        targetPixelSize: CGSize
    ) -> Int? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let rawHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              rawWidth.doubleValue > 0,
              rawHeight.doubleValue > 0 else {
            return nil
        }

        var sourceWidth = CGFloat(rawWidth.doubleValue)
        var sourceHeight = CGFloat(rawHeight.doubleValue)
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if [5, 6, 7, 8].contains(orientation) {
            swap(&sourceWidth, &sourceHeight)
        }

        let scale = max(
            targetPixelSize.width / sourceWidth,
            targetPixelSize.height / sourceHeight
        )
        return max(1, Int((max(sourceWidth, sourceHeight) * scale).rounded(.up)))
    }
}
