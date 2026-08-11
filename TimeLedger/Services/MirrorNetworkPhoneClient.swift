import Combine
import Foundation
import Network
import SwiftData

import EvolutionCore

/// Phone-side Bonjour client. JSON wire format compatible with EvolutionCore.MirrorWireMessage.
final class MirrorNetworkPhoneClient: ObservableObject {
    @Published var isBrowsing = false
    @Published var isConnected = false
    @Published var status = "未连接 Mac"
    @Published var discoveredName: String?

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private let deviceId: String
    private let queue = DispatchQueue(label: "com.lessen.TimeLedger.mirror.phone")
    private var pairingCode: String = ""
    private weak var modelContext: ModelContext?

    init(deviceId: String? = nil) {
        if let deviceId {
            self.deviceId = deviceId
        } else if let id = UserDefaults.standard.string(forKey: "pee.deviceId") {
            self.deviceId = id
        } else {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: "pee.deviceId")
            self.deviceId = id
        }
    }

    func connect(pairingCode: String, modelContext: ModelContext) {
        self.pairingCode = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelContext = modelContext
        stop()
        publish { $0.status = "正在查找 Mac…"; $0.isBrowsing = true }

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_timeledger-mirror._tcp", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            self.queue.async {
                guard self.connection == nil, let first = results.first else { return }
                let endpoint = first.endpoint
                DispatchQueue.main.async {
                    self.discoveredName = "\(endpoint)"
                }
                self.openConnection(to: endpoint)
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        connection?.cancel()
        connection = nil
        browser?.cancel()
        browser = nil
        receiveBuffer = Data()
        publish {
            $0.isBrowsing = false
            $0.isConnected = false
            $0.status = "未连接 Mac"
        }
    }

    func pushFullSnapshot() {
        queue.async { [weak self] in
            guard let self, let modelContext = self.modelContext else { return }
            guard self.connection != nil else { return }
            do {
                let snapshot = try self.buildSnapshot(modelContext: modelContext)
                self.sendMessage(.fullSnapshot(snapshot))
                self.publish { $0.status = "已推送全量到 Mac" }
            } catch {
                self.publish { $0.status = "推送失败：\(error.localizedDescription)" }
            }
        }
    }

    private func openConnection(to endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.publish { $0.status = "已连接，正在配对…" }
                self?.sendHello()
            case .failed(let error):
                self?.publish {
                    $0.isConnected = false
                    $0.status = "连接失败：\(error.localizedDescription)"
                }
            case .cancelled:
                self?.publish { $0.isConnected = false }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveLoop(connection)
    }

    private func sendHello() {
        sendMessage(.hello(role: "phone", deviceId: deviceId, pairingCode: pairingCode))
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let content, !content.isEmpty {
                self.receiveBuffer.append(content)
                while self.receiveBuffer.count >= 4 {
                    let length = self.receiveBuffer.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                    let total = 4 + Int(length)
                    guard self.receiveBuffer.count >= total else { break }
                    let payload = self.receiveBuffer.subdata(in: 4..<total)
                    self.receiveBuffer.removeSubrange(0..<total)
                    self.handlePayload(payload)
                }
            }
            if error != nil || isComplete {
                self.publish {
                    $0.isConnected = false
                    $0.status = "Mac 已断开"
                }
                return
            }
            self.receiveLoop(connection)
        }
    }

    private func handlePayload(_ data: Data) {
        guard let message = try? MirrorWireMessage.decode(from: data) else { return }

        switch message {
        case .helloAck(_, let ok, let reason):
            if ok {
                publish {
                    $0.isConnected = true
                    $0.isBrowsing = false
                    $0.status = "已与 Mac 镜像连接"
                }
                pushFullSnapshot()
            } else {
                let detail = reason ?? "未知"
                publish { $0.status = "配对失败：\(detail)" }
                DispatchQueue.main.async { self.stop() }
            }
        case .requestFullSnapshot:
            pushFullSnapshot()
        case .delta(let batch):
            guard let modelContext else { return }
            DispatchQueue.main.async {
                do {
                    let json = try String(data: ISO8601Codec.encoder.encode(batch), encoding: .utf8) ?? "{}"
                    let count = try MirrorSyncImportService(modelContext: modelContext).importMacBatchJSON(json)
                    self.status = "已应用 Mac 变更 \(count) 条"
                } catch {
                    self.status = "应用 Mac 变更失败：\(error.localizedDescription)"
                }
            }
        case .ping:
            sendMessage(.pong)
        case .hello, .fullSnapshot, .pong:
            break
        }
    }

    private func sendMessage(_ message: MirrorWireMessage) {
        guard let connection else { return }
        guard let payload = try? message.encodedData() else { return }
        let frame = MirrorFrameCodec.encode(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func publish(_ block: @escaping (MirrorNetworkPhoneClient) -> Void) {
        DispatchQueue.main.async {
            block(self)
        }
    }

    /// 构建完整账本快照，使用 EvolutionCore typed DTO，与 Mac 端 wire 协议一一对应。
    private func buildSnapshot(modelContext: ModelContext) throws -> MirrorLedgerSnapshot {
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
        let journals = try modelContext.fetch(FetchDescriptor<JournalEntry>())
        let journalLinks = try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
        let cursor = try modelContext.fetch(FetchDescriptor<TimeCursor>()).first

        let cursorAt = cursor?.cursorAt ?? Date()
        let cursorUpdated = cursor?.updatedAt ?? Date()

        let mirrorProjects = projects.map { p in
            MirrorProject(
                id: p.id.uuidString,
                name: p.name,
                categoryName: p.categoryName,
                sortOrder: p.sortOrder,
                isArchived: p.isArchived,
                revision: 1,
                updatedAt: p.updatedAt
            )
        }

        let mirrorEntries = entries.map { e -> MirrorTimeEntry in
            let body = documents.first {
                $0.ownerID == e.id && $0.ownerKind == ContentOwnerKind.timeEntry.rawValue
            }?.body ?? ""
            return MirrorTimeEntry(
                id: e.id.uuidString,
                projectId: e.projectId.uuidString,
                projectNameSnapshot: e.projectNameSnapshot,
                categoryNameSnapshot: e.categoryNameSnapshot,
                startAt: e.startAt,
                endAt: e.endAt,
                note: body,
                status: e.status,
                revision: 1,
                createdAt: e.createdAt,
                updatedAt: e.updatedAt
            )
        }

        let mirrorThoughts = journals.map { journal -> MirrorThought in
            let document = documents.first {
                $0.ownerID == journal.id && $0.ownerKind == ContentOwnerKind.journalEntry.rawValue
            }
            let link = journalLinks.first { $0.journalEntryID == journal.id }
            return MirrorThought(
                id: journal.id.uuidString,
                body: document?.body ?? "",
                capturedAt: journal.capturedAt,
                anchorAt: journal.anchorAt,
                linkedEntryId: link?.timeEntryID.uuidString,
                linkSource: link?.linkSource ?? ThoughtLinkSource.none.rawValue,
                revision: document?.revision ?? 0,
                createdAt: journal.createdAt,
                updatedAt: document?.updatedAt ?? journal.updatedAt
            )
        }

        return MirrorLedgerSnapshot(
            phoneDeviceId: deviceId,
            snapshotRevision: 1,
            cursor: MirrorCursor(
                cursorAt: cursorAt,
                updatedAt: cursorUpdated,
                revision: 1
            ),
            projects: mirrorProjects,
            timeEntries: mirrorEntries,
            thoughts: mirrorThoughts
        )
    }
}
