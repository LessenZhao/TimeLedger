import SwiftData
import SwiftUI

struct ExportView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: AppSettings?
    @State private var exportResult: String?
    @State private var errorMessage: String?

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
