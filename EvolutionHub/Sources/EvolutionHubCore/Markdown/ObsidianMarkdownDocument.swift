import Foundation

/// Authoritative input and validation boundary for the offline Web reader.
///
/// JavaScript may report a range only after it has mapped the browser selection
/// to source UTF-16 offsets. This type deliberately validates, rather than
/// repairing, that report: a malformed mapping cannot become a ReadingNote.
public struct ObsidianMarkdownDocument: Sendable, Equatable {
    public struct Section: Sendable, Equatable, Identifiable {
        public let id: String
        public let markdown: String

        public init(id: String, markdown: String) {
            self.id = id
            self.markdown = markdown
        }
    }

    public struct Selection: Sendable, Equatable {
        public let sectionID: String
        public let sourceRange: NSRange
        public let quote: String

        public init(sectionID: String, sourceRange: NSRange, quote: String) {
            self.sectionID = sectionID
            self.sourceRange = sourceRange
            self.quote = quote
        }
    }

    public enum ValidationError: Error, Equatable {
        case emptySectionID
        case duplicateSectionID(String)
        case unknownSection(String)
        case emptySelection
        case sourceRangeOutOfBounds
        case quoteDoesNotMatchSource
    }

    public let sections: [Section]

    public init(sections: [Section]) throws {
        var known = Set<String>()
        for section in sections {
            guard !section.id.isEmpty else { throw ValidationError.emptySectionID }
            guard known.insert(section.id).inserted else {
                throw ValidationError.duplicateSectionID(section.id)
            }
        }
        self.sections = sections
    }

    public func validatedSelection(
        sectionID: String,
        sourceRange: NSRange,
        quote: String
    ) throws -> Selection {
        guard !quote.isEmpty, sourceRange.location >= 0, sourceRange.length > 0 else {
            throw ValidationError.emptySelection
        }
        guard let section = sections.first(where: { $0.id == sectionID }) else {
            throw ValidationError.unknownSection(sectionID)
        }
        let length = (section.markdown as NSString).length
        guard sourceRange.location <= length,
              sourceRange.length <= length - sourceRange.location else {
            throw ValidationError.sourceRangeOutOfBounds
        }
        let slice = (section.markdown as NSString).substring(with: sourceRange)
        guard Self.visibleText(fromMarkdown: slice) == Self.normalized(quote) else {
            throw ValidationError.quoteDoesNotMatchSource
        }
        return Selection(sectionID: sectionID, sourceRange: sourceRange, quote: quote)
    }

    private static func visibleText(fromMarkdown source: String) -> String {
        var text = source
        let linkPattern = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]+\)"#)
        let matches = linkPattern.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        for match in matches.reversed() {
            let label = (text as NSString).substring(with: match.range(at: 1))
            text = (text as NSString).replacingCharacters(in: match.range, with: label)
        }
        let footnotePattern = try! NSRegularExpression(pattern: #"\[\^[^\]]+\]"#)
        text = footnotePattern.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: ""
        )
        text = stripBlockSyntax(from: text)
        for marker in ["**", "__", "~~", "`", "\\"] {
            text = text.replacingOccurrences(of: marker, with: "")
        }
        return normalized(text)
    }

    /// A browser range spanning rendered blocks also spans their Markdown
    /// delimiters in source. Those delimiters have no visible counterpart and
    /// must not make an otherwise exact visible quote fail validation.
    private static func stripBlockSyntax(from source: String) -> String {
        var text = source
        let patterns = [
            #"(?m)^[ \t]{0,3}#{1,6}[ \t]+"#,
            #"(?m)^[ \t]{0,3}(?:>[ \t]?)+"#,
            #"(?m)^[ \t]*(?:[-+*]|\d+[.)])[ \t]+"#,
            #"(?m)^[ \t]*\[[ xX]\][ \t]+"#,
            #"(?m)^[ \t]*(?:```|~~~)[^\n]*$"#,
            #"(?m)^[ \t|:-]+$"#
        ]
        for pattern in patterns {
            let expression = try! NSRegularExpression(pattern: pattern)
            text = expression.stringByReplacingMatches(
                in: text,
                range: NSRange(location: 0, length: (text as NSString).length),
                withTemplate: ""
            )
        }
        return text.replacingOccurrences(of: "|", with: " ")
    }

    private static func normalized(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
