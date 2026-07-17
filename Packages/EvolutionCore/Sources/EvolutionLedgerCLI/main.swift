import Darwin
import EvolutionCore
import Foundation

private final class ReadOnlyStore: EvolutionDocumentStore, @unchecked Sendable {
    func load() throws -> EvolutionLedgerDocument {
        throw CLIError.message("CLI 不读取正式 ledger records")
    }

    func save(_ document: EvolutionLedgerDocument) throws {
        throw CLIError.message("CLI 不写入正式 ledger records")
    }
}

private enum CLIError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}

private struct Arguments {
    let command: String
    let values: [String: String]

    init(_ raw: [String]) throws {
        guard let command = raw.first, command == "prepare" || command == "validate" else {
            throw CLIError.message("仅支持 prepare 或 validate")
        }
        self.command = command
        let allowed: Set<String> = command == "prepare"
            ? ["--job-id", "--request", "--output"]
            : ["--proposal"]
        var parsed: [String: String] = [:]
        var index = 1
        while index < raw.count {
            let flag = raw[index]
            guard allowed.contains(flag) else { throw CLIError.message("未知参数：\(flag)") }
            guard parsed[flag] == nil else { throw CLIError.message("参数重复：\(flag)") }
            guard index + 1 < raw.count, !raw[index + 1].hasPrefix("--") else {
                throw CLIError.message("参数缺少值：\(flag)")
            }
            parsed[flag] = raw[index + 1]
            index += 2
        }
        guard Set(parsed.keys) == allowed else {
            let missing = allowed.subtracting(parsed.keys).sorted().joined(separator: ",")
            throw CLIError.message("缺少参数：\(missing)")
        }
        values = parsed
    }
}

private func read<T: Decodable>(_ type: T.Type, path: String) throws -> T {
    try ISO8601Codec.decoder.decode(type, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

private func publish(_ data: Data, outputPath: String) throws {
    let manager = FileManager.default
    let output = URL(fileURLWithPath: outputPath)
    let temporary = URL(fileURLWithPath: outputPath + ".tmp")
    try manager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    do {
        if manager.fileExists(atPath: temporary.path) { try manager.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        if manager.fileExists(atPath: output.path) {
            _ = try manager.replaceItemAt(output, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: output)
        }
    } catch {
        if manager.fileExists(atPath: temporary.path) { try? manager.removeItem(at: temporary) }
        throw error
    }
}

private func emit(_ values: [String: Any], to handle: FileHandle) {
    let data = (try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])) ?? Data("{\"ok\":false}".utf8)
    handle.write(data)
    handle.write(Data([0x0A]))
}

do {
    let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
    switch arguments.command {
    case "prepare":
        let jobID = arguments.values["--job-id"]!
        let request: EvolutionPrepareRequest = try read(EvolutionPrepareRequest.self, path: arguments.values["--request"]!)
        let ledger = EvolutionLedger(store: ReadOnlyStore())
        let bundle = try ledger.prepare(jobId: jobID, request: request)
        try publish(ISO8601Codec.encoder.encode(bundle), outputPath: arguments.values["--output"]!)
        let sessions = bundle.archiveDays.reduce(0) { $0 + $1.sessions.count }
        emit(["jobId": bundle.jobId, "ok": true, "sessions": sessions], to: .standardOutput)
    case "validate":
        let proposal: EvolutionProposalEnvelope = try read(EvolutionProposalEnvelope.self, path: arguments.values["--proposal"]!)
        try EvolutionProposalValidator().validate(proposal)
        emit(["jobId": proposal.jobId, "ok": true], to: .standardOutput)
    default:
        throw CLIError.message("不可达命令")
    }
} catch {
    let raw = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    let singleLine = raw.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    emit(["error": singleLine, "ok": false], to: .standardError)
    exit(1)
}
