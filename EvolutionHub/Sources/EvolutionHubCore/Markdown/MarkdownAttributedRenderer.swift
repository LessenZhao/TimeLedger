import AppKit
import Foundation

/// Single continuous Obsidian-like Markdown display + display→source UTF-16 map.
public struct MarkdownRenderResult {
    public let source: String
    public let display: NSAttributedString
    /// Parallel to display UTF-16: source index, or -1 for synthetic glyphs.
    public let sourceMap: [Int]
    /// Display ranges that should draw a left quote bar.
    public let quoteDisplayRanges: [NSRange]

    public init(
        source: String,
        display: NSAttributedString,
        sourceMap: [Int],
        quoteDisplayRanges: [NSRange] = []
    ) {
        self.source = source
        self.display = display
        self.sourceMap = sourceMap
        self.quoteDisplayRanges = quoteDisplayRanges
    }

    public func sourceRange(forDisplay range: NSRange) -> NSRange? {
        guard range.location >= 0, range.length > 0,
              range.location + range.length <= sourceMap.count else { return nil }
        var indices: [Int] = []
        for i in range.location ..< (range.location + range.length) {
            let src = sourceMap[i]
            if src >= 0 { indices.append(src) }
        }
        guard let lo = indices.min(), let hi = indices.max() else { return nil }
        let length = hi - lo + 1
        guard lo >= 0, length > 0, lo + length <= (source as NSString).length else { return nil }
        return NSRange(location: lo, length: length)
    }

    public func sourceQuote(forDisplay range: NSRange) -> String? {
        guard let sourceRange = sourceRange(forDisplay: range) else { return nil }
        return (source as NSString).substring(with: sourceRange)
    }

    public func displayRanges(forSource range: NSRange) -> [NSRange] {
        guard range.location >= 0, range.length > 0 else { return [] }
        let end = range.location + range.length
        var ranges: [NSRange] = []
        var runStart: Int?
        for (displayIndex, sourceIndex) in sourceMap.enumerated() {
            let hit = sourceIndex >= range.location && sourceIndex < end
            if hit {
                if runStart == nil { runStart = displayIndex }
            } else if let start = runStart {
                ranges.append(NSRange(location: start, length: displayIndex - start))
                runStart = nil
            }
        }
        if let start = runStart {
            ranges.append(NSRange(location: start, length: sourceMap.count - start))
        }
        return ranges
    }
}

public enum MarkdownAttributedRenderer {
    public struct Options {
        /// Match MarkdownBodyView default reading size (and Obsidian comfort).
        public var bodyFontSize: CGFloat = 16
        public var textColor: NSColor = .labelColor
        public var secondaryColor: NSColor = .secondaryLabelColor
        public var linkColor: NSColor = .linkColor
        public var codeBackground: NSColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9)
        public var highlightColor: NSColor = NSColor.systemYellow.withAlphaComponent(0.35)

