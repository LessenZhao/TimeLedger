import Foundation

/// Block-level Markdown structure used for fidelity rendering.
/// Goal: preserve the same visual hierarchy Obsidian shows for study notes
/// (headings, list items on separate lines, fenced code, quotes).
public struct MarkdownStructure: Sendable, Equatable {
    public enum Block: Sendable, Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case list(ordered: Bool, items: [ListItem])
        case code(String)
        case quote(String)
        case thematicBreak
    }

    public struct ListItem: Sendable, Equatable {
        public var indent: Int
        public var marker: String
        public var text: String

        public init(indent: Int, marker: String, text: String) {
            self.indent = indent
            self.marker = marker
            self.text = text
        }
    }

    public var blocks: [Block]

    public init(blocks: [Block]) {
        self.blocks = blocks
    }

    public static func parse(_ markdown: String) -> MarkdownStructure {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var blocks: [Block] = []
        var index = 0
        var paragraphLines: [String] = []
        var listItems: [ListItem] = []
        var listOrdered: Bool?

        func flushParagraph() {
            let raw = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraphLines = []
            guard !raw.isEmpty else { return }
            blocks.append(.paragraph(raw))
        }

        func flushList() {
            guard let ordered = listOrdered, !listItems.isEmpty else {
                listItems = []
                listOrdered = nil
                return
            }
            blocks.append(.list(ordered: ordered, items: listItems))
            listItems = []
            listOrdered = nil
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushList()
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let codeLine = lines[index]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(codeLine)
                    index += 1
                }
                blocks.append(.code(codeLines.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                flushList()
                blocks.append(.thematicBreak)
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                flushList()
                blocks.append(.heading(level: heading.0, text: heading.1))
                index += 1
                continue
            }

            if let item = parseListItem(line) {
                flushParagraph()
                if let ordered = listOrdered, ordered != item.ordered {
                    flushList()
                }
                listOrdered = item.ordered
                listItems.append(ListItem(indent: item.indent, marker: item.marker, text: item.text))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                var quoteLines: [String] = []
                while index < lines.count {
                    let q = lines[index].trimmingCharacters(in: .whitespaces)
                    guard q.hasPrefix(">") else { break }
                    let body = q.dropFirst().drop(while: { $0 == " " })
                    quoteLines.append(String(body))
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            // Ordinary text line — keep hard line breaks inside a paragraph
            // until a blank line, so structure is not silently flattened.
            flushList()
            paragraphLines.append(line.trimmingCharacters(in: .whitespaces))
            index += 1
        }

        flushParagraph()
        flushList()
        return MarkdownStructure(blocks: blocks)
    }

    private static func parseHeading(_ trimmed: String) -> (Int, String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.first == " " || rest.isEmpty else { return nil }
        let text = rest.drop(while: { $0 == " " })
        return (level, String(text))
    }

    private static func parseListItem(_ line: String) -> (ordered: Bool, indent: Int, marker: String, text: String)? {
        var indent = 0
        var idx = line.startIndex
        while idx < line.endIndex {
            let ch = line[idx]
            if ch == " " {
                indent += 1
                idx = line.index(after: idx)
            } else if ch == "\t" {
                indent += 4
                idx = line.index(after: idx)
            } else {
                break
            }
        }
        let rest = String(line[idx...])
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") {
            let marker = String(rest.prefix(1))
            let text = String(rest.dropFirst(2))
            return (false, indent, marker, text)
        }
        // ordered: 1. / 12.
        var digits = ""
        var cursor = rest.startIndex
        while cursor < rest.endIndex, rest[cursor].isNumber {
            digits.append(rest[cursor])
            cursor = rest.index(after: cursor)
        }
        guard !digits.isEmpty,
              cursor < rest.endIndex,
              rest[cursor] == "." else { return nil }
        let afterDot = rest.index(after: cursor)
        guard afterDot < rest.endIndex, rest[afterDot] == " " else { return nil }
        let textStart = rest.index(after: afterDot)
        let text = String(rest[textStart...])
        return (true, indent, digits, text)
    }
}
