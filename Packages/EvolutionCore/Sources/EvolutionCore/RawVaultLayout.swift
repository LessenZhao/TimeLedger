import Foundation

/// Canonical layout under Application Support / configured root.
public struct RawVaultLayout: Sendable, Hashable {
    public var rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public static func defaultApplicationSupport(fileManager: FileManager = .default) -> RawVaultLayout {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return RawVaultLayout(
            rootURL: base.appendingPathComponent("PersonalEvolutionEngine", isDirectory: true)
        )
    }

    public var rawURL: URL { rootURL.appendingPathComponent("raw", isDirectory: true) }
    public var normalizedURL: URL { rootURL.appendingPathComponent("normalized", isDirectory: true) }
    public var databaseURL: URL { rootURL.appendingPathComponent("database", isDirectory: true) }
    public var syncURL: URL { rootURL.appendingPathComponent("sync", isDirectory: true) }
    public var configURL: URL { rootURL.appendingPathComponent("config", isDirectory: true) }
    public var logsURL: URL { rootURL.appendingPathComponent("logs", isDirectory: true) }

    public func rawSourceURL(_ source: ContextSource) -> URL {
        rawURL.appendingPathComponent(source.rawValue, isDirectory: true)
    }

    public var requiredDirectories: [URL] {
        [
            rawURL,
            rawSourceURL(.codex),
            rawSourceURL(.claude),
            rawSourceURL(.chatgpt),
            normalizedURL,
            databaseURL,
            syncURL,
            configURL,
            logsURL
        ]
    }

    public func ensureDirectories(fileManager: FileManager = .default) throws {
        for url in requiredDirectories {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
