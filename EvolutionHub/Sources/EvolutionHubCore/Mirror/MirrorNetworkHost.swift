import Foundation
import Network
import EvolutionCore

/// Mac-side Bonjour listener for phone mirror sessions.
@MainActor
public final class MirrorNetworkHost: ObservableObject {
    public static let sharedServiceName = "TimeLedger Mac"

    @Published public private(set) var isAdvertising = false
    @Published public private(set) var pairingCode: String = ""
    @Published public private(set) var peerDeviceId: String?
    @Published public private(set) var lastEvent: String = ""
    @Published public private(set) var isPeerConnected = false

    public var onFullSnapshot: ((MirrorLedgerSnapshot) -> Void)?
    public var onDelta: ((SyncBatchFile) -> Void)?
    public var onRequestFullSnapshot: (() -> Void)?

    private var listener: NWListener?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private let macDeviceId: String
    private let queue = DispatchQueue(label: "com.lessen.TimeLedger.mirror.host")

    public init(macDeviceId: String) {
        self.macDeviceId = macDeviceId
    }

    public func startAdvertising() throws {
        stop()
        pairingCode = MirrorPairing.generateCode()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let listener = try NWListener(using: parameters)
        listener.service = NWListener.Service(
            name: Self.sharedServiceName,
            type: MirrorServiceDiscovery.bonjourType
        )
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isAdvertising = true
                    self.lastEvent = "等待 iPhone… 配对码 \(self.pairingCode)"
                case .failed(let error):
                    self.isAdvertising = false
                    self.lastEvent = "广播失败：\(error.localizedDescription)"
                case .cancelled:
                    self.isAdvertising = false
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.accept(connection)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        isAdvertising = false
        isPeerConnected = false
        peerDeviceId = nil
        receiveBuffer = Data()
    }

    public func send(_ message: MirrorWireMessage) {
        guard let connection, isPeerConnected else { return }
        do {
            let payload = try message.encodedData()
            let frame = MirrorFrameCodec.encode(payload)
            connection.send(content: frame, completion: .contentProcessed { _ in })
        } catch {
            lastEvent = "发送失败：\(error.localizedDescription)"
        }
    }

    public func sendDelta(_ batch: SyncBatchFile) {
        send(.delta(batch))
    }

    public func requestPhoneSnapshot() {
        send(.requestFullSnapshot)
    }

    private func accept(_ connection: NWConnection) {
        // Single peer: replace previous
        self.connection?.cancel()
        self.connection = connection
        receiveBuffer = Data()
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.lastEvent = "链路已建立，等待配对…"
                case .failed(let error):
                    self.isPeerConnected = false
                    self.lastEvent = "连接失败：\(error.localizedDescription)"
                case .cancelled:
                    self.isPeerConnected = false
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
        receiveLoop(connection)
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let content, !content.isEmpty {
                    self.receiveBuffer.append(content)
                    let frames = MirrorFrameCodec.decodeFrames(buffer: &self.receiveBuffer)
                    for frame in frames {
                        self.handleFrame(frame)
                    }
                }
                if error != nil || isComplete {
                    self.isPeerConnected = false
                    self.lastEvent = "手机已断开"
                    return
                }
                self.receiveLoop(connection)
            }
        }
    }

    private func handleFrame(_ data: Data) {
        do {
            let message = try MirrorWireMessage.decode(from: data)
            switch message {
            case let .hello(role, deviceId, code):
                guard role == "phone" else {
                    send(.helloAck(deviceId: macDeviceId, ok: false, reason: "角色无效"))
                    return
                }
                guard code == pairingCode else {
                    send(.helloAck(deviceId: macDeviceId, ok: false, reason: "配对码错误"))
                    lastEvent = "配对失败：码错误"
                    return
                }
                peerDeviceId = deviceId
                isPeerConnected = true
                send(.helloAck(deviceId: macDeviceId, ok: true, reason: nil))
                lastEvent = "已配对手机 \(deviceId.prefix(8))…"
                send(.requestFullSnapshot)
            case let .fullSnapshot(snapshot):
                onFullSnapshot?(snapshot)
                lastEvent = "已接收手机全量镜像"
            case let .delta(batch):
                onDelta?(batch)
                lastEvent = "已接收手机增量 \(batch.envelopes.count) 条"
            case .ping:
                send(.pong)
            case .pong, .helloAck, .requestFullSnapshot:
                break
            }
        } catch {
            lastEvent = "解析失败：\(error.localizedDescription)"
        }
    }
}
