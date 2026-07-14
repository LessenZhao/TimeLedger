import Combine
import Foundation
import EvolutionCore

@MainActor
public final class MirrorSessionController: ObservableObject {
    @Published public private(set) var engine: MirrorLedgerEngine
    @Published public var selectedDay: Date = Date()
    @Published public var now: Date = Date()
    @Published public var statusMessage: String = "未连接 iPhone"
    @Published public var syncFolderPath: String = ""
    @Published public private(set) var networkHost: MirrorNetworkHost

    private var ticker: AnyCancellable?
    private var networkEventHook: AnyCancellable?

    public init(macDeviceId: String = UUID().uuidString) {
        let id = macDeviceId
        self.engine = MirrorLedgerEngine(macDeviceId: id)
        let host = MirrorNetworkHost(macDeviceId: id)
        self.networkHost = host
        host.onFullSnapshot = { [weak self] snapshot in
            self?.applyNetworkSnapshot(snapshot)
        }
        host.onDelta = { [weak self] batch in
            self?.applyNetworkDelta(batch)
        }
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.now = date
            }
        networkEventHook = host.$lastEvent
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self, !event.isEmpty else { return }
                if !self.canBookkeep {
                    self.statusMessage = event
                }
            }
    }

    public var connectionState: MirrorConnectionState { engine.connectionState }
    public var canBookkeep: Bool { engine.canBookkeep }
    public var unclassifiedDuration: TimeInterval { engine.unclassifiedDuration(now: now) }

    public func startLANAdvertising() {
        do {
            try networkHost.startAdvertising()
            statusMessage = "局域网等待中 · 配对码 \(networkHost.pairingCode)"
        } catch {
            statusMessage = "无法广播：\(error.localizedDescription)"
        }
    }

    public func stopLANAdvertising() {
        networkHost.stop()
        if !canBookkeep {
            statusMessage = "已停止局域网广播"
        }
    }

    public func connectFromSyncBatchFile(url: URL) throws {
        let batch = try SyncBatchImporter.importFile(at: url)
        let snapshot = try MirrorSnapshotBuilder.fromSyncBatch(batch)
        var e = engine
        e.connect(with: snapshot)
        engine = e
        statusMessage = "已连接（文件）· 手机 \(snapshot.phoneDeviceId.prefix(8))…"
    }

    public func connectFromSnapshotFile(url: URL) throws {
        let data = try Data(contentsOf: url)
        let snapshot = try ISO8601Codec.decoder.decode(MirrorLedgerSnapshot.self, from: data)
        var e = engine
        e.connect(with: snapshot)
        engine = e
        statusMessage = "已连接（快照）· r\(snapshot.snapshotRevision)"
    }

    public func disconnect() {
        networkHost.stop()
        var e = engine
        e.disconnect()
        engine = e
        statusMessage = "已断开 · 记账已锁定"
    }

    public func quickRecord(projectId: String) throws {
        var e = engine
        _ = try e.quickRecord(projectId: projectId, now: now)
        engine = e
        statusMessage = "已记草稿 · 同步中"
        try flushOutbound()
    }

    public func confirmEntry(id: String) throws {
        var e = engine
        try e.confirmEntry(id: id, now: now)
        engine = e
        try flushOutbound()
    }

    public func unconfirmEntry(id: String) throws {
        var e = engine
        try e.unconfirmEntry(id: id, now: now)
        engine = e
        try flushOutbound()
    }

    public func deleteDraft(id: String) throws {
        var e = engine
        try e.deleteDraft(id: id)
        engine = e
        try flushOutbound()
    }

    public func updateDraftEntry(id: String, startAt: Date, endAt: Date, note: String) throws {
        var e = engine
        try e.updateDraftEntry(id: id, startAt: startAt, endAt: endAt, note: note, now: now)
        engine = e
        try flushOutbound()
    }

    public func addThought(body: String) throws {
        var e = engine
        _ = try e.addThought(body: body, now: now)
        engine = e
        try flushOutbound()
    }

    public func pullInboundFromSyncFolder() throws {
        guard engine.isConnected else { return }
        let inbound = syncFolderURL().appendingPathComponent("phone-to-mac.json")
        guard FileManager.default.fileExists(atPath: inbound.path) else {
            statusMessage = "同步目录中没有 phone-to-mac.json"
            return
        }
        let batch = try SyncBatchImporter.importFile(at: inbound)
        var e = engine
        try e.applyInbound(envelopes: batch.envelopes)
        engine = e
        statusMessage = "已拉取手机变更 \(batch.envelopes.count) 条"
    }

    public func exportOutboundBatch() throws -> URL {
        var e = engine
        let envelopes = e.drainOutbound()
        engine = e
        let batch = SyncBatchFile(deviceId: engine.macDeviceId, envelopes: envelopes)
        let data = try ISO8601Codec.encoder.encode(batch)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-to-phone-\(Int(Date().timeIntervalSince1970)).json")
        try data.write(to: url)
        return url
    }

    public func requestPhoneRefresh() {
        networkHost.requestPhoneSnapshot()
        statusMessage = "已请求手机推送全量"
    }

    private func applyNetworkSnapshot(_ snapshot: MirrorLedgerSnapshot) {
        var e = engine
        e.connect(with: snapshot)
        engine = e
        statusMessage = "局域网已连接 · 镜像与手机一致"
    }

    private func applyNetworkDelta(_ batch: SyncBatchFile) {
        guard engine.isConnected else {
            // If not connected yet but got delta, ignore
            return
        }
        var e = engine
        do {
            try e.applyInbound(envelopes: batch.envelopes)
            engine = e
            statusMessage = "已合并手机增量 \(batch.envelopes.count) 条"
        } catch {
            statusMessage = "合并失败：\(error.localizedDescription)"
        }
    }

    private func flushOutbound() throws {
        var e = engine
        let drained = e.drainOutbound()
        engine = e
        guard !drained.isEmpty else { return }

        let batch = SyncBatchFile(deviceId: engine.macDeviceId, envelopes: drained)

        // LAN first
        if networkHost.isPeerConnected {
            networkHost.sendDelta(batch)
        }

        // File fallback / audit trail
        let folder = syncFolderURL()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = folder.appendingPathComponent("mac-to-phone.json")
        var envelopes = drained
        if FileManager.default.fileExists(atPath: out.path),
           let existing = try? SyncBatchImporter.importFile(at: out)
        {
            envelopes = existing.envelopes + drained
        }
        let fileBatch = SyncBatchFile(deviceId: engine.macDeviceId, envelopes: envelopes)
        try ISO8601Codec.encoder.encode(fileBatch).write(to: out)
    }

    private func syncFolderURL() -> URL {
        if !syncFolderPath.isEmpty {
            return URL(fileURLWithPath: syncFolderPath, isDirectory: true)
        }
        return RawVaultLayout.defaultApplicationSupport().syncURL
            .appendingPathComponent("mirror", isDirectory: true)
    }
}
