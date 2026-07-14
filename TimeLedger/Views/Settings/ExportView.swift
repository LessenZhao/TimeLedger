import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: AppSettings?
    @State private var exportResult: String?
    @State private var errorMessage: String?
    @State private var showingMacImporter = false

    var body: some View {
        Form {
            Section("导出格式") {
                Button("导出 CSV") {
                    exportCSV()
                }
                Button("导出 JSON 备份") {
                    exportJSON()
                }
                Button("导出 Markdown 日报") {
                    exportMarkdown()
                }
                Button("导出 SyncEnvelope（连接 Mac 镜像）") {
                    exportSyncEnvelope()
                }
                Button("导入 Mac 回写（mac-to-phone）") {
                    importMacBatch()
                }
            }

            Section("导出选项") {
                Toggle("仅导出已确认", isOn: Binding(
                    get: { settings?.exportOnlyConfirmed ?? true },
                    set: { newValue in
                        settings?.exportOnlyConfirmed = newValue
                        try? modelContext.save()
                    }
                ))
            }

            if let result = exportResult {
                Section("结果") {
                    Text(result)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("导出数据")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadSettings()
        }
        .fileImporter(
            isPresented: $showingMacImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let count = try MirrorSyncImportService(modelContext: modelContext).importMacBatchFile(at: url)
                    exportResult = "已从 Mac 回写应用 \(count) 条变更"
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importMacBatch() {
        showingMacImporter = true
    }

    private func loadSettings() {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            settings = existing
        } else {
            let s = AppSettings()
            modelContext.insert(s)
            try? modelContext.save()
            settings = s
        }
    }

    private func exportSyncEnvelope() {
        do {
            let json = try SyncEnvelopeExportService(modelContext: modelContext).exportSyncBatchJSON()
            exportResult = json
            errorMessage = nil
            shareText(json, filename: "timeledger-syncbatch.json")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shareText(_ text: String, filename: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try text.data(using: .utf8)?.write(to: url)
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController
            {
                root.present(av, animated: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportCSV() {
        do {
            let csv = try ExportService(modelContext: modelContext).exportCSV(onlyConfirmed: settings?.exportOnlyConfirmed ?? true)
            exportResult = csv
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportJSON() {
        do {
            let json = try ExportService(modelContext: modelContext).exportJSON()
            exportResult = json
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportMarkdown() {
        do {
            let md = try ExportService(modelContext: modelContext).exportMarkdownDailyReport(date: Date(), onlyConfirmed: settings?.exportOnlyConfirmed ?? true)
            exportResult = md
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ExportView()
        .modelContainer(previewModelContainer)
}
