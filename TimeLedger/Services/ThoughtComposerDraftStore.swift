import Foundation

nonisolated enum ThoughtComposerDraftStoreError: LocalizedError {
    case invalidPhoto
    case tooManyAttachments

    var errorDescription: String? {
        switch self {
        case .invalidPhoto:
            "无法读取所选照片。"
        case .tooManyAttachments:
            "一条思考最多添加 9 个附件。"
        }
    }
}

nonisolated struct ThoughtComposerDraftAttachment: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let mediaType: String
    let sourceOrigin: String?
    let capturedAt: Date
    let durationSeconds: Double
    let originalFilename: String
    let thumbnailData: Data

    var kind: MediaKind {
        MediaKind(rawValue: mediaType) ?? .photo
    }

    var cameFromPhotoLibrary: Bool {
        sourceOrigin == "photoLibrary"
    }
}

nonisolated struct ThoughtComposerDraft: Codable, Equatable, Sendable {
    var id: UUID
    var body: String
    var anchorAt: Date?
    var attachments: [ThoughtComposerDraftAttachment]

    static var empty: ThoughtComposerDraft {
        ThoughtComposerDraft(
            id: UUID(),
            body: "",
            anchorAt: nil,
            attachments: []
        )
    }

    var hasContent: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
    }
}

nonisolated struct ThoughtComposerDraftStore: Sendable {
    static let maximumAttachmentCount = 9

    let rootURL: URL

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.rootURL = applicationSupport
                .appending(path: "ThoughtComposerDraft", directoryHint: .isDirectory)
        }
    }

    private var originalsURL: URL {
        rootURL.appending(path: "Originals", directoryHint: .isDirectory)
    }

    private var manifestURL: URL {
        rootURL.appending(path: "draft.json")
    }

    func load() throws -> ThoughtComposerDraft {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(ThoughtComposerDraft.self, from: data)
    }

    @discardableResult
    func updateBody(_ body: String, now: Date = Date()) throws -> ThoughtComposerDraft {
        var draft = try load()
        let wasEmpty = !draft.hasContent
        draft.body = body
        if wasEmpty && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.anchorAt = now
        } else if !draft.hasContent {
            draft.anchorAt = nil
        }
        try save(draft)
        return draft
    }

    func addCapture(_ capture: CameraCapture) async throws -> ThoughtComposerDraft {
        try await addCapture(capture, sourceOrigin: "camera")
    }

    func addLibraryCapture(_ capture: CameraCapture) async throws -> ThoughtComposerDraft {
        try await addCapture(capture, sourceOrigin: "photoLibrary")
    }

    private func addCapture(
        _ capture: CameraCapture,
        sourceOrigin: String
    ) async throws -> ThoughtComposerDraft {
        let rootURL = rootURL
        return try await Task.detached(priority: .userInitiated) {
            let store = ThoughtComposerDraftStore(rootURL: rootURL)
            let fileExtension = capture.sourceURL.pathExtension.isEmpty
                ? (capture.kind == .photo ? "jpg" : "mov")
                : capture.sourceURL.pathExtension.lowercased()
            return try store.stageOriginal(
                sourceURL: capture.sourceURL,
                kind: capture.kind,
                sourceOrigin: sourceOrigin,
                capturedAt: capture.capturedAt,
                durationSeconds: capture.durationSeconds,
                thumbnailData: capture.thumbnailData,
                fileExtension: fileExtension
            )
        }.value
    }

    func addPhotoData(
        _ data: Data,
        thumbnailData: Data,
        fileExtension: String,
        capturedAt: Date = Date()
    ) async throws -> ThoughtComposerDraft {
        let rootURL = rootURL
        return try await Task.detached(priority: .userInitiated) {
            let store = ThoughtComposerDraftStore(rootURL: rootURL)
            return try store.stageOriginal(
                data: data,
                kind: .photo,
                sourceOrigin: "photoLibrary",
                capturedAt: capturedAt,
                durationSeconds: 0,
                thumbnailData: thumbnailData,
                fileExtension: fileExtension.isEmpty ? "jpg" : fileExtension.lowercased()
            )
        }.value
    }

    func removeAttachment(id: UUID) async throws -> ThoughtComposerDraft {
        let rootURL = rootURL
        return try await Task.detached(priority: .userInitiated) {
            let store = ThoughtComposerDraftStore(rootURL: rootURL)
            var draft = try store.load()
            guard let attachment = draft.attachments.first(where: { $0.id == id }) else {
                return draft
            }
            draft.attachments.removeAll { $0.id == id }
            if !draft.hasContent {
                draft.anchorAt = nil
            }
            try store.save(draft)
            let url = store.originalURL(for: attachment)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return draft
        }.value
    }

    func discard() async throws {
        let rootURL = rootURL
        try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
            try FileManager.default.removeItem(at: rootURL)
        }.value
    }

    func originalURL(for attachment: ThoughtComposerDraftAttachment) -> URL {
        originalsURL.appending(path: attachment.originalFilename)
    }

    private func stageOriginal(
        sourceURL: URL,
        kind: MediaKind,
        sourceOrigin: String,
        capturedAt: Date,
        durationSeconds: Double,
        thumbnailData: Data,
        fileExtension: String
    ) throws -> ThoughtComposerDraft {
        let id = UUID()
        let filename = "\(id.uuidString).\(fileExtension)"
        try FileManager.default.createDirectory(
            at: originalsURL,
            withIntermediateDirectories: true
        )
        let destination = originalsURL.appending(path: filename)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        do {
            return try appendAttachment(
                id: id,
                kind: kind,
                sourceOrigin: sourceOrigin,
                capturedAt: capturedAt,
                durationSeconds: durationSeconds,
                originalFilename: filename,
                thumbnailData: thumbnailData
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private func stageOriginal(
        data: Data,
        kind: MediaKind,
        sourceOrigin: String,
        capturedAt: Date,
        durationSeconds: Double,
        thumbnailData: Data,
        fileExtension: String
    ) throws -> ThoughtComposerDraft {
        let id = UUID()
        let filename = "\(id.uuidString).\(fileExtension)"
        try FileManager.default.createDirectory(
            at: originalsURL,
            withIntermediateDirectories: true
        )
        let destination = originalsURL.appending(path: filename)
        try data.write(to: destination, options: .atomic)
        do {
            return try appendAttachment(
                id: id,
                kind: kind,
                sourceOrigin: sourceOrigin,
                capturedAt: capturedAt,
                durationSeconds: durationSeconds,
                originalFilename: filename,
                thumbnailData: thumbnailData
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private func appendAttachment(
        id: UUID,
        kind: MediaKind,
        sourceOrigin: String,
        capturedAt: Date,
        durationSeconds: Double,
        originalFilename: String,
        thumbnailData: Data
    ) throws -> ThoughtComposerDraft {
        var draft = try load()
        guard draft.attachments.count < Self.maximumAttachmentCount else {
            throw ThoughtComposerDraftStoreError.tooManyAttachments
        }
        if !draft.hasContent {
            draft.anchorAt = capturedAt
        }
        draft.attachments.append(
            ThoughtComposerDraftAttachment(
                id: id,
                mediaType: kind.rawValue,
                sourceOrigin: sourceOrigin,
                capturedAt: capturedAt,
                durationSeconds: durationSeconds,
                originalFilename: originalFilename,
                thumbnailData: thumbnailData
            )
        )
        try save(draft)
        return draft
    }

    private func save(_ draft: ThoughtComposerDraft) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(draft)
        try data.write(to: manifestURL, options: .atomic)
    }
}
