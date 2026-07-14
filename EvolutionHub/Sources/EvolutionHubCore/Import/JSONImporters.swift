import Foundation
import EvolutionCore

enum TimeLedgerExportDTO {
    struct Root: Decodable {
        var version: Int
        var exportedAt: String?
        var projects: [Project]
        var timeEntries: [TimeEntry]
        var thoughtNotes: [ThoughtNote]
    }

    struct Project: Decodable {
        var id: String
        var name: String
        var categoryName: String
    }

    struct TimeEntry: Decodable {
        var id: String
        var projectId: String
        var projectNameSnapshot: String
        var categoryNameSnapshot: String
        var startAt: String
        var endAt: String
        var note: String
        var status: String
        var createdAt: String
        var updatedAt: String
    }

    struct ThoughtNote: Decodable {
        var id: String
        var body: String
        var capturedAt: String
        var anchorAt: String
        var linkedEntryId: String
        var linkSource: String
        var createdAt: String
        var updatedAt: String
    }
}

public enum TimeLedgerJSONImporter {
    public static func importFromData(_ data: Data) throws -> (
        projects: [ImportedProject],
        entries: [ImportedTimeEntry],
        thoughts: [ImportedThoughtNote]
    ) {
        let root = try JSONDecoder().decode(TimeLedgerExportDTO.Root.self, from: data)
        let projects = root.projects.map {
            ImportedProject(id: $0.id, name: $0.name, categoryName: $0.categoryName)
        }
        let entries = try root.timeEntries.map { dto -> ImportedTimeEntry in
            ImportedTimeEntry(
                id: dto.id,
                projectId: dto.projectId,
                projectNameSnapshot: dto.projectNameSnapshot,
                categoryNameSnapshot: dto.categoryNameSnapshot,
                startAt: try parseDate(dto.startAt),
                endAt: try parseDate(dto.endAt),
                note: dto.note,
                status: dto.status,
                createdAt: try parseDate(dto.createdAt),
                updatedAt: try parseDate(dto.updatedAt)
            )
        }
        let thoughts = try root.thoughtNotes.map { dto -> ImportedThoughtNote in
            let linked = dto.linkedEntryId.isEmpty ? nil : dto.linkedEntryId
            return ImportedThoughtNote(
                id: dto.id,
                body: dto.body,
                capturedAt: try parseDate(dto.capturedAt),
                anchorAt: try parseDate(dto.anchorAt),
                linkedEntryId: linked,
                linkSource: dto.linkSource,
                createdAt: try parseDate(dto.createdAt),
                updatedAt: try parseDate(dto.updatedAt)
            )
        }
        return (projects, entries, thoughts)
    }

    public static func importFromFile(at url: URL) throws -> (
        projects: [ImportedProject],
        entries: [ImportedTimeEntry],
        thoughts: [ImportedThoughtNote]
    ) {
        let data = try Data(contentsOf: url)
        return try importFromData(data)
    }

    private static func parseDate(_ raw: String) throws -> Date {
        if let date = ISO8601Codec.date(from: raw) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: raw) {
            return date
        }
        throw ImportError.invalidDate(raw)
    }
}

public enum ContextEventJSONImporter {
    public static func importFromData(_ data: Data) throws -> [ContextEvent] {
        try ISO8601Codec.decoder.decode([ContextEvent].self, from: data)
    }

    public static func importFromFile(at url: URL) throws -> [ContextEvent] {
        try importFromData(Data(contentsOf: url))
    }
}

public enum ImportError: Error, LocalizedError, Equatable {
    case invalidDate(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDate(let raw):
            return "无法解析日期: \(raw)"
        }
    }
}
