import AppKit
import EvolutionHubCore
import SwiftUI

/// Renders study-note Markdown with Obsidian-like structural fidelity:
/// headings, one list item per line, fenced code, quotes, and inline marks.
///
/// Important: do NOT feed multi-item lists into `AttributedString(markdown:)`
/// with `.full` syntax. Apple's parser keeps list structure only as
/// presentation intents; SwiftUI `Text` often collapses those into one run,
/// which is exactly the flattened layout users rejected.
struct MarkdownBodyView: View {
    let text: String
    var bodyFontSize: CGFloat = 16

    var body: some View {
        let structure = MarkdownStructure.parse(text)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(structure.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
                    .padding(.top, topPadding(for: block))
                    .padding(.bottom, bottomPadding(for: block))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        })
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownStructure.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inlineAttributed(text, bodyFontSize: headingSize(level), weight: headingWeight(level)))
                .textSelection(.enabled)
                .lineSpacing(4)
        case .paragraph(let text):
            // Preserve hard line breaks inside a paragraph block.
            Text(Self.inlineAttributed(text, bodyFontSize: bodyFontSize, weight: .regular, preserveLineBreaks: true))
                .textSelection(.enabled)
                .lineSpacing(6)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(listMarker(ordered: ordered, item: item, index: index))
                            .font(.system(size: bodyFontSize, weight: .regular).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 14, alignment: .trailing)
                        Text(Self.inlineAttributed(item.text, bodyFontSize: bodyFontSize, weight: .regular))
                            .textSelection(.enabled)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(min(item.indent, 24)))
                }
            }
        case .code(let text):
            Text(text)
                .font(.system(size: bodyFontSize - 1, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 3)
                Text(Self.inlineAttributed(text, bodyFontSize: bodyFontSize, weight: .regular, preserveLineBreaks: true))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func listMarker(ordered: Bool, item: MarkdownStructure.ListItem, index: Int) -> String {
        if ordered {
            let number = Int(item.marker) ?? (index + 1)
            return "\(number)."
        }
        return "•"
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return bodyFontSize + 9
        case 2: return bodyFontSize + 5
        case 3: return bodyFontSize + 2
        default: return bodyFontSize + 1
        }
    }

    private func headingWeight(_ level: Int) -> Font.Weight {
        switch level {
        case 1: return .bold
        case 2, 3: return .semibold
        default: return .medium
        }
    }

    private func topPadding(for block: MarkdownStructure.Block) -> CGFloat {
        switch block {
        case .heading(let level, _):
            return level <= 1 ? 18 : (level == 2 ? 16 : 12)
        case .paragraph, .list, .quote:
            return 8
        case .code:
            return 10
        case .thematicBreak:
            return 12
        }
    }

    private func bottomPadding(for block: MarkdownStructure.Block) -> CGFloat {
        switch block {
        case .heading:
            return 6
        case .paragraph, .list, .quote:
            return 10
        case .code:
            return 12
        case .thematicBreak:
            return 12
        }
    }

    /// Inline-only Markdown so bold/italic/code/links work without collapsing block structure.
    static func inlineAttributed(
        _ markdown: String,
        bodyFontSize: CGFloat,
        weight: Font.Weight,
        preserveLineBreaks: Bool = false
    ) -> AttributedString {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Convert hard line breaks to Markdown hard-break syntax before inline parse,
        // otherwise CommonMark soft-breaks become spaces.
        let source: String
        if preserveLineBreaks {
            source = normalized
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .joined(separator: "  \n")
        } else {
            source = normalized
        }

        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible

        var attributed: AttributedString
        if let parsed = try? AttributedString(markdown: source, options: options) {
            attributed = parsed
        } else {
            attributed = AttributedString(normalized)
        }

        attributed.font = .system(size: bodyFontSize, weight: weight)
        attributed.foregroundColor = .primary

        for run in attributed.runs {
            if run.link != nil {
                attributed[run.range].foregroundColor = Color(nsColor: .linkColor)
                attributed[run.range].underlineStyle = .single
            }
        }
        return attributed
    }
}
