import Foundation

/// Stable identity keys for import idempotency.
public enum DeduplicationKey: Hashable, Sendable, Codable {
    case external(source: ContextSource, externalId: String)
    case fallback(source: ContextSource, sourcePath: String, sourceLine: Int, contentHash: String)

    public var stringValue: String {
        switch self {
        case let .external(source, externalId):
            return "ext:\(source.rawValue):\(externalId)"
        case let .fallback(source, sourcePath, sourceLine, contentHash):
            return "fb:\(source.rawValue):\(sourcePath):\(sourceLine):\(contentHash)"
        }
    }

    public static func preferred(
        source: ContextSource,
        externalId: String?
    ) -> DeduplicationKey? {
        guard let externalId, !externalId.isEmpty else { return nil }
        return .external(source: source, externalId: externalId)
    }

    public static func resolve(
        source: ContextSource,
        externalId: String?,
        sourcePath: String?,
        sourceLine: Int?,
        contentHash: String
    ) -> DeduplicationKey {
        if let key = preferred(source: source, externalId: externalId) {
            return key
        }
        return .fallback(
            source: source,
            sourcePath: sourcePath ?? "",
            sourceLine: sourceLine ?? -1,
            contentHash: contentHash
        )
    }
}

/// In-memory import index for testing and pure logic; storage backends plug in later.
public struct ImportDeduper: Sendable {
    private var seen: Set<String>

    public init(seen: Set<String> = []) {
        self.seen = seen
    }

    public var count: Int { seen.count }

    /// Returns true if this is the first time the key is registered.
    @discardableResult
    public mutating func register(_ key: DeduplicationKey) -> Bool {
        let value = key.stringValue
        if seen.contains(value) {
            return false
        }
        seen.insert(value)
        return true
    }

    public func contains(_ key: DeduplicationKey) -> Bool {
        seen.contains(key.stringValue)
    }
}
