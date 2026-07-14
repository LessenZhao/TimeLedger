import Foundation

struct ThoughtDraftStore {
    enum Key: String {
        case quickCapture = "thought.draft.quickCapture"
        case addToEntry = "thought.draft.addToEntry"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(_ key: Key) -> String {
        defaults.string(forKey: key.rawValue) ?? ""
    }

    func save(_ text: String, for key: Key) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clear(key)
        } else {
            defaults.set(text, forKey: key.rawValue)
        }
    }

    func clear(_ key: Key) {
        defaults.removeObject(forKey: key.rawValue)
    }
}
