import EvolutionCore
import Foundation

/// Local, user-owned stars for imported ChatGPT conversations and turns.
/// Persisted beside the ledger; never written back into the ChatGPT archive.
public struct ChatConversationUserMarksDocument: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var starredConversationIDs: [String]
    public var starredTurnIDs: [String]

    public static let currentSchemaVersion = 1

    public static var empty: ChatConversationUserMarksDocument {
        ChatConversationUserMarksDocument(
            schemaVersion: currentSchemaVersion,
            starredConversationIDs: [],
            starredTurnIDs: []
        )
    }

    public init(
        schemaVersion: Int = currentSchemaVersion,
        starredConversationIDs: [String] = [],
        starredTurnIDs: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.starredConversationIDs = starredConversationIDs
        self.starredTurnIDs = starredTurnIDs
    }
}

public struct ChatConversationDayGroup: Identifiable, Sendable, Hashable {
    public var dayKey: String
    public var dayStart: Date
    public var conversations: [ChatConversationArchiveSummary]

    public var id: String { dayKey }

    public init(dayKey: String, dayStart: Date, conversations: [ChatConversationArchiveSummary]) {
        self.dayKey = dayKey
        self.dayStart = dayStart
        self.conversations = conversations
    }
}

public enum ChatConversationDayGrouping {
    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func groups(
        from conversations: [ChatConversationArchiveSummary],
        starredConversationIDs: Set<String>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ChatConversationDayGroup] {
        var buckets: [String: (dayStart: Date, items: [ChatConversationArchiveSummary])] = [:]

        for conversation in conversations {
            let date = ISO8601Codec.date(from: conversation.updatedAt) ?? .distantPast
            let dayStart = calendar.startOfDay(for: date)
            let key = dayKeyFormatter.string(from: dayStart)
            var bucket = buckets[key] ?? (dayStart, [])
            bucket.items.append(conversation)
            buckets[key] = bucket
        }

        return buckets.keys.sorted(by: >).compactMap { key in
            guard var bucket = buckets[key] else { return nil }
            bucket.items.sort { lhs, rhs in
                let lhsStarred = starredConversationIDs.contains(lhs.conversationId)
                let rhsStarred = starredConversationIDs.contains(rhs.conversationId)
                if lhsStarred != rhsStarred {
                    return lhsStarred && !rhsStarred
                }
                let lhsDate = ISO8601Codec.date(from: lhs.updatedAt) ?? .distantPast
                let rhsDate = ISO8601Codec.date(from: rhs.updatedAt) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.conversationId > rhs.conversationId
            }
            return ChatConversationDayGroup(
                dayKey: key,
                dayStart: bucket.dayStart,
                conversations: bucket.items
            )
        }
    }

    public static func title(for dayStart: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(dayStart) {
            return "今天"
        }
        if calendar.isDateInYesterday(dayStart) {
            return "昨天"
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        if calendar.component(.year, from: dayStart) == calendar.component(.year, from: now) {
            formatter.dateFormat = "M月d日 EEE"
        } else {
            formatter.dateFormat = "yyyy年M月d日 EEE"
        }
        return formatter.string(from: dayStart)
    }
}

public enum ChatConversationTurnPresentation {
    /// Collapse markdown/noise into a single-line preview for catalog labels.
    public static func preview(from content: String, limit: Int) -> String {
        var text = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Strip fenced code blocks coarsely.
        while let start = text.range(of: "```"),
              let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            text.replaceSubrange(start.lowerBound..<end.upperBound, with: " ")
        }

        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var value = String(line).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("###### ") { value = String(value.dropFirst(7)) }
                else if value.hasPrefix("##### ") { value = String(value.dropFirst(6)) }
                else if value.hasPrefix("#### ") { value = String(value.dropFirst(5)) }
                else if value.hasPrefix("### ") { value = String(value.dropFirst(4)) }
                else if value.hasPrefix("## ") { value = String(value.dropFirst(3)) }
                else if value.hasPrefix("# ") { value = String(value.dropFirst(2)) }
                else if value.hasPrefix("> ") { value = String(value.dropFirst(2)) }
                else if value.hasPrefix("- ") || value.hasPrefix("* ") || value.hasPrefix("+ ") {
                    value = String(value.dropFirst(2))
                }
                value = value
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "__", with: "")
                    .replacingOccurrences(of: "`", with: "")
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        let joined = lines.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !joined.isEmpty else { return "（空消息）" }
        if joined.count <= limit { return joined }
        let end = joined.index(joined.startIndex, offsetBy: max(0, limit - 1))
        return String(joined[..<end]) + "…"
    }
}

public extension ChatConversationSourceTurn {
    var userMessage: ChatConversationSourceMessage? {
        messages.first(where: { $0.role == .user }) ?? messages.first
    }

    var assistantMessage: ChatConversationSourceMessage? {
        messages.first(where: { $0.role == .assistant })
    }

    var catalogTitle: String {
        guard let userMessage else { return "（空轮次）" }
        return ChatConversationTurnPresentation.preview(from: userMessage.content, limit: 36)
    }

    var catalogSubtitle: String {
        if let assistantMessage {
            return ChatConversationTurnPresentation.preview(from: assistantMessage.content, limit: 48)
        }
        return "尚无回复"
    }
}
