import SwiftUI
import SwiftData

struct ThoughtComposerSheet: View {
    let focusTextOnAppear: Bool
    let targetEntry: TimeEntry?

    init(
        focusTextOnAppear: Bool = true,
        targetEntry: TimeEntry? = nil
    ) {
        self.focusTextOnAppear = focusTextOnAppear
        self.targetEntry = targetEntry
    }

    var body: some View {
        RichCardContentEditorSheet(
            target: .newJournal(entry: targetEntry),
            title: "记录随记"
        )
    }
}

#Preview {
    ThoughtComposerSheet()
        .modelContainer(previewModelContainer)
}
