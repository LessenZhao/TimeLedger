import EvolutionCore
import EvolutionHubCore
import SwiftUI

enum ReadingNoteNavigationTarget: Sendable, Hashable {
    case conversation(conversationID: String)
    case formalAsset(assetID: String)
}

/// Unified reading-notes library with jump-back into source or formal surfaces.
struct ChatReadingNotesLibraryView: View {
    @ObservedObject var store: ChatConversationHubStore
    var onNavigate: (ReadingNoteNavigationTarget) -> Void

    @State private var query = ""
    @State private var scope: Scope = .all

    private enum Scope: String, CaseIterable, Identifiable {
        case all = "全部"
        case source = "原文"
        case formal = "正式库"
        var id: Self { self }
    }

    private var filtered: [ReadingNote] {
        store.allNotes.filter { note in
            switch scope {
            case .all:
                break
            case .source:
                if case .sourceMessageSpan = note.anchor { break } else { return false }
            case .formal:
                if case .formalAssetSpan = note.anchor { break } else { return false }
            }
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return true }
            let hay = [
                note.quoteSnapshot,
                note.body ?? "",
                title(for: note),
            ].joined(separator: "\n")
            return hay.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("范围", selection: $scope) {
                    ForEach(Scope.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                TextField("搜索摘录或笔记", text: $query)
                    .textFieldStyle(.roundedBorder)
                Spacer(minLength: 0)
                Text("\(filtered.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if filtered.isEmpty {
                ContentUnavailableView(
                    "还没有阅读笔记",
                    systemImage: "note.text",
                    description: Text("在会话原文或正式库正文中划线/写笔记后，会集中出现在这里。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                List(filtered) { note in
                    Button {
                        navigate(note)
                    } label: {
                        noteRow(note)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("删除笔记", role: .destructive) {
                            store.deleteReadingNote(id: note.id)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func noteRow(_ note: ReadingNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(badge(for: note))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                Text(title(for: note))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(note.updatedAt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(note.quoteSnapshot)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if let body = note.body, !body.isEmpty {
                Text(body)
                    .font(.body)
                    .lineLimit(4)
            } else if note.isHighlight {
                Text("划线")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func badge(for note: ReadingNote) -> String {
        switch note.anchor {
        case .sourceMessageSpan:
            return "原文"
        case .formalAssetSpan:
            return "正式"
        }
    }

    private func title(for note: ReadingNote) -> String {
        switch note.anchor {
        case .sourceMessageSpan(let span):
            return store.conversationTitle(for: span.conversationId)
        case .formalAssetSpan(let span):
            return store.asset(id: span.assetId)?.title ?? span.assetId
        }
    }

    private func navigate(_ note: ReadingNote) {
        switch note.anchor {
        case .sourceMessageSpan(let span):
            onNavigate(.conversation(conversationID: span.conversationId))
        case .formalAssetSpan(let span):
            onNavigate(.formalAsset(assetID: span.assetId))
        }
    }
}
