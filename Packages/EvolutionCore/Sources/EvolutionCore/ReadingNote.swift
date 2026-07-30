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
    public var sourceHash: String
    public var visibleTextHash: String
    public var rendererVersion: String
    public var selectorVersion: String
    public var offsetUnit: String
    public var positionStart: Int
    public var positionEnd: Int
    public var exact: String
    public var prefix: String
    public var suffix: String

    public init(
        conversationId: String,
        messageId: String,
        contentHash: String,
        locationUTF16: Int,
        lengthUTF16: Int,
        textHash: String,
        sourceHash: String? = nil,
        visibleTextHash: String? = nil,
        rendererVersion: String = "markdown-it-14.1.0+recogito-4.2.5",
        selectorVersion: String = "text-position-quote-v1",
        offsetUnit: String = "utf16",
        exact: String = "",
        prefix: String = "",
        suffix: String = ""
    ) {
        self.conversationId = conversationId
        self.messageId = messageId
        self.contentHash = contentHash
        self.locationUTF16 = locationUTF16
        self.lengthUTF16 = lengthUTF16
        self.textHash = textHash
        self.sourceHash = sourceHash ?? contentHash
        self.visibleTextHash = visibleTextHash ?? textHash
        self.rendererVersion = rendererVersion
        self.selectorVersion = selectorVersion
        self.offsetUnit = offsetUnit
        self.positionStart = locationUTF16
        self.positionEnd = locationUTF16 + lengthUTF16
        self.exact = exact
        self.prefix = prefix
        self.suffix = suffix
    }
}

public struct FormalAssetSpanAnchor: Codable, Sendable, Hashable {
    public var assetId: String
    public var versionId: String
    public var textHash: String
    public var locationUTF16: Int
    public var lengthUTF16: Int
    public var quoteHash: String
    public var sourceHash: String
    public var visibleTextHash: String
    public var rendererVersion: String
    public var selectorVersion: String
    public var offsetUnit: String
    public var positionStart: Int
    public var positionEnd: Int
    public var exact: String
    public var prefix: String
    public var suffix: String

    public init(
        assetId: String,
        versionId: String,
        textHash: String,
        locationUTF16: Int,
        lengthUTF16: Int,
        quoteHash: String,
        sourceHash: String? = nil,
        visibleTextHash: String? = nil,
        rendererVersion: String = "markdown-it-14.1.0+recogito-4.2.5",
        selectorVersion: String = "text-position-quote-v1",
        offsetUnit: String = "utf16",
        exact: String = "",
        prefix: String = "",
        suffix: String = ""
    ) {
        self.assetId = assetId
        self.versionId = versionId
        self.textHash = textHash
        self.locationUTF16 = locationUTF16
        self.lengthUTF16 = lengthUTF16
        self.quoteHash = quoteHash
        self.sourceHash = sourceHash ?? textHash
        self.visibleTextHash = visibleTextHash ?? textHash
        self.rendererVersion = rendererVersion
        self.selectorVersion = selectorVersion
        self.offsetUnit = offsetUnit
        self.positionStart = locationUTF16
        self.positionEnd = locationUTF16 + lengthUTF16
        self.exact = exact
        self.prefix = prefix
        self.suffix = suffix
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
        textHash: String,
        sourceHash: String? = nil,
        visibleTextHash: String? = nil,
        exact: String = "",
        prefix: String = "",
        suffix: String = ""
    ) throws -> ReadingNoteAnchor {
        guard lengthUTF16 > 0 else { throw ReadingNoteError.emptyRange }
        return .sourceMessageSpan(
            SourceMessageSpanAnchor(
                conversationId: conversationId,
                messageId: messageId,
                contentHash: contentHash,
                locationUTF16: locationUTF16,
                lengthUTF16: lengthUTF16,
                textHash: textHash,
                sourceHash: sourceHash,
                visibleTextHash: visibleTextHash,
                exact: exact,
                prefix: prefix,
                suffix: suffix
            )
        )
    }

    public static func formalAnchor(
        assetId: String,
        versionId: String,
        textHash: String,
        locationUTF16: Int,
        lengthUTF16: Int,
        quoteHash: String,
        sourceHash: String? = nil,
        visibleTextHash: String? = nil,
        exact: String = "",
        prefix: String = "",
        suffix: String = ""
    ) throws -> ReadingNoteAnchor {
        guard lengthUTF16 > 0 else { throw ReadingNoteError.emptyRange }
        return .formalAssetSpan(
            FormalAssetSpanAnchor(
                assetId: assetId,
                versionId: versionId,
                textHash: textHash,
                locationUTF16: locationUTF16,
                lengthUTF16: lengthUTF16,
                quoteHash: quoteHash,
                sourceHash: sourceHash,
                visibleTextHash: visibleTextHash,
                exact: exact,
                prefix: prefix,
                suffix: suffix
            )
        )
    }
}

// MARK: - Document + file IO

public struct ReadingNotesDocument: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var notes: [ReadingNote]

    public static let currentSchemaVersion = 2

    public static var empty: ReadingNotesDocument {
        ReadingNotesDocument(schemaVersion: currentSchemaVersion, notes: [])
    }

    public init(schemaVersion: Int = currentSchemaVersion, notes: [ReadingNote] = []) {
        self.schemaVersion = schemaVersion
        self.notes = notes
    }
}

/// Atomic load/save for `records/chatgpt-reading-notes-v2.json`.
public enum ReadingNotesFileStore {
    public static func load(from url: URL, fileManager: FileManager = .default) throws -> ReadingNotesDocument {
        guard fileManager.fileExists(atPath: url.path) else {
            return .empty
        }
        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(ReadingNotesDocument.self, from: data)
        guard document.schemaVersion == ReadingNotesDocument.currentSchemaVersion else {
            throw ReadingNotesFileStoreError.unsupportedSchema(document.schemaVersion)
        }
        return document
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

public enum ReadingNotesFileStoreError: Error, Sendable, Equatable {
    case unsupportedSchema(Int)
}
