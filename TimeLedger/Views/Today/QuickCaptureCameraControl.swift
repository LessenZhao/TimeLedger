import SwiftUI
import UIKit

struct QuickCaptureCameraControl: View {
    let tapAction: () -> Void
    let cameraAction: () -> Void

    var body: some View {
        Image(systemName: "lightbulb.fill")
            .font(.system(size: TLTheme.statusIconSize, weight: .medium))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.2, maximumDistance: 24)
                    .exclusively(before: TapGesture())
                    .onEnded { result in
                        switch result {
                        case .first:
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            cameraAction()
                        case .second:
                            tapAction()
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("快速想法")
            .accessibilityHint("轻点记录想法，按住打开相机")
            .accessibilityIdentifier("today.quickThoughtCamera")
            .accessibilityAction {
                tapAction()
            }
            .accessibilityAction(named: Text("打开相机")) {
                cameraAction()
            }
    }
}
