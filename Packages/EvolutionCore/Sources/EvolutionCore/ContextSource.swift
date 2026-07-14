import Foundation

public enum ContextSource: String, Codable, Sendable, CaseIterable, Hashable {
    case codex
    case claude
    case chatgpt
    case git
    case browser
}
