import Foundation

public enum ChatConversationArchiveReaderError: Error, Sendable, Equatable {
    case missingArchiveIndex(String)
    case invalidArchiveIndex(String)
}

public struct ChatConversationArchiveReader: Sendable {
    public init() {}

    public func read(
        archiveRoot: URL,
        processedRevisions: [ChatConversationProcessedRevision]
    ) throws -> [ChatConversationArchiveSummary] {
        let indexURL = archiveRoot.appendingPathComponent("_archive-index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            throw ChatConversationArchiveReaderError.missingArchiveIndex(indexURL.path)
        }

        let manifest: [String: ManifestEntry]
        do {
            manifest = try JSONDecoder().decode([String: ManifestEntry].self, from: Data(contentsOf: indexURL))
        } catch {
            throw ChatConversationArchiveReaderError.invalidArchiveIndex(indexURL.path)
        }

        let revisionsByMessage = Set(processedRevisions.map {
            RevisionKey(conversationId: $0.conversationId, messageId: $0.messageId, contentHash: $0.contentHash)
        })
        return manifest
            .map { conversationId, entry in
                summary(
                    conversationId: conversationId,
                    entry: entry,
                    archiveRoot: archiveRoot,
                    processedRevisions: revisionsByMessage
                )
            }
            .sorted { left, right in
                (left.createdAt, left.conversationId) < (right.createdAt, right.conversationId)
            }
    }

    private func summary(
        conversationId: String,
        entry: ManifestEntry,
        archiveRoot: URL,
        processedRevisions: Set<RevisionKey>
    ) -> ChatConversationArchiveSummary {
        let fallbackTitle = title(from: entry.lastSnapshotFilename)
        guard let dataFilename = entry.lastDataFilename,
              let dataURL = dataURL(for: dataFilename, under: archiveRoot),
              FileManager.default.fileExists(atPath: dataURL.path) else {
            return unavailableSummary(
                conversationId: conversationId,
                title: fallbackTitle,
                entry: entry,
                issue: .missingStructuredData
            )
        }

        let archive: ChatConversationArchiveFile
        do {
            archive = try JSONDecoder().decode(ChatConversationArchiveFile.self, from: Data(contentsOf: dataURL))
        } catch {
            return unavailableSummary(
                conversationId: conversationId,
                title: fallbackTitle,
                entry: entry,
                issue: .invalidStructuredData
            )
        }
        guard archive.conversationId == conversationId else {
            return unavailableSummary(
                conversationId: conversationId,
                title: archive.title,
                entry: entry,
                issue: .mismatchedConversationIdentity
            )
        }

        let pendingMessageIDs = archive.messages.compactMap { message -> String? in
            let key = RevisionKey(
                conversationId: conversationId,
                messageId: message.id,
                contentHash: ContentHasher.hash(message.content)
            )
            return processedRevisions.contains(key) ? nil : message.id
        }
        let pendingMessageCount = pendingMessageIDs.count
        let processedMessageCount = archive.messages.count - pendingMessageCount
        let status: ChatConversationProcessingStatus
        if pendingMessageCount == 0 {
            status = .processed
        } else if processedMessageCount == 0 {
            status = .pending
        } else {
            status = .partiallyProcessed
        }
        return ChatConversationArchiveSummary(
            conversationId: conversationId,
            title: archive.title,
            sourceURL: archive.sourceURL,
            createdAt: archive.createdAt,
            updatedAt: archive.updatedAt,
            status: status,
            processedMessageCount: processedMessageCount,
            pendingMessageCount: pendingMessageCount,
            pendingMessageIDs: pendingMessageIDs,
            issue: nil
        )
    }

    private func unavailableSummary(
        conversationId: String,
        title: String,
        entry: ManifestEntry,
        issue: ChatConversationArchiveIssue
    ) -> ChatConversationArchiveSummary {
        ChatConversationArchiveSummary(
            conversationId: conversationId,
            title: title,
            sourceURL: nil,
            createdAt: entry.createdAt,
            updatedAt: entry.lastActivityAt,
            status: .needsReexport,
            processedMessageCount: 0,
            pendingMessageCount: 0,
            pendingMessageIDs: [],
            issue: issue
        )
    }

    private func dataURL(for filename: String, under archiveRoot: URL) -> URL? {
        let candidate = archiveRoot.appendingPathComponent(filename).standardizedFileURL
        let root = archiveRoot.standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }

    private func title(from snapshotFilename: String) -> String {
        let withoutDate: String
        if let separator = snapshotFilename.range(of: "--") {
            withoutDate = String(snapshotFilename[separator.upperBound...])
        } else {
            withoutDate = snapshotFilename
        }
        return withoutDate.replacingOccurrences(of: ".md", with: "")
    }
}

private extension ChatConversationArchiveReader {
    struct ManifestEntry: Decodable {
        var createdAt: String
        var lastActivityAt: String
        var lastSnapshotFilename: String
        var lastDataFilename: String?
    }

    struct RevisionKey: Hashable {
        var conversationId: String
        var messageId: String
        var contentHash: String
    }
}
