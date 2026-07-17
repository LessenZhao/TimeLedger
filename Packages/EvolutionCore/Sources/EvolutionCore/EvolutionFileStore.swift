import Foundation

public protocol EvolutionDocumentStore: Sendable {
    func load() throws -> EvolutionLedgerDocument
    func save(_ document: EvolutionLedgerDocument) throws
}

public struct JSONEvolutionDocumentStore: EvolutionDocumentStore, @unchecked Sendable {
    public let layout: EvolutionLedgerLayout
    private let fileManager: FileManager

    public init(layout: EvolutionLedgerLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public func load() throws -> EvolutionLedgerDocument {
        guard fileManager.fileExists(atPath: layout.ledgerFileURL.path) else {
            return EvolutionLedgerDocument.empty
        }

        let data = try Data(contentsOf: layout.ledgerFileURL)
        return try ISO8601Codec.decoder.decode(EvolutionLedgerDocument.self, from: data)
    }

    public func save(_ document: EvolutionLedgerDocument) throws {
        try layout.ensureDirectories(fileManager: fileManager)
        let data = try ISO8601Codec.encoder.encode(document.canonicalized())
        try data.write(to: layout.ledgerFileURL, options: .atomic)
    }
}

private extension EvolutionLedgerDocument {
    static var empty: EvolutionLedgerDocument {
        EvolutionLedgerDocument(
            schemaVersion: EvolutionSchema.current,
            projects: [],
            days: [],
            nodes: [],
            annotations: [],
            sourceSessions: [],
            worktreeEvidence: [],
            imports: [],
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func canonicalized() -> EvolutionLedgerDocument {
        var result = self
        result.projects.sort {
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }
        result.days.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }
        result.nodes.sort(by: EvolutionOrdering.nodes)
        result.annotations.sort(by: EvolutionOrdering.annotations)
        result.sourceSessions.sort { $0.id < $1.id }
        result.worktreeEvidence.sort { $0.id < $1.id }
        result.imports.sort {
            if $0.importedAt != $1.importedAt { return $0.importedAt < $1.importedAt }
            return $0.id < $1.id
        }
        return result
    }
}

enum EvolutionOrdering {
    static func nodes(_ lhs: EvolutionNode, _ rhs: EvolutionNode) -> Bool {
        if lhs.happenedAt != rhs.happenedAt { return lhs.happenedAt < rhs.happenedAt }
        if lhs.recognizedAt != rhs.recognizedAt { return lhs.recognizedAt < rhs.recognizedAt }
        return lhs.id < rhs.id
    }

    static func annotations(_ lhs: UserAnnotation, _ rhs: UserAnnotation) -> Bool {
        if lhs.recognizedAt != rhs.recognizedAt { return lhs.recognizedAt < rhs.recognizedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id < rhs.id
    }
}
