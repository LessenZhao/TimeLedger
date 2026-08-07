import Combine
import Foundation
import Network
import SwiftData

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
                let snapshotJSON = try self.buildSnapshotJSON(modelContext: modelContext)
                self.sendRaw(type: "fullSnapshot", extra: ["snapshot": snapshotJSON])
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
        sendRaw(type: "hello", extra: [
            "role": "phone",
            "deviceId": deviceId,
            "pairingCode": pairingCode
        ])
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
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return }

        switch type {
        case "helloAck":
            let ok = obj["ok"] as? Bool ?? false
            if ok {
                publish {
                    $0.isConnected = true
                    $0.isBrowsing = false
                    $0.status = "已与 Mac 镜像连接"
                }
                pushFullSnapshot()
            } else {
                let reason = obj["reason"] as? String ?? "未知"
                publish { $0.status = "配对失败：\(reason)" }
                DispatchQueue.main.async { self.stop() }
            }
        case "requestFullSnapshot":
            pushFullSnapshot()
        case "delta":
            if let batch = obj["batch"] as? [String: Any],
               let modelContext,
               let data = try? JSONSerialization.data(withJSONObject: batch),
               let json = String(data: data, encoding: .utf8)
            {
                DispatchQueue.main.async {
                    do {
                        let count = try MirrorSyncImportService(modelContext: modelContext).importMacBatchJSON(json)
                        self.status = "已应用 Mac 变更 \(count) 条"
                    } catch {
                        self.status = "应用 Mac 变更失败：\(error.localizedDescription)"
                    }
                }
            }
        case "ping":
            sendRaw(type: "pong", extra: [:])
        default:
            break
        }
    }

    private func sendRaw(type: String, extra: [String: Any]) {
        guard let connection else { return }
        var body = extra
        body["type"] = type
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func publish(_ block: @escaping (MirrorNetworkPhoneClient) -> Void) {
        DispatchQueue.main.async {
            block(self)
        }
    }

    private func buildSnapshotJSON(modelContext: ModelContext) throws -> [String: Any] {
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
        let journals = try modelContext.fetch(FetchDescriptor<JournalEntry>())
        let journalLinks = try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
        let cursor = try modelContext.fetch(FetchDescriptor<TimeCursor>()).first
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func d(_ date: Date) -> String { iso.string(from: date) }

        let cursorAt = cursor?.cursorAt ?? Date()
        let cursorUpdated = cursor?.updatedAt ?? Date()

        return [
            "protocolVersion": "1.0",
            "phoneDeviceId": deviceId,
            "snapshotRevision": 1,
            "exportedAt": d(Date()),
            "cursor": [
                "cursorAt": d(cursorAt),
                "updatedAt": d(cursorUpdated),
                "revision": 1
            ] as [String: Any],
            "projects": projects.map { p -> [String: Any] in
                [
                    "id": p.id.uuidString,
                    "name": p.name,
                    "categoryName": p.categoryName,
                    "sortOrder": p.sortOrder,
                    "isArchived": p.isArchived,
                    "revision": 1,
                    "updatedAt": d(p.updatedAt)
                ]
            },
            "timeEntries": entries.map { e -> [String: Any] in
                let body = documents.first {
                    $0.ownerID == e.id && $0.ownerKind == ContentOwnerKind.timeEntry.rawValue
                }?.body ?? ""
                return [
                    "id": e.id.uuidString,
                    "projectId": e.projectId.uuidString,
                    "projectNameSnapshot": e.projectNameSnapshot,
                    "categoryNameSnapshot": e.categoryNameSnapshot,
                    "startAt": d(e.startAt),
                    "endAt": d(e.endAt),
                    "note": body,
                    "status": e.status,
                    "revision": 1,
                    "createdAt": d(e.createdAt),
                    "updatedAt": d(e.updatedAt)
                ]
            },
            "thoughts": journals.map { journal -> [String: Any] in
                let document = documents.first {
                    $0.ownerID == journal.id && $0.ownerKind == ContentOwnerKind.journalEntry.rawValue
                }
                let link = journalLinks.first { $0.journalEntryID == journal.id }
                var row: [String: Any] = [
                    "id": journal.id.uuidString,
                    "body": document?.body ?? "",
                    "capturedAt": d(journal.capturedAt),
                    "anchorAt": d(journal.anchorAt),
                    "linkSource": link?.linkSource ?? ThoughtLinkSource.none.rawValue,
                    "revision": document?.revision ?? 0,
                    "createdAt": d(journal.createdAt),
                    "updatedAt": d(document?.updatedAt ?? journal.updatedAt)
                ]
                if let linked = link?.timeEntryID.uuidString {
                    row["linkedEntryId"] = linked
                }
                return row
            }
        ]
    }
}
