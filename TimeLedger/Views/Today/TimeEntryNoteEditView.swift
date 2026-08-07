import SwiftUI

struct TimeEntryNoteEditView: View {
    var body: some View {
        ContentUnavailableView(
            "请从记录编辑页修改内容",
            systemImage: "square.and.pencil",
            description: Text("文字、照片和视频共用同一个编辑入口。")
        )
    }
}