        public init() {}
        public init(bodyFontSize: CGFloat) {
            self.bodyFontSize = bodyFontSize
        }
    }

    public static func render(
        source: String,
        highlights: [NSRange] = [],
        options: Options = Options()
    ) -> MarkdownRenderResult {
        let builder = Builder(source: source, options: options)
        builder.build()
        var result = builder.finalize()
        if !highlights.isEmpty {
            result = applyHighlights(result, highlights: highlights, color: options.highlightColor)
        }
        return result
    }

    public static func attributedString(
        source: String,
        highlights: [NSRange] = [],
        options: Options = Options()
    ) -> NSAttributedString {
        render(source: source, highlights: highlights, options: options).display
    }

    private static func applyHighlights(
        _ result: MarkdownRenderResult,
        highlights: [NSRange],
        color: NSColor
    ) -> MarkdownRenderResult {
        let mutable = NSMutableAttributedString(attributedString: result.display)
        for sourceRange in highlights {
            for displayRange in result.displayRanges(forSource: sourceRange) {
                mutable.addAttribute(.backgroundColor, value: color, range: displayRange)
            }
        }
        return MarkdownRenderResult(
            source: result.source,
            display: mutable,
            sourceMap: result.sourceMap,
            quoteDisplayRanges: result.quoteDisplayRanges
        )
    }

    // MARK: - Builder

    private final class Builder {
        let source: String
        let sourceNS: NSString
        let options: Options
        let display = NSMutableAttributedString()
        var map: [Int] = []
        var quoteRanges: [NSRange] = []

        init(source: String, options: Options) {
            self.source = source
            self.sourceNS = source as NSString
            self.options = options
        }

        func build() {
            var offset = 0
            var inCodeFence = false
            var codeLines: [(text: String, sourceStart: Int)] = []

            func flushCode() {
                guard !codeLines.isEmpty else { return }
                ensureBlockBreak(before: 10)
                let codeStart = display.length
                for (idx, line) in codeLines.enumerated() {
                    if idx > 0 { appendSynthetic("\n", attrs: codeAttrs()) }
                    if line.text.isEmpty {
                        appendSynthetic(" ", attrs: codeAttrs())
                        if !map.isEmpty { map[map.count - 1] = line.sourceStart }
                    } else {
                        appendFromSource(
                            NSRange(location: line.sourceStart, length: (line.text as NSString).length),
                            attrs: codeAttrs()
                        )
                    }
                }
                let codeLen = display.length - codeStart
                if codeLen > 0 {
                    display.addAttribute(
                        .backgroundColor,
                        value: options.codeBackground,
                        range: NSRange(location: codeStart, length: codeLen)
                    )
                }
                appendSynthetic("\n", attrs: bodyAttrs())
                codeLines = []
            }

            while offset < sourceNS.length {
                let lineRange = sourceNS.lineRange(for: NSRange(location: offset, length: 0))
                let contentRange = stripTrailingNewline(lineRange)
                let lineText = sourceNS.substring(with: contentRange)
                let trimmed = lineText.trimmingCharacters(in: .whitespaces)
                let leadingWS = lineText.prefix { $0 == " " || $0 == "\t" }.count

                if trimmed.hasPrefix("```") {
                    if inCodeFence {
                        flushCode()
                        inCodeFence = false
                    } else {
                        inCodeFence = true
                        codeLines = []
                    }
                    offset = NSMaxRange(lineRange)
                    continue
                }

                if inCodeFence {
                    codeLines.append((text: lineText, sourceStart: contentRange.location))
                    offset = NSMaxRange(lineRange)
                    continue
                }

                if trimmed.isEmpty {
                    // Blank line → paragraph gap
                    if display.length > 0, display.string.last != "\n" {
                        appendSynthetic("\n", attrs: bodyAttrs())
                    }
                    appendSynthetic("\n", attrs: bodyAttrs(lineSpacing: 2, paraAfter: 0, paraBefore: 0))
                    offset = NSMaxRange(lineRange)
                    continue
                }

                if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                    ensureBlockBreak(before: 12)
                    appendSynthetic(
                        "────────────────────────────────────────",
                        attrs: [
                            .font: NSFont.systemFont(ofSize: 8, weight: .regular),
                            .foregroundColor: options.secondaryColor.withAlphaComponent(0.55),
                            .paragraphStyle: paragraphStyle(before: 10, after: 10, lineSpacing: 0),
                        ]
                    )
                    appendSynthetic("\n", attrs: bodyAttrs())
                    offset = NSMaxRange(lineRange)
                    continue
                }

                if let heading = parseHeading(trimmed) {
                    let before: CGFloat = heading.level <= 1 ? 20 : (heading.level == 2 ? 18 : 14)
                    ensureBlockBreak(before: before)
                    let title = heading.text
                    let titleRangeInLine = (lineText as NSString).range(of: title)
                    let titleSource: NSRange = {
                        if titleRangeInLine.location != NSNotFound {
                            return NSRange(
                                location: contentRange.location + titleRangeInLine.location,
                                length: titleRangeInLine.length
                            )
                        }
                        return contentRange
                    }()
                    let size = headingSize(heading.level)
                    let weight = headingWeight(heading.level)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: size, weight: weight),
                        .foregroundColor: options.textColor,
                        .paragraphStyle: paragraphStyle(before: 2, after: 8, lineSpacing: 4),
                    ]
                    if titleSource.length > 0 {
                        appendInline(sourceRange: titleSource, baseAttrs: attrs)
                    } else if !title.isEmpty {
                        appendSynthetic(title, attrs: attrs)
                    }
                    appendSynthetic("\n", attrs: attrs)
                    offset = NSMaxRange(lineRange)
                    continue
                }

                if trimmed.hasPrefix(">") {
                    ensureBlockBreak(before: 8)
                    var body = trimmed
                    while body.hasPrefix(">") {
                        body = String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
                    }
                    let bodyRangeInLine = (lineText as NSString).range(of: body)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: options.bodyFontSize, weight: .regular),
                        .foregroundColor: options.secondaryColor,
                        .paragraphStyle: paragraphStyle(
                            before: 2,
                            after: 6,
                            lineSpacing: 5,
                            headIndent: 16,
                            firstLineHeadIndent: 16
                        ),
                    ]
                    let qStart = display.length
                    if bodyRangeInLine.location != NSNotFound, !body.isEmpty {
                        let src = NSRange(
                            location: contentRange.location + bodyRangeInLine.location,
                            length: bodyRangeInLine.length
                        )
                        appendInline(sourceRange: src, baseAttrs: attrs)
                    } else if !body.isEmpty {
                        appendSynthetic(body, attrs: attrs)
                    }
                    let qLen = display.length - qStart
                    if qLen > 0 {
                        quoteRanges.append(NSRange(location: qStart, length: qLen))
                    }
                    appendSynthetic("\n", attrs: attrs)
                    offset = NSMaxRange(lineRange)
                    continue
                }

                if let list = parseListItem(trimmed) {
                    ensureBlockBreak(before: 2)
                    let indent = CGFloat(min(leadingWS, 24))
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: options.bodyFontSize, weight: .regular),
                        .foregroundColor: options.textColor,
                        .paragraphStyle: paragraphStyle(
                            before: 1,
                            after: 3,
                            lineSpacing: 4,
                            headIndent: indent + 22,
                            firstLineHeadIndent: indent + 4
                        ),
                    ]
                    let markerDisplay = list.ordered ? "\(list.marker). " : "•  "
                    appendSynthetic(markerDisplay, attrs: [
                        .font: NSFont.systemFont(ofSize: options.bodyFontSize, weight: .regular),
                        .foregroundColor: options.secondaryColor,
                        .paragraphStyle: attrs[.paragraphStyle] as Any,
                    ])
                    let itemText = list.text
                    let itemRangeInLine = (lineText as NSString).range(of: itemText, options: .backwards)
                    if itemRangeInLine.location != NSNotFound, itemRangeInLine.length > 0 {
                        let src = NSRange(
                            location: contentRange.location + itemRangeInLine.location,
                            length: itemRangeInLine.length
                        )
                        appendInline(sourceRange: src, baseAttrs: attrs)
                    } else if !itemText.isEmpty {
                        appendSynthetic(itemText, attrs: attrs)
                    }
                    appendSynthetic("\n", attrs: attrs)
                    offset = NSMaxRange(lineRange)
                    continue
                }

                // paragraph
                ensureBlockBreak(before: 4)
                let attrs = bodyAttrs(lineSpacing: 6, paraAfter: 8, paraBefore: 2)
                if contentRange.length > 0 {
                    appendInline(sourceRange: contentRange, baseAttrs: attrs)
                }
                appendSynthetic("\n", attrs: attrs)
                offset = NSMaxRange(lineRange)
            }

            if inCodeFence { flushCode() }

            // Trim trailing newlines
            while display.length > 0, display.string.last == "\n" {
                display.deleteCharacters(in: NSRange(location: display.length - 1, length: 1))
                if !map.isEmpty { map.removeLast() }
                // fix quote ranges if needed
                quoteRanges = quoteRanges.compactMap { r in
                    if r.location >= display.length { return nil }
                    let maxLen = display.length - r.location
                    return NSRange(location: r.location, length: min(r.length, maxLen))
                }
            }
        }

        func finalize() -> MarkdownRenderResult {
            precondition(display.length == map.count)
            return MarkdownRenderResult(
                source: source,
                display: display,
                sourceMap: map,
                quoteDisplayRanges: quoteRanges
            )
        }

        private func ensureBlockBreak(before: CGFloat) {
            guard display.length > 0 else { return }
            if display.string.last != "\n" {
                appendSynthetic("\n", attrs: bodyAttrs())
            }
        }

        private func appendSynthetic(_ string: String, attrs: [NSAttributedString.Key: Any]) {
            guard !string.isEmpty else { return }
            display.append(NSAttributedString(string: string, attributes: attrs))
            map.append(contentsOf: repeatElement(-1, count: (string as NSString).length))
        }

        private func appendFromSource(_ range: NSRange, attrs: [NSAttributedString.Key: Any]) {
            guard range.length > 0,
                  range.location >= 0,
                  range.location + range.length <= sourceNS.length else { return }
            let piece = sourceNS.substring(with: range)
            display.append(NSAttributedString(string: piece, attributes: attrs))
            for i in 0 ..< range.length { map.append(range.location + i) }
        }

        private func appendInline(sourceRange: NSRange, baseAttrs: [NSAttributedString.Key: Any]) {
            guard sourceRange.length > 0 else { return }
            let segment = sourceNS.substring(with: sourceRange) as NSString
            var cursor = 0
            let length = segment.length

            while cursor < length {
                let rest = segment.substring(from: cursor) as NSString

                if rest.hasPrefix("**"),
                   let close = findClosing(rest, openLen: 2, close: "**", from: 2) {
                    let innerLen = close - 2
                    var attrs = baseAttrs
                    let size = (baseAttrs[.font] as? NSFont)?.pointSize ?? options.bodyFontSize
                    attrs[.font] = NSFont.systemFont(ofSize: size, weight: .semibold)
                    appendFromSource(
                        NSRange(location: sourceRange.location + cursor + 2, length: innerLen),
                        attrs: attrs
                    )
                    cursor += close + 2
                    continue
                }

                if rest.hasPrefix("`"),
                   let close = findClosing(rest, openLen: 1, close: "`", from: 1) {
                    let innerLen = close - 1
                    var attrs = baseAttrs
                    let size = (baseAttrs[.font] as? NSFont)?.pointSize ?? options.bodyFontSize
                    attrs[.font] = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                    attrs[.backgroundColor] = options.codeBackground
                    appendFromSource(
                        NSRange(location: sourceRange.location + cursor + 1, length: innerLen),
                        attrs: attrs
                    )
                    cursor += close + 1
                    continue
                }

                if rest.hasPrefix("["), let link = parseLink(rest) {
                    var attrs = baseAttrs
                    attrs[.foregroundColor] = options.linkColor
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    appendFromSource(
                        NSRange(
                            location: sourceRange.location + cursor + link.labelRange.location,
                            length: link.labelRange.length
                        ),
                        attrs: attrs
                    )
                    cursor += link.totalLength
                    continue
                }

                if rest.hasPrefix("*"), !rest.hasPrefix("**"),
                   let close = findClosing(rest, openLen: 1, close: "*", from: 1), close > 1 {
                    let innerLen = close - 1
                    var attrs = baseAttrs
                    if let font = baseAttrs[.font] as? NSFont,
                       let italic = NSFont(
                        descriptor: font.fontDescriptor.withSymbolicTraits(.italic),
                        size: font.pointSize
                       ) {
                        attrs[.font] = italic
                    }
                    appendFromSource(
                        NSRange(location: sourceRange.location + cursor + 1, length: innerLen),
                        attrs: attrs
                    )
                    cursor += close + 1
                    continue
                }

                appendFromSource(
                    NSRange(location: sourceRange.location + cursor, length: 1),
                    attrs: baseAttrs
                )
                cursor += 1
            }
        }

        private func findClosing(_ text: NSString, openLen: Int, close: String, from: Int) -> Int? {
            let c = close as NSString
            var i = from
            while i <= text.length - c.length {
                if text.substring(with: NSRange(location: i, length: c.length)) == close {
                    return i
                }
                i += 1
            }
            return nil
        }

        private struct LinkParse {
            var labelRange: NSRange
            var totalLength: Int
        }

        private func parseLink(_ text: NSString) -> LinkParse? {
            guard text.length > 4, text.character(at: 0) == 91 else { return nil }
            var i = 1
            while i < text.length {
                if text.character(at: i) == 93 {
                    let labelLen = i - 1
                    guard i + 1 < text.length, text.character(at: i + 1) == 40 else { return nil }
                    var j = i + 2
                    while j < text.length {
                        if text.character(at: j) == 41 {
                            return LinkParse(
                                labelRange: NSRange(location: 1, length: labelLen),
                                totalLength: j + 1
                            )
                        }
                        j += 1
                    }
                    return nil
                }
                if text.character(at: i) == 10 { return nil }
                i += 1
            }
            return nil
        }

        private func bodyAttrs(
            lineSpacing: CGFloat = 6,
            paraAfter: CGFloat = 6,
            paraBefore: CGFloat = 0
        ) -> [NSAttributedString.Key: Any] {
            [
                .font: NSFont.systemFont(ofSize: options.bodyFontSize, weight: .regular),
                .foregroundColor: options.textColor,
                .paragraphStyle: paragraphStyle(before: paraBefore, after: paraAfter, lineSpacing: lineSpacing),
            ]
        }

        private func codeAttrs() -> [NSAttributedString.Key: Any] {
            [
                .font: NSFont.monospacedSystemFont(ofSize: max(12, options.bodyFontSize - 1), weight: .regular),
                .foregroundColor: options.textColor,
                .paragraphStyle: paragraphStyle(before: 1, after: 1, lineSpacing: 3),
            ]
        }

        /// Same deltas as MarkdownBodyView.
        private func headingSize(_ level: Int) -> CGFloat {
            switch level {
            case 1: return options.bodyFontSize + 10  // clearer H1
            case 2: return options.bodyFontSize + 6   // clearer H2
            case 3: return options.bodyFontSize + 3
            default: return options.bodyFontSize + 1
            }
        }

        private func headingWeight(_ level: Int) -> NSFont.Weight {
            switch level {
            case 1: return .bold
            case 2: return .semibold
            case 3: return .semibold
            default: return .medium
            }
        }

        private func paragraphStyle(
            before: CGFloat,
            after: CGFloat,
            lineSpacing: CGFloat,
            headIndent: CGFloat = 0,
            firstLineHeadIndent: CGFloat? = nil
        ) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = before
            style.paragraphSpacing = after
            style.lineSpacing = lineSpacing
            style.headIndent = headIndent
            style.firstLineHeadIndent = firstLineHeadIndent ?? headIndent
            style.lineBreakMode = .byWordWrapping
            style.alignment = .left
            return style
        }

        private func stripTrailingNewline(_ lineRange: NSRange) -> NSRange {
            guard lineRange.length > 0 else { return lineRange }
            let line = sourceNS.substring(with: lineRange)
            var length = lineRange.length
            if line.hasSuffix("\r\n") { length -= 2 }
            else if line.hasSuffix("\n") || line.hasSuffix("\r") { length -= 1 }
            return NSRange(location: lineRange.location, length: max(0, length))
        }

        private func parseHeading(_ trimmed: String) -> (level: Int, text: String)? {
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

        private func parseListItem(_ trimmed: String) -> (ordered: Bool, marker: String, text: String)? {
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                return (false, String(trimmed.prefix(1)), String(trimmed.dropFirst(2)))
            }
            var digits = ""
            for ch in trimmed {
                if ch.isNumber { digits.append(ch) } else { break }
            }
            guard !digits.isEmpty else { return nil }
            let rest = trimmed.dropFirst(digits.count)
            guard rest.hasPrefix(". ") else { return nil }
            return (true, digits, String(rest.dropFirst(2)))
        }
    }
}
