import AppKit
import EvolutionCore
import EvolutionHubCore
import SwiftUI

/// Compatibility wrapper for one formal asset. Conversation sessions use
/// `ObsidianMarkdownReader` directly with every message in one WebView.
struct AnnotatableMarkdownReader: View {
    let source: String
    var notes: [ReadingNote] = []
    var allowsNotes: Bool = false
    var bodyFontSize: CGFloat = 16
    var assetId: String? = nil
    var versionId: String? = nil
    var onHighlight: ((NSRange, String) -> Void)?
    var onSaveNote: ((NSRange, String, String) -> Void)?
    var onUpdateNote: ((ReadingNote, String) -> Void)?
    var onDeleteNote: ((ReadingNote) -> Void)?

    @State private var composer: NoteComposerState?
    @State private var activeNote: ReadingNote?

    var body: some View {
        ObsidianMarkdownReader(
            sections: [
                .init(
                    id: "document",
                    markdown: source,
                    metadata: .init(assetId: assetId, versionId: versionId)
                )
            ],
            notes: notes.map { note in
                let range: NSRange
                switch note.anchor {
                case .sourceMessageSpan(let span):
                    range = NSRange(location: span.locationUTF16, length: span.lengthUTF16)
                case .formalAssetSpan(let span):
                    range = NSRange(location: span.locationUTF16, length: span.lengthUTF16)
                }
                return .init(id: note.id, sectionID: "document", sourceRange: range)
            },
            allowsAnnotations: allowsNotes,
            onSelectionAction: { _, range, quote, action in
                switch action {
                case .note:
                    composer = NoteComposerState(range: range, quote: quote, existingNoteID: nil, existingBody: "")
                case .highlight:
                    onHighlight?(range, quote)
                case .copy:
                    break
                }
            },
            onEditNote: { noteID in
                activeNote = notes.first(where: { $0.id == noteID })
            }
        )
        .sheet(item: $composer) { state in
            NoteComposerSheet(quote: state.quote, initialBody: state.existingBody) { body in
                if let id = state.existingNoteID, let note = notes.first(where: { $0.id == id }) {
                    onUpdateNote?(note, body)
                } else {
                    onSaveNote?(state.range, state.quote, body)
                }
                composer = nil
            } onCancel: {
                composer = nil
            }
        }
        .sheet(item: $activeNote) { note in
            NoteComposerSheet(quote: note.quoteSnapshot, initialBody: note.body ?? "") { body in
                onUpdateNote?(note, body)
                activeNote = nil
            } onCancel: {
                activeNote = nil
            } onDelete: {
                onDeleteNote?(note)
                activeNote = nil
            }
        }
    }
}

// MARK: - Composer

struct NoteComposerState: Identifiable {
    var id: String { "\(range.location):\(range.length):\(existingNoteID ?? "new")" }
    var range: NSRange
    var quote: String
    var existingNoteID: String?
    var existingBody: String
    var sectionID: String? = nil
}

struct NoteComposerSheet: View {
    let quote: String
    let initialBody: String
    var onSave: (String) -> Void
    var onCancel: () -> Void
    var onDelete: (() -> Void)? = nil
    @State private var bodyText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("写笔记").font(.headline)
            Text(quote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            TextEditor(text: $bodyText).font(.body).frame(minHeight: 140)
            HStack {
                if let onDelete { Button("删除", role: .destructive, action: onDelete) }
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") { onSave(bodyText) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && onDelete == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 280)
        .onAppear { bodyText = initialBody }
    }
}
