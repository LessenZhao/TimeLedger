import Foundation

/// Layout Document: block sequence + source UTF-16 ranges.
/// Pure data hub for L1 painting and L2 selection mapping (008).
public struct MarkdownLayoutDocument: Sendable, Equatable {
    public struct RangeUTF16: Sendable, Equatable {
        public var location: Int
        public var length: Int

        public init(location: Int, length: Int) {
            self.location = location
            self.length = length
        }

        public var nsRange: NSRange { NSRange(location: location, length: length) }
    }

    public enum BlockKind: Sendable, Equatable {
        case heading(level: Int)
        case paragraph
        case listItem(ordered: Bool, marker: String, indent: Int)
        case code
        case quote
        case thematicBreak
    }

    public struct Block: Sendable, Equatable, Identifiable {
        public var id: String
        public var kind: BlockKind
        /// UTF-16 range in `source` covering the semantic text for this block
        /// (heading title, paragraph body, list item text, quote body, code body).
        public var sourceRange: RangeUTF16
        /// Display core text (matches MarkdownBodyView / MarkdownStructure text).
        public var text: String

        public init(id: String, kind: BlockKind, sourceRange: RangeUTF16, text: String) {
            self.id = id
            self.kind = kind
            self.sourceRange = sourceRange
            self.text = text
        }
    }

    public var source: String
    public var blocks: [Block]

    public init(source: String, blocks: [Block]) {
        self.source = source
        self.blocks = blocks
    }

    /// Map a selection inside `block.text` (UTF-16) to a range in full `source`.
    public func sourceRange(blockID: String, textUTF16Range: NSRange) -> RangeUTF16? {
        guard let block = blocks.first(where: { $0.id == blockID }) else { return nil }
        guard textUTF16Range.location >= 0, textUTF16Range.length > 0 else { return nil }
        let textNS = block.text as NSString
        guard textUTF16Range.location + textUTF16Range.length <= textNS.length else { return nil }
        // block.text is a slice of source at sourceRange (builder invariant).
        let loc = block.sourceRange.location + textUTF16Range.location
        let len = textUTF16Range.length
        let sourceNS = source as NSString
        guard loc >= 0, loc + len <= sourceNS.length else { return nil }
        return RangeUTF16(location: loc, length: len)
    }

    public func quote(blockID: String, textUTF16Range: NSRange) -> String? {
        guard let r = sourceRange(blockID: blockID, textUTF16Range: textUTF16Range) else { return nil }
        return (source as NSString).substring(with: r.nsRange)
    }
}

