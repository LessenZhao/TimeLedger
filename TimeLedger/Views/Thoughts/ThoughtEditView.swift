import SwiftUI

struct ThoughtEditView: View {
    let journal: JournalEntry
    let entry: TimeEntry?

    init(journal: JournalEntry, entry: TimeEntry? = nil) {
        self.journal = journal
        self.entry = entry
    }

    var body: some View {
        RichCardContentView(
            target: .journal(journal),
            mode: .edit
        )
    }
}
