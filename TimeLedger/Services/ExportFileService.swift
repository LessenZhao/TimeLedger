import Foundation
import SwiftData

nonisolated struct ExportArtifact: Sendable {
    let url: URL
    let entryCount: Int
    let thoughtCount: Int
    let byteCount: Int
}

@ModelActor
actor ExportFileService {
    func exportJSON(range: ExportDateRange, onlyConfirmed: Bool) throws -> ExportArtifact {
        try Task.checkCancellation()
        let prepared = try JSONExportService(modelContext: modelContext).prepareJSON(
            range: range,
            onlyConfirmed: onlyConfirmed
        )
        try Task.checkCancellation()

        let url = try write(
            prepared.data,
            filename: "timeledger-\(dayString(range.start))-to-\(dayString(range.endExclusive.addingTimeInterval(-1))).json"
        )
        return ExportArtifact(
            url: url,
            entryCount: prepared.entryCount,
            thoughtCount: prepared.thoughtCount,
            byteCount: prepared.data.count
        )
    }

    func exportSyncEnvelope(range: ExportDateRange, onlyConfirmed: Bool) throws -> ExportArtifact {
        try Task.checkCancellation()
        let prepared = try SyncEnvelopeExportService(modelContext: modelContext).prepareSyncBatchJSON(
            range: range,
            onlyConfirmed: onlyConfirmed
        )
        try Task.checkCancellation()

        let data = Data(prepared.json.utf8)
        let url = try write(
            data,
            filename: "timeledger-sync-\(dayString(range.start))-to-\(dayString(range.endExclusive.addingTimeInterval(-1))).json"
        )
        return ExportArtifact(
            url: url,
            entryCount: prepared.entryCount,
            thoughtCount: prepared.thoughtCount,
            byteCount: data.count
        )
    }

    private func write(_ data: Data, filename: String) throws -> URL {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "TimeLedgerExports", directoryHint: .isDirectory)
        let directory = rootDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appending(path: filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func dayString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
