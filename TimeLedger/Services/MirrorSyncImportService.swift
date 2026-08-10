import Foundation
import SwiftData

/// 兼容 facade：只转发给 TimeLedgerEngine，不再直接写数据库或手拼 JSON。
struct MirrorSyncImportService {
    let modelContext: ModelContext

    enum ImportError: LocalizedError {
        case invalidJSON

        var errorDescription: String? {
            switch self {
            case .invalidJSON: return "无法解析同步文件"
            }
        }
    }

    @discardableResult
    func importMacBatchJSON(_ json: String) throws -> Int {
        do {
            return try TimeLedgerEngine(modelContext: modelContext).importMacBatchJSON(json)
        } catch {
            throw error
        }
    }

    func importMacBatchFile(at url: URL) throws -> Int {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try importMacBatchJSON(text)
    }
}
