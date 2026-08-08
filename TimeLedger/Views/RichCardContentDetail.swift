import SwiftData
import SwiftUI

struct ThoughtDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [TimeEntry]
    @Query private var journalLinks: [JournalTimeLink]
    @State private var showingEditor = false

    let journal: JournalEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let linkedEntry {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("关联时间记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(linkedEntry.projectNameSnapshot)
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("thought.detail.linkedEntry")
                }

                RichCardContentView(
                    target: .journal(journal),
                    mode: .readOnly
                )
                .frame(minHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: TLTheme.cardRadius))
            }
            .padding(16)
        }
        .background(TLTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("随记详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: journal.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(journal.isFavorite ? Color.yellow : .secondary)
                }
                .accessibilityLabel(journal.isFavorite ? "取消收藏随记" : "收藏随记")
                .accessibilityIdentifier("thought.detail.favorite")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") {
                    showingEditor = true
                }
                .accessibilityIdentifier("thought.detail.edit")
            }
        }
        .sheet(isPresented: $showingEditor) {
            RichCardContentEditorSheet(target: .journal(journal), title: "编辑随记")
        }
    }

    private func toggleFavorite() {
        do {
            try JournalContentService(modelContext: modelContext).setFavorite(journal, !journal.isFavorite)
        } catch {
            return
        }
    }

    private var linkedEntry: TimeEntry? {
        guard let link = journalLinks.first(where: { $0.journalEntryID == journal.id }) else {
            return nil
        }
        return allEntries.first { $0.id == link.timeEntryID }
    }
}

