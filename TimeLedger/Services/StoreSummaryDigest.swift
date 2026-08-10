import CryptoKit
import Foundation
import SwiftData

struct StoreSummaryDigest: Equatable, Sendable {
    let hex: String
}

/// 迁移门禁使用的脱敏数据摘要：文本、路径、缩略图只保留哈希，ID 与时间保留原值。
@MainActor
enum StoreSummaryDigestBuilder {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()

    static func currentDigest(modelContext: ModelContext) throws -> StoreSummaryDigest {
        var rows: [String] = []

        let projects = try modelContext.fetch(FetchDescriptor<Project>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for project in projects {
            rows.append([
                "project",
                project.id.uuidString.lowercased(),
                hash(project.name),
                hash(project.categoryName),
                hash(project.emoji),
                hash(project.colorHex),
                String(project.sortOrder),
                String(project.isArchived),
                date(project.createdAt),
                date(project.updatedAt),
            ].joined(separator: "|"))
        }

        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
        let documentByOwner = Dictionary(
            uniqueKeysWithValues: documents.map { ($0.ownerKey, $0) }
        )
        for entry in entries {
            let note = documentByOwner[
                ContentDocument.key(ownerID: entry.id, ownerKind: .timeEntry)
            ]?.body ?? ""
            rows.append([
                "timeEntry",
                entry.id.uuidString.lowercased(),
                entry.projectId.uuidString.lowercased(),
                hash(entry.projectNameSnapshot),
                hash(entry.categoryNameSnapshot),
                date(entry.startAt),
                date(entry.endAt),
                entry.status,
                hash(note),
                date(entry.createdAt),
                date(entry.updatedAt),
            ].joined(separator: "|"))
        }

        let journals = try modelContext.fetch(FetchDescriptor<JournalEntry>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let journalLinks = try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
        let linkByJournalID = Dictionary(
            uniqueKeysWithValues: journalLinks.map { ($0.journalEntryID, $0) }
        )
        for journal in journals {
            let body = documentByOwner[
                ContentDocument.key(ownerID: journal.id, ownerKind: .journalEntry)
            ]?.body ?? ""
            let link = linkByJournalID[journal.id]
            rows.append([
                "thought",
                journal.id.uuidString.lowercased(),
                date(journal.capturedAt),
                date(journal.anchorAt),
                hash(body),
                optionalID(link?.timeEntryID),
                link?.linkSource ?? ThoughtLinkSource.none.rawValue,
                date(journal.createdAt),
                date(journal.updatedAt),
                String(journal.isFavorite),
            ].joined(separator: "|"))
        }

        let moments = try modelContext.fetch(FetchDescriptor<MediaMoment>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for moment in moments {
            rows.append([
                "media",
                moment.id.uuidString.lowercased(),
                moment.mediaType,
                date(moment.capturedAt),
                date(moment.anchorAt),
                optionalID(moment.linkedEntryId),
                moment.linkSource,
                moment.requestedStorage,
                moment.storedLocation,
                hash(moment.appRelativePath),
                hash(moment.photosAssetIdentifier),
                hash(moment.pendingRelativePath),
                hash(moment.sourceTemporaryPath),
                hash(moment.thumbnailData),
                formatDouble(moment.durationSeconds),
                moment.status,
                hash(moment.lastError),
                moment.originalAvailability,
                date(moment.createdAt),
                date(moment.updatedAt),
            ].joined(separator: "|"))
        }

        let attachments = try modelContext.fetch(FetchDescriptor<ContentAttachment>())
            .sorted { $0.mediaMomentID.uuidString < $1.mediaMomentID.uuidString }
        let documentByID = Dictionary(
            uniqueKeysWithValues: documents.map { ($0.id, $0) }
        )
        for attachment in attachments {
            guard let document = documentByID[attachment.contentDocumentID] else { continue }
            rows.append([
                "mediaAttachment",
                attachment.mediaMomentID.uuidString.lowercased(),
                document.ownerID.uuidString.lowercased(),
                document.ownerKind,
                String(attachment.sortOrder),
            ].joined(separator: "|"))
        }

        let cursors = try modelContext.fetch(FetchDescriptor<TimeCursor>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for cursor in cursors {
            rows.append([
                "cursor",
                cursor.id.uuidString.lowercased(),
                date(cursor.cursorAt),
                date(cursor.updatedAt),
            ].joined(separator: "|"))
        }

        let settings = try modelContext.fetch(FetchDescriptor<AppSettings>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for setting in settings {
            rows.append([
                "settings",
                setting.id.uuidString.lowercased(),
                String(setting.longUnclassifiedThresholdMinutes),
                String(setting.exportOnlyConfirmed),
                String(setting.includeDraftInTodaySummary),
                setting.mediaStoragePreference,
            ].joined(separator: "|"))
        }

        let actionItems = try modelContext.fetch(FetchDescriptor<ActionItem>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for item in actionItems {
            rows.append([
                "actionItem",
                item.id.uuidString.lowercased(),
                hash(item.title),
                String(item.sortOrder),
                String(item.isArchived),
                optionalDate(item.activeCycleStartedAt),
                date(item.createdAt),
                date(item.updatedAt),
            ].joined(separator: "|"))
        }

        let completions = try modelContext.fetch(FetchDescriptor<ActionCompletion>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for completion in completions {
            rows.append([
                "actionCompletion",
                completion.id.uuidString.lowercased(),
                completion.actionItemId.uuidString.lowercased(),
                hash(completion.actionTitleSnapshot),
                date(completion.completedAt),
                date(completion.dayStart),
                optionalID(completion.linkedEntryId),
                date(completion.createdAt),
                date(completion.updatedAt),
            ].joined(separator: "|"))
        }

        return makeDigest(rows: rows)
    }

    static func makeDigest(rows: [String]) -> StoreSummaryDigest {
        let canonical = rows.sorted().joined(separator: "\n") + "\n"
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return StoreSummaryDigest(
            hex: digest.map { String(format: "%02x", $0) }.joined()
        )
    }

    static func hash(_ text: String?) -> String {
        let value = text ?? ""
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ data: Data?) -> String {
        let value = data ?? Data()
        let digest = SHA256.hash(data: value)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func date(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func optionalDate(_ date: Date?) -> String {
        date.map { self.date($0) } ?? "nil"
    }

    static func optionalID(_ id: UUID?) -> String {
        id.map { $0.uuidString.lowercased() } ?? "nil"
    }

    static func formatDouble(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
