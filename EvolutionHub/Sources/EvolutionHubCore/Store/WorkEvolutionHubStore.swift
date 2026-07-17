import Combine
import EvolutionCore
import Foundation

public enum WorkEvolutionHubStoreError: Error, Sendable, Equatable {
    case sourceSessionNotFound(String)
}

extension WorkEvolutionHubStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sourceSessionNotFound(let id):
            return "找不到来源会话：\(id)。"
        }
    }
}

/// Main-actor presentation façade. Persistence, proposal validation, merge and
/// projection semantics remain owned by EvolutionLedger.
@MainActor
public final class WorkEvolutionHubStore: ObservableObject {
    @Published public private(set) var snapshot: EvolutionSnapshot
    @Published public private(set) var receipts: [ImportReceipt]
    @Published public private(set) var lastError: String?
    @Published public var selectedDay: Date
    @Published public var selectedProjectId: String?
    @Published public var selectedSourceSessionId: String?

    public let calendar: Calendar

    private let ledger: EvolutionLedger
    private let inbox: EvolutionProposalInbox
    private let archiveReader: ArchiveEvidenceReader
    private let exporter: EvolutionMarkdownExporter
    private let now: @Sendable () -> Date
    private var refreshTask: Task<RefreshResult, Never>?

    public init(
        layout: EvolutionLedgerLayout = .defaultDocuments(),
        calendar: Calendar = .current,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let ledger = EvolutionLedger(
            store: JSONEvolutionDocumentStore(layout: layout, fileManager: fileManager)
        )
        self.ledger = ledger
        self.inbox = EvolutionProposalInbox(
            layout: layout,
            ledger: ledger,
            fileManager: fileManager,
            now: now
        )
        self.archiveReader = ArchiveEvidenceReader()
        self.exporter = EvolutionMarkdownExporter(layout: layout)
        self.now = now
        self.calendar = calendar
        self.selectedDay = now()
        self.selectedProjectId = nil
        self.selectedSourceSessionId = nil
        self.snapshot = Self.emptySnapshot
        self.receipts = []
        self.lastError = nil
    }

    public func refresh() async {
        let task: Task<RefreshResult, Never>
        if let inFlight = refreshTask {
            task = inFlight
        } else {
            let inbox = self.inbox
            let ledger = self.ledger
            let exporter = self.exporter
            let created = Task.detached(priority: .userInitiated) {
                var imported: [ImportReceipt] = []
                var importError: String?
                do {
                    imported = try inbox.importPending()
                } catch {
                    importError = error.localizedDescription
                }
                do {
                    let snapshot = try ledger.read(.all)
                    var exportError: String?
                    do {
                        try exporter.export(snapshot: snapshot)
                    } catch {
                        exportError = "Markdown 导出失败：\(error.localizedDescription)"
                    }
                    return RefreshResult(
                        snapshot: snapshot,
                        receipts: imported,
                        error: [importError, exportError]
                            .compactMap { $0 }
                            .joined(separator: "\n")
                            .nonEmpty
                    )
                } catch {
                    return RefreshResult(
                        snapshot: nil,
                        receipts: imported,
                        error: [importError, error.localizedDescription]
                            .compactMap { $0 }
                            .joined(separator: "\n")
                    )
                }
            }
            refreshTask = created
            task = created
        }

        let result = await task.value
        refreshTask = nil

        if let loaded = result.snapshot {
            snapshot = loaded
        }
        receipts = result.receipts
        lastError = result.error
    }

    public func addAnnotation(
        target: AnnotationTarget,
        kind: AnnotationKind,
        body: String,
        happenedAt: Date? = nil
    ) throws {
        let timestamp = now()
        let annotation = UserAnnotation(
            id: UUID().uuidString,
            target: target,
            kind: kind,
            body: body,
            happenedAt: happenedAt,
            recognizedAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try apply(.addAnnotation(annotation))
    }

    public func confirmDay(_ date: String) throws {
        try apply(.confirmDay(date))
    }

    public func confirmProject(_ id: String) throws {
        try apply(.confirmProject(id))
    }

    public func confirmNode(_ id: String) throws {
        try apply(.confirmNode(id))
    }

    public func conversation(sessionId: String) throws -> [PreparedMessage] {
        guard let session = snapshot.sourceSessions.first(where: { $0.id == sessionId }) else {
            throw WorkEvolutionHubStoreError.sourceSessionNotFound(sessionId)
        }
        return try archiveReader.conversation(session: session)
    }

    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func apply(_ command: EvolutionUserCommand) throws {
        do {
            _ = try ledger.apply(command)
            let loaded = try ledger.read(.all)
            snapshot = loaded
            do {
                try exporter.export(snapshot: loaded)
                lastError = nil
            } catch {
                lastError = "Markdown 导出失败：\(error.localizedDescription)"
            }
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private static let emptySnapshot = EvolutionSnapshot(
        projects: [],
        days: [],
        nodes: [],
        annotations: [],
        sourceSessions: [],
        worktreeEvidence: []
    )
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private struct RefreshResult: Sendable {
    var snapshot: EvolutionSnapshot?
    var receipts: [ImportReceipt]
    var error: String?
}
