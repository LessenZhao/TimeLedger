import AppKit
import SwiftUI

/// Renders study-asset Markdown with visible block hierarchy:
/// heading levels, paragraph gaps, and tappable link anchors.
/// Long text is never shown as a single wall of unspaced runs.
struct MarkdownBodyView: View {
    let text: String
    var bodyFontSize: CGFloat = 15

    var body: some View {
        let blocks = Self.splitBlocks(text)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
                    .padding(.top, block.topPadding)
                    .padding(.bottom, block.bottomPadding)
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
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(Self.attributed(block.raw, bodyFontSize: bodyFontSize, preferHeadingLevel: level))
                .textSelection(.enabled)
                .lineSpacing(4)
        case .paragraph, .list, .code, .quote, .other:
            Text(Self.attributed(block.raw, bodyFontSize: bodyFontSize, preferHeadingLevel: nil))
                .textSelection(.enabled)
                .lineSpacing(6)
        }
    }

    // MARK: - Block split

    private struct MarkdownBlock {
        enum Kind {
            case heading(Int)
            case paragraph
            case list
            case code
            case quote
            case other
        }

        var raw: String
        var kind: Kind

        var topPadding: CGFloat {
            switch kind {
            case .heading(let level):
                return level <= 1 ? 18 : (level == 2 ? 16 : 12)
            case .paragraph, .list, .quote, .other:
                return 8
            case .code:
                return 10
            }
        }

        var bottomPadding: CGFloat {
            switch kind {
            case .heading:
                return 6
            case .paragraph, .list, .quote, .other:
                return 10
            case .code:
                return 12
            }
        }
    }

    /// Split markdown into block-level chunks so spacing is structural,
    /// not a single AttributedString wall.
    private static func splitBlocks(_ markdown: String) -> [MarkdownBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var blocks: [MarkdownBlock] = []
        var current: [String] = []
        var inFence = false

        func flush() {
            let raw = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            current = []
            guard !raw.isEmpty else { return }
            blocks.append(MarkdownBlock(raw: raw, kind: classify(raw)))
        }

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inFence {
                    current.append(line)
                    flush()
                    inFence = false
                } else {
                    flush()
                    inFence = true
                    current.append(line)
                }
                continue
            }
            if inFence {
                current.append(line)
                continue
            }
            if trimmed.isEmpty {
                flush()
                continue
            }
            if headingLevel(trimmed) != nil, !current.isEmpty {
                flush()
                current.append(line)
                flush()
                continue
            }
            if headingLevel(trimmed) != nil && current.isEmpty {
                current.append(line)
                flush()
                continue
            }
            current.append(line)
        }
        flush()
        return blocks
    }

    private static func headingLevel(_ line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " || rest.isEmpty else { return nil }
        return level
    }

    private static func classify(_ raw: String) -> MarkdownBlock.Kind {
        let first = raw.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? raw
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        if let level = headingLevel(trimmed) {
            return .heading(level)
        }
        if trimmed.hasPrefix("```") {
            return .code
        }
        if trimmed.hasPrefix(">") {
            return .quote
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return .list
        }
        if trimmed.first?.isNumber == true, trimmed.contains(". ") {
            return .list
        }
        return .paragraph
    }

    // MARK: - Inline attributed

    static func attributed(
        _ markdown: String,
        bodyFontSize: CGFloat = 15,
        preferHeadingLevel: Int? = nil
    ) -> AttributedString {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible

        var attributed: AttributedString
        if let parsed = try? AttributedString(markdown: normalized, options: options) {
            attributed = parsed
        } else {
            attributed = AttributedString(normalized)
        }

        attributed.font = .system(size: bodyFontSize)
        attributed.foregroundColor = .primary

        if let forced = preferHeadingLevel {
            let size: CGFloat
            let weight: Font.Weight
            switch forced {
            case 1:
                size = bodyFontSize + 9
                weight = .bold
            case 2:
                size = bodyFontSize + 5
                weight = .semibold
            case 3:
                size = bodyFontSize + 2
                weight = .semibold
            default:
                size = bodyFontSize + 1
                weight = .medium
            }
            attributed.font = .system(size: size, weight: weight)
        }

        for run in attributed.runs {
            let range = run.range
            if preferHeadingLevel == nil, let intent = run.presentationIntent {
                for component in intent.components {
                    switch component.kind {
                    case .header(let level):
                        let size: CGFloat
                        let weight: Font.Weight
                        switch level {
                        case 1:
                            size = bodyFontSize + 9
                            weight = .bold
                        case 2:
                            size = bodyFontSize + 5
                            weight = .semibold
                        case 3:
                            size = bodyFontSize + 2
                            weight = .semibold
                        default:
                            size = bodyFontSize + 1
                            weight = .medium
                        }
                        attributed[range].font = .system(size: size, weight: weight)
                    case .blockQuote:
                        attributed[range].foregroundColor = .secondary
                    default:
                        break
                    }
                }
            }

            if run.link != nil {
                attributed[range].foregroundColor = Color(nsColor: .linkColor)
                attributed[range].underlineStyle = .single
            }
        }

        return attributed
    }
}
