import SwiftUI

struct CameraBoundaryFixtureView: View {
    @Environment(\.dismiss) private var dismiss

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
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
