import AVFoundation
import UIKit

enum CameraAccessResult {
    case ready
    case unavailable
    case cameraDenied
    case microphoneDenied

    var message: String {
        switch self {
        case .ready:
            ""
        case .unavailable:
            "此设备没有可用的系统相机。"
        case .cameraDenied:
            "相机权限未开启，无法拍照或录像。请在系统设置中允许 TimeLedger 使用相机。"
        case .microphoneDenied:
            "麦克风权限未开启，无法可靠录制视频声音。请在系统设置中允许 TimeLedger 使用麦克风。"
        }
    }

    var offersSettings: Bool {
        self == .cameraDenied || self == .microphoneDenied
    }
}

struct CameraPermissionService {
    func prepareForCamera() async -> CameraAccessResult {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .unavailable
        }

        guard await authorization(for: .video) else {
            return .cameraDenied
        }
        guard await authorization(for: .audio) else {
            return .microphoneDenied
        }
        return .ready
    }

    private func authorization(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }
}
