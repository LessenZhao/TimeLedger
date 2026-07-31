import Testing
import UIKit
@testable import TimeLedger

@MainActor
struct TimelineThumbnailDecoderTests {
    @Test func downsampledImageFillsTheTimelineCardPixelSize() throws {
        let data = try solidJPEGData(color: .red, pixelSize: CGSize(width: 1_200, height: 900))

        let cgImage = try #require(
            TimelineThumbnailDecoder.decode(data: data, targetPixelSize: CGSize(width: 312, height: 234))
        )

        #expect(cgImage.width == 312)
        #expect(cgImage.height == 234)
    }

    @Test func invalidDataReturnsNilWithoutCrashing() {
        #expect(
            TimelineThumbnailDecoder.decode(
                data: Data("not-an-image".utf8),
                targetPixelSize: CGSize(width: 312, height: 234)
            ) == nil
        )
    }

    @Test func concurrentDecodesKeepEachImageWithItsOwnRequest() async throws {
        let redData = try solidJPEGData(color: .red, pixelSize: CGSize(width: 1_200, height: 900))
        let blueData = try solidJPEGData(color: .blue, pixelSize: CGSize(width: 1_200, height: 900))
        let requests = (0..<40).map { index in
            ThumbnailRequest(
                expected: index.isMultiple(of: 2) ? .red : .blue,
                data: index.isMultiple(of: 2) ? redData : blueData
            )
        }

        let results = await withTaskGroup(of: ThumbnailResult.self) { group in
            for request in requests {
                group.addTask {
                    let image = TimelineThumbnailDecoder.decode(
                        data: request.data,
                        targetPixelSize: CGSize(width: 312, height: 234)
                    )
                    return ThumbnailResult(
                        expected: request.expected,
                        sample: image.flatMap(sampleColor)
                    )
                }
            }

            var results: [ThumbnailResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        #expect(results.count == requests.count)
        for result in results {
            let sample = try #require(result.sample)
            switch result.expected {
            case .red:
                #expect(sample.red > 200)
                #expect(sample.green < 80)
                #expect(sample.blue < 80)
            case .blue:
                #expect(sample.red < 80)
                #expect(sample.green < 80)
                #expect(sample.blue > 160)
            }
        }
    }

    @Test func decodeDoesNotMutateTheInputData() throws {
        let data = try solidJPEGData(color: .green, pixelSize: CGSize(width: 1_200, height: 900))
        let original = data

        _ = TimelineThumbnailDecoder.decode(
            data: data,
            targetPixelSize: CGSize(width: 312, height: 234)
        )

        #expect(data == original)
    }
}

private struct ThumbnailRequest: Sendable {
    let expected: ExpectedThumbnailColor
    let data: Data
}

private struct ThumbnailResult: Sendable {
    let expected: ExpectedThumbnailColor
    let sample: ThumbnailColorSample?
}

private enum ExpectedThumbnailColor: Sendable {
    case red
    case blue
}

private struct ThumbnailColorSample: Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}

@MainActor
private func solidJPEGData(color: UIColor, pixelSize: CGSize) throws -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
        color.setFill()
        UIRectFill(CGRect(origin: .zero, size: pixelSize))
    }
    return try #require(image.jpegData(compressionQuality: 0.9))
}

private func sampleColor(_ cgImage: CGImage) -> ThumbnailColorSample? {
    var pixel = [UInt8](repeating: 0, count: 4)
    guard let context = CGContext(
        data: &pixel,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        return nil
    }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return ThumbnailColorSample(red: pixel[0], green: pixel[1], blue: pixel[2])
}
