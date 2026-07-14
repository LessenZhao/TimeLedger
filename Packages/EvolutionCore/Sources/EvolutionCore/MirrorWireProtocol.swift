import Foundation

public enum MirrorServiceDiscovery {
    public static let bonjourType = "_timeledger-mirror._tcp"
    public static let bonjourDomain = "local."
}

/// Length-prefixed JSON frames over a byte stream.
public enum MirrorFrameCodec {
    public static func encode(_ data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        var out = Data(bytes: &length, count: 4)
        out.append(data)
        return out
    }

    public static func decodeFrames(buffer: inout Data) -> [Data] {
        var frames: [Data] = []
        while buffer.count >= 4 {
            let length: UInt32 = buffer.prefix(4).withUnsafeBytes { raw in
                raw.load(as: UInt32.self).bigEndian
            }
            let total = 4 + Int(length)
            guard buffer.count >= total else { break }
            let payload = buffer.subdata(in: 4..<total)
            frames.append(payload)
            buffer.removeSubrange(0..<total)
        }
        return frames
    }
}

public enum MirrorWireMessage: Codable, Sendable {
    case hello(role: String, deviceId: String, pairingCode: String)
    case helloAck(deviceId: String, ok: Bool, reason: String?)
    case fullSnapshot(MirrorLedgerSnapshot)
    case delta(SyncBatchFile)
    case requestFullSnapshot
    case ping
    case pong

    private enum CodingKeys: String, CodingKey {
        case type, role, deviceId, pairingCode, ok, reason, snapshot, batch
    }

    private enum Kind: String, Codable {
        case hello, helloAck, fullSnapshot, delta, requestFullSnapshot, ping, pong
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .hello(role, deviceId, pairingCode):
            try c.encode(Kind.hello, forKey: .type)
            try c.encode(role, forKey: .role)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode(pairingCode, forKey: .pairingCode)
        case let .helloAck(deviceId, ok, reason):
            try c.encode(Kind.helloAck, forKey: .type)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode(ok, forKey: .ok)
            try c.encodeIfPresent(reason, forKey: .reason)
        case let .fullSnapshot(snapshot):
            try c.encode(Kind.fullSnapshot, forKey: .type)
            try c.encode(snapshot, forKey: .snapshot)
        case let .delta(batch):
            try c.encode(Kind.delta, forKey: .type)
            try c.encode(batch, forKey: .batch)
        case .requestFullSnapshot:
            try c.encode(Kind.requestFullSnapshot, forKey: .type)
        case .ping:
            try c.encode(Kind.ping, forKey: .type)
        case .pong:
            try c.encode(Kind.pong, forKey: .type)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(Kind.self, forKey: .type)
        switch type {
        case .hello:
            self = .hello(
                role: try c.decode(String.self, forKey: .role),
                deviceId: try c.decode(String.self, forKey: .deviceId),
                pairingCode: try c.decode(String.self, forKey: .pairingCode)
            )
        case .helloAck:
            self = .helloAck(
                deviceId: try c.decode(String.self, forKey: .deviceId),
                ok: try c.decode(Bool.self, forKey: .ok),
                reason: try c.decodeIfPresent(String.self, forKey: .reason)
            )
        case .fullSnapshot:
            self = .fullSnapshot(try c.decode(MirrorLedgerSnapshot.self, forKey: .snapshot))
        case .delta:
            self = .delta(try c.decode(SyncBatchFile.self, forKey: .batch))
        case .requestFullSnapshot:
            self = .requestFullSnapshot
        case .ping:
            self = .ping
        case .pong:
            self = .pong
        }
    }

    public func encodedData() throws -> Data {
        try ISO8601Codec.encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> MirrorWireMessage {
        try ISO8601Codec.decoder.decode(MirrorWireMessage.self, from: data)
    }
}

public enum MirrorPairing {
    public static func generateCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }
}