struct TimeEntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allJournals: [JournalEntry]
    @Query private var allDocuments: [ContentDocument]
    @Query private var journalLinks: [JournalTimeLink]
    @Query private var allActionCompletions: [ActionCompletion]

    let entry: TimeEntry

    @State private var showingRecordEditor = false
    @State private var showingAddThought = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metadata

                RichCardContentView(
                    target: .timeEntry(entry),
                    mode: .readOnly
                )
                .frame(minHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: TLTheme.cardRadius))

                if !linkedJournals.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("关联随记")
                            .font(.headline)

                        ForEach(linkedJournals) { journal in
                            HStack(spacing: 8) {
                                NavigationLink {
                                    ThoughtDetailView(journal: journal)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(DateFormatterFactory.timeOnly.string(from: journal.capturedAt))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        let body = journalBody(journal)
                                        Text(body.isEmpty ? "暂无文字内容" : body)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .lineLimit(3)
                                    }
                                    .padding(12)
                                    .background(
                                        TLTheme.cardBackground,
                                        in: RoundedRectangle(cornerRadius: TLTheme.cardRadius)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("entry.detail.thought")

                                Button {
                                    toggleFavorite(journal)
                                } label: {
                                    Image(systemName: journal.isFavorite ? "star.fill" : "star")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(journal.isFavorite ? Color.yellow : .secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(journal.isFavorite ? "取消收藏随记" : "收藏随记")
                                .accessibilityIdentifier("entry.detail.thought.favorite")
                            }
                        }
                    }
                }

                Button {
                    showingAddThought = true
                } label: {
                    Label("添加随记", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                if !linkedActionCompletions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("完成事项")
                            .font(.headline)

                        ForEach(linkedActionCompletions) { completion in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(completion.actionTitleSnapshot)
                                Text(DateFormatterFactory.timeOnly.string(from: completion.completedAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .accessibilityIdentifier("entry.actions")
                }
            }
            .padding(16)
        }
        .background(TLTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") {
                    showingRecordEditor = true
                }
                .accessibilityIdentifier("entry.detail.edit")
            }
        }
        .sheet(isPresented: $showingRecordEditor) {
            NavigationStack {
                TimeEntryEditView(entry: entry)
            }
        }
        .sheet(isPresented: $showingAddThought) {
            NavigationStack {
                ThoughtComposerSheet(targetEntry: entry)
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.projectNameSnapshot)
                .font(.title3.weight(.semibold))
            Text(timeRangeText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(entry.status == TimeEntryStatus.draft.rawValue ? "待确认" : "已确认")
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    entry.status == TimeEntryStatus.draft.rawValue
                        ? Color.secondary
                        : Color.accentColor
                )
        }
        .accessibilityIdentifier("entry.detail.metadata")
    }

    private var timeRangeText: String {
        let start = DateFormatterFactory.dateTime.string(from: entry.startAt)
        let end = DateFormatterFactory.dateTime.string(from: entry.endAt)
        return start + " – " + end
    }

    private var linkedJournals: [JournalEntry] {
        let ids = Set(journalLinks.filter { $0.timeEntryID == entry.id }.map(\.journalEntryID))
        return allJournals
            .filter { ids.contains($0.id) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private func journalBody(_ journal: JournalEntry) -> String {
        allDocuments.first {
            $0.ownerID == journal.id && $0.ownerKindEnum == .journalEntry
        }?.body ?? ""
    }

    private func toggleFavorite(_ journal: JournalEntry) {
        do {
            try JournalContentService(modelContext: modelContext).setFavorite(journal, !journal.isFavorite)
        } catch {
            return
        }
    }

    private var linkedActionCompletions: [ActionCompletion] {
        allActionCompletions
            .filter { $0.linkedEntryId == entry.id }
            .sorted { $0.completedAt < $1.completedAt }
    }
}

struct RichCardContentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [TimeEntry]
    @Query private var journalLinks: [JournalTimeLink]
    @Query private var journals: [JournalEntry]

    let target: RichCardContentTarget
    let title: String

    @State private var session: ContentEditorSession?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isFavorite: Bool
    @State private var pendingNewJournalFavorite = false

    init(target: RichCardContentTarget, title: String) {
        self.target = target
        self.title = title
        if case .journal(let journal) = target {
            _isFavorite = State(initialValue: journal.isFavorite)
        } else {
            _isFavorite = State(initialValue: false)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let journalTarget,
                       let link = journalLinks.first(where: { $0.journalEntryID == journalTarget.id }),
                       let linkedEntry = entries.first(where: { $0.id == link.timeEntryID }) {
                        LabeledContent(
                            "关联时间记录",
                            value: "\(linkedEntry.projectNameSnapshot) · \(DateFormatterFactory.timeOnly.string(from: linkedEntry.startAt))–\(DateFormatterFactory.timeOnly.string(from: linkedEntry.endAt))"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .accessibilityIdentifier("thought.edit.linkedEntry")
                    }

                    RichCardContentView(
                        target: target,
                        mode: .edit,
                        onSessionReady: { session = $0 }
                    )
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }
            .background(TLTheme.pageBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        cancel()
                    }
                    .accessibilityIdentifier("richContent.cancel")
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if showsFavoriteToggle {
                        favoriteToggleButton
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .accessibilityIdentifier(saveAccessibilityIdentifier)
                    .disabled(isSaving || session?.hasContent != true)
                }
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var saveAccessibilityIdentifier: String {
        switch target {
        case .journal:
            return "thought.edit.save"
        case .newJournal:
            return "thought.composer.save"
        case .timeEntry:
            return "timeEntry.edit.save"
        case .newTimeEntry:
            return "richContent.save"
        }
    }

    private var journalTarget: JournalEntry? {
        if case .journal(let journal) = target {
            return journal
        }
        return nil
    }

    private var showsFavoriteToggle: Bool {
        switch target {
        case .journal, .newJournal: true
        case .timeEntry, .newTimeEntry: false
        }
    }

    private var favoriteToggleButton: some View {
        Button {
            toggleFavorite()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? Color.yellow : .secondary)
        }
        .accessibilityLabel(isFavorite ? "取消收藏随记" : "收藏随记")
        .accessibilityIdentifier("thought.favorite.toggle")
    }

    private func toggleFavorite() {
        switch target {
        case .journal(let journal):
            isFavorite.toggle()
            do {
                try JournalContentService(modelContext: modelContext).setFavorite(journal, isFavorite)
            } catch {
                isFavorite.toggle()
                errorMessage = error.localizedDescription
            }
        case .newJournal:
            isFavorite.toggle()
            pendingNewJournalFavorite = isFavorite
        case .timeEntry, .newTimeEntry:
            break
        }
    }

    private func applyPendingFavoriteToNewJournal() {
        guard pendingNewJournalFavorite,
              let ownerID = session?.ownerID,
              let journal = journals.first(where: { $0.id == ownerID }) else { return }
        do {
            try JournalContentService(modelContext: modelContext).setFavorite(journal, true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel() {
        Task {
            do {
                try await session?.cancel()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        guard let session, !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await session.save()
                applyPendingFavoriteToNewJournal()
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
