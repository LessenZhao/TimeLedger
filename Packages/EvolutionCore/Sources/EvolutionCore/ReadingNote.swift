import Foundation

// MARK: - Anchors

/// Exclusive anchor for a reading note: either source message span or formal asset span.
public enum ReadingNoteAnchor: Codable, Sendable, Hashable {
    case sourceMessageSpan(SourceMessageSpanAnchor)
    case formalAssetSpan(FormalAssetSpanAnchor)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum AnchorType: String, Codable {
        case sourceMessageSpan
        case formalAssetSpan
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(AnchorType.self, forKey: .type)
        switch type {
        case .sourceMessageSpan:
            self = .sourceMessageSpan(try SourceMessageSpanAnchor(from: decoder))
        case .formalAssetSpan:
            self = .formalAssetSpan(try FormalAssetSpanAnchor(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sourceMessageSpan(let anchor):
            try container.encode(AnchorType.sourceMessageSpan, forKey: .type)
            try anchor.encode(to: encoder)
        case .formalAssetSpan(let anchor):
            try container.encode(AnchorType.formalAssetSpan, forKey: .type)
            try anchor.encode(to: encoder)
        }
    }
}

public struct SourceMessageSpanAnchor: Codable, Sendable, Hashable {
    public var conversationId: String
    public var messageId: String
    public var contentHash: String
    public var locationUTF16: Int
    public var lengthUTF16: Int
    public var textHash: String

    public init(
        conversationId: String,
        messageId: String,
        contentHash: String,
        locationUTF16: Int,
        lengthUTF16: Int,
        textHash: String
    ) {
        self.conversationId = conversationId
        self.messageId = messageId
        self.contentHash = contentHash
        self.locationUTF16 = locationUTF16
        self.lengthUTF16 = lengthUTF16
        self.textHash = textHash
    }
}

public struct FormalAssetSpanAnchor: Codable, Sendable, Hashable {
    public var assetId: String
    public var versionId: String
    public var textHash: String
    public var locationUTF16: Int
    public var lengthUTF16: Int
    public var quoteHash: String

    public init(
        assetId: String,
        versionId: String,
        textHash: String,
        locationUTF16: Int,
        lengthUTF16: Int,
        quoteHash: String
    ) {
        self.assetId = assetId
        self.versionId = versionId
        self.textHash = textHash
        self.locationUTF16 = locationUTF16
        self.lengthUTF16 = lengthUTF16
        self.quoteHash = quoteHash
    }
}

// MARK: - Note

public enum ReadingNoteError: Error, Sendable, Equatable {
    case emptyRange
    case emptyQuote
}

/// Personal reading note / highlight. Parallel to formal study assets; never promoted into ledger assets.
public struct ReadingNote: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var body: String?
    public var isHighlight: Bool
    public var quoteSnapshot: String
    public var createdAt: String
    public var updatedAt: String
    public var anchor: ReadingNoteAnchor

    public init(
        id: String,
        body: String? = nil,
        isHighlight: Bool,
        quoteSnapshot: String,
        createdAt: String,
        updatedAt: String,
        anchor: ReadingNoteAnchor
    ) {
        self.id = id
        self.body = body
        self.isHighlight = isHighlight
        self.quoteSnapshot = quoteSnapshot
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.anchor = anchor
    }

    public static func make(
        id: String = UUID().uuidString.lowercased(),
        body: String? = nil,
        isHighlight: Bool,
        quoteSnapshot: String,
        anchor: ReadingNoteAnchor,
        now: Date = Date()
    ) throws -> ReadingNote {
        let quote = quoteSnapshot
        guard !quote.isEmpty else { throw ReadingNoteError.emptyQuote }
        switch anchor {
        case .sourceMessageSpan(let span):
            guard span.lengthUTF16 > 0 else { throw ReadingNoteError.emptyRange }
        case .formalAssetSpan(let span):
            guard span.lengthUTF16 > 0 else { throw ReadingNoteError.emptyRange }
        }
        let stamp = ISO8601Codec.string(from: now)
        let normalizedBody = body.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let finalBody = (normalizedBody?.isEmpty == true) ? nil : normalizedBody
        return ReadingNote(
            id: id,
            body: finalBody,
            isHighlight: isHighlight,
            quoteSnapshot: quote,
            createdAt: stamp,
            updatedAt: stamp,
            anchor: anchor
        )
    }

    public static func sourceAnchor(
        conversationId: String,
        messageId: String,
        contentHash: String,
        locationUTF16: Int,
        lengthUTF16: Int,
        textHash: String
    ) throws -> ReadingNoteAnchor {
        guard lengthUTF16 > 0 else { throw ReadingNoteError.emptyRange }
        return .sourceMessageSpan(
            SourceMessageSpanAnchor(
                conversationId: conversationId,
                messageId: messageId,
                contentHash: contentHash,
                locationUTF16: locationUTF16,
                lengthUTF16: lengthUTF16,
                textHash: textHash
            )
        )
    }

    public static func formalAnchor(
        assetId: String,
        versionId: String,
        textHash: String,
        locationUTF16: Int,
        lengthUTF16: Int,
        quoteHash: String
    ) throws -> ReadingNoteAnchor {
        guard lengthUTF16 > 0 else { throw ReadingNoteError.emptyRange }
        return .formalAssetSpan(
            FormalAssetSpanAnchor(
                assetId: assetId,
                versionId: versionId,
                textHash: textHash,
                locationUTF16: locationUTF16,
                lengthUTF16: lengthUTF16,
                quoteHash: quoteHash
            )
        )
    }
}

// MARK: - Document + file IO

public struct ReadingNotesDocument: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var notes: [ReadingNote]

    public static let currentSchemaVersion = 1

    public static var empty: ReadingNotesDocument {
        ReadingNotesDocument(schemaVersion: currentSchemaVersion, notes: [])
    }

    public init(schemaVersion: Int = currentSchemaVersion, notes: [ReadingNote] = []) {
        self.schemaVersion = schemaVersion
        self.notes = notes
    }
}

/// Atomic load/save for `records/chatgpt-reading-notes.json`. Bad/missing file → empty.
public enum ReadingNotesFileStore {
    public static func load(from url: URL, fileManager: FileManager = .default) -> ReadingNotesDocument {
        guard fileManager.fileExists(atPath: url.path) else {
            return .empty
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ReadingNotesDocument.self, from: data)
        } catch {
            return .empty
        }
    }

    public static func save(
        _ document: ReadingNotesDocument,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(document)
        try data.write(to: url, options: .atomic)
    }
}
