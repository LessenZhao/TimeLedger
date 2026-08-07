import SwiftData
import SwiftUI

struct MediaManualLinkView: View {
    @Environment(\.dismiss) private var dismiss

    let moment: MediaMoment

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "请编辑随记",
                systemImage: "square.and.pencil",
                description: Text("媒体归属和时间关联只在统一随记编辑器中修改。")
            )
            .navigationTitle("媒体关联")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
