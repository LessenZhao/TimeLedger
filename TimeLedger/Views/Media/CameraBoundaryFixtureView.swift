import SwiftUI
import UIKit

struct CameraBoundaryFixtureView: View {
    @Environment(\.dismiss) private var dismiss
    let onUsePhoto: ((CameraCapture) -> Void)?

    init(onUsePhoto: ((CameraCapture) -> Void)? = nil) {
        self.onUsePhoto = onUsePhoto
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.largeTitle)
                Text("系统相机边界已调用")
                    .accessibilityIdentifier("camera.fixture.called")
                Text("这是 UI 测试 fixture，不代表真实相机通过。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if onUsePhoto != nil {
                    Button("使用测试照片", action: useTestPhoto)
                        .accessibilityIdentifier("camera.fixture.usePhoto")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func useTestPhoto() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        guard let originalData = image.jpegData(compressionQuality: 0.9),
              let thumbnailData = MediaThumbnailFactory.thumbnailData(for: image) else {
            return
        }
        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "TimeLedger-UICameraFixture-\(UUID().uuidString).jpg")
        do {
            try originalData.write(to: sourceURL, options: .atomic)
            onUsePhoto?(
                CameraCapture(
                    sourceURL: sourceURL,
                    kind: .photo,
                    capturedAt: Date(),
                    thumbnailData: thumbnailData,
                    durationSeconds: 0
                )
            )
        } catch {
            return
        }
    }
}