/// Builds a Layout Document with the same block splitting behavior as `MarkdownStructure.parse`,
/// while recording UTF-16 source ranges for each block's semantic text.
public enum MarkdownLayoutBuilder {
    public static func build(source: String) -> MarkdownLayoutDocument {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // Prefer original source for ranges when normalization is a no-op.
        let sourceForRanges: String
        let ns: NSString
        if normalized == source {
            sourceForRanges = source
            ns = source as NSString
        } else {
            sourceForRanges = normalized
            ns = normalized as NSString
        }

        var blocks: [MarkdownLayoutDocument.Block] = []
        var blockIndex = 0
        func nextID(_ prefix: String) -> String {
            defer { blockIndex += 1 }
            return "\(prefix)-\(blockIndex)"
        }

        // Line table: (startUTF16, content without newline, full line length including newline)
        var lines: [(start: Int, content: String, end: Int)] = []
        var offset = 0
        while offset < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: offset, length: 0))
            let full = ns.substring(with: lineRange)
            var contentLen = lineRange.length
            if full.hasSuffix("\r\n") { contentLen -= 2 }
            else if full.hasSuffix("\n") || full.hasSuffix("\r") { contentLen -= 1 }
            let content = ns.substring(with: NSRange(location: lineRange.location, length: max(0, contentLen)))
            lines.append((lineRange.location, content, NSMaxRange(lineRange)))
            offset = NSMaxRange(lineRange)
        }
        if lines.isEmpty {
            return MarkdownLayoutDocument(source: sourceForRanges, blocks: [])
        }

        var i = 0
        var paragraphBuf: [(start: Int, text: String)] = []
        var listBuf: [(ordered: Bool, marker: String, indent: Int, text: String, range: MarkdownLayoutDocument.RangeUTF16)] = []
        var listOrdered: Bool?

        func flushParagraph() {
            guard !paragraphBuf.isEmpty else { return }
            let text = paragraphBuf.map(\.text).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                paragraphBuf = []
                return
            }
            // Range from first non-empty line start through last line content end
            let first = paragraphBuf.first!
            let last = paragraphBuf.last!
            let start = first.start
            let end = last.start + (last.text as NSString).length
            // Tighten to actual `text` occurrence if possible
            let sliceRange = rangeOfSemanticText(text, preferringStart: start, in: ns)
            blocks.append(
                MarkdownLayoutDocument.Block(
                    id: nextID("p"),
                    kind: .paragraph,
                    sourceRange: sliceRange,
                    text: text
                )
            )
            paragraphBuf = []
            _ = end
        }

        func flushList() {
            guard let ordered = listOrdered, !listBuf.isEmpty else {
                listBuf = []
                listOrdered = nil
                return
            }
            for item in listBuf {
                blocks.append(
                    MarkdownLayoutDocument.Block(
                        id: nextID("li"),
                        kind: .listItem(ordered: ordered, marker: item.marker, indent: item.indent),
                        sourceRange: item.range,
                        text: item.text
                    )
                )
            }
            listBuf = []
            listOrdered = nil
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.content.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushList()
                i += 1
                var codeParts: [(start: Int, text: String)] = []
                while i < lines.count {
                    let cl = lines[i]
                    if cl.content.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeParts.append((cl.start, cl.content))
                    i += 1
                }
                let codeText = codeParts.map(\.text).joined(separator: "\n")
                let range: MarkdownLayoutDocument.RangeUTF16
                if let first = codeParts.first, let last = codeParts.last {
                    let loc = first.start
                    let len = (last.start + (last.text as NSString).length) - loc
                    range = MarkdownLayoutDocument.RangeUTF16(location: loc, length: max(0, len))
                } else {
                    range = MarkdownLayoutDocument.RangeUTF16(location: line.start, length: 0)
                }
                blocks.append(
                    MarkdownLayoutDocument.Block(
                        id: nextID("code"),
                        kind: .code,
                        sourceRange: range,
                        text: codeText
                    )
                )
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                i += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                flushList()
                let r = rangeOfSemanticText(trimmed, preferringStart: line.start, in: ns)
                blocks.append(
                    MarkdownLayoutDocument.Block(
                        id: nextID("hr"),
                        kind: .thematicBreak,
                        sourceRange: r,
                        text: ""
                    )
                )
                i += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                flushList()
                let r = rangeOfSemanticText(heading.text, preferringStart: line.start, in: ns)
                blocks.append(
                    MarkdownLayoutDocument.Block(
                        id: nextID("h"),
                        kind: .heading(level: heading.level),
                        sourceRange: r,
                        text: heading.text
                    )
                )
                i += 1
                continue
            }

            if let item = parseListItem(line.content) {
                flushParagraph()
                if let ordered = listOrdered, ordered != item.ordered {
                    flushList()
                }
                listOrdered = item.ordered
                let r = rangeOfSemanticText(item.text, preferringStart: line.start, in: ns)
                listBuf.append(
                    (
                        ordered: item.ordered,
                        marker: item.marker,
                        indent: item.indent,
                        text: item.text,
                        range: r
                    )
                )
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                var quoteParts: [(start: Int, text: String)] = []
                while i < lines.count {
                    let qLine = lines[i]
                    let qTrim = qLine.content.trimmingCharacters(in: .whitespaces)
                    guard qTrim.hasPrefix(">") else { break }
                    var body = qTrim
                    while body.hasPrefix(">") {
                        body = String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
                    }
                    // locate body in original line content
                    let bodyRangeInLine = (qLine.content as NSString).range(of: body)
                    let start: Int
                    if bodyRangeInLine.location != NSNotFound {
                        start = qLine.start + bodyRangeInLine.location
                    } else {
                        start = qLine.start
                    }
                    quoteParts.append((start, body))
                    i += 1
                }
                let qText = quoteParts.map(\.text).joined(separator: "\n")
                let range: MarkdownLayoutDocument.RangeUTF16
                if qText.isEmpty {
                    range = MarkdownLayoutDocument.RangeUTF16(location: line.start, length: 0)
                } else if let first = quoteParts.first, let last = quoteParts.last {
                    let loc = first.start
                    let len = (last.start + (last.text as NSString).length) - loc
                    range = MarkdownLayoutDocument.RangeUTF16(location: loc, length: max(0, len))
                } else {
                    range = rangeOfSemanticText(qText, preferringStart: line.start, in: ns)
                }
                blocks.append(
                    MarkdownLayoutDocument.Block(
                        id: nextID("q"),
                        kind: .quote,
                        sourceRange: range,
                        text: qText
                    )
                )
                continue
            }

            flushList()
            let paraText = line.content.trimmingCharacters(in: .whitespaces)
            let paraStart: Int = {
                let r = (line.content as NSString).range(of: paraText)
                if r.location != NSNotFound { return line.start + r.location }
                return line.start
            }()
            paragraphBuf.append((paraStart, paraText))
            i += 1
        }

        flushParagraph()
        flushList()
        return MarkdownLayoutDocument(source: sourceForRanges, blocks: blocks)
    }

    // MARK: - Helpers

    private static func rangeOfSemanticText(
        _ text: String,
        preferringStart: Int,
        in ns: NSString
    ) -> MarkdownLayoutDocument.RangeUTF16 {
        guard !text.isEmpty else {
            return MarkdownLayoutDocument.RangeUTF16(location: preferringStart, length: 0)
        }
        let full = ns.range(of: text, options: [], range: NSRange(location: 0, length: ns.length))
        // Prefer occurrence at/after preferringStart
        var searchStart = min(max(0, preferringStart), ns.length)
        let after = ns.range(
            of: text,
            options: [],
            range: NSRange(location: searchStart, length: ns.length - searchStart)
        )
        if after.location != NSNotFound {
            return MarkdownLayoutDocument.RangeUTF16(location: after.location, length: after.length)
        }
        if full.location != NSNotFound {
            return MarkdownLayoutDocument.RangeUTF16(location: full.location, length: full.length)
        }
        return MarkdownLayoutDocument.RangeUTF16(location: preferringStart, length: 0)
    }

    private static func parseHeading(_ trimmed: String) -> (level: Int, text: String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.first == " " || rest.isEmpty else { return nil }
        return (level, String(rest.drop(while: { $0 == " " })))
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
            return (false, indent, String(rest.prefix(1)), String(rest.dropFirst(2)))
        }
        var digits = ""
        var cursor = rest.startIndex
        while cursor < rest.endIndex, rest[cursor].isNumber {
            digits.append(rest[cursor])
            cursor = rest.index(after: cursor)
        }
        guard !digits.isEmpty, cursor < rest.endIndex, rest[cursor] == "." else { return nil }
        let afterDot = rest.index(after: cursor)
        guard afterDot < rest.endIndex, rest[afterDot] == " " else { return nil }
        let textStart = rest.index(after: afterDot)
        return (true, indent, digits, String(rest[textStart...]))
    }
}
