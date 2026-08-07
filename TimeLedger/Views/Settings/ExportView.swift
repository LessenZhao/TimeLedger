import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: AppSettings?
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var artifact: ExportArtifact?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isExporting = false
    @State private var showingShareSheet = false
    @State private var showingMacImporter = false
    @State private var exportTask: Task<Void, Never>?

    private var calendar: Calendar { .current }

    private var selectedRange: ExportDateRange? {
        let start = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        guard start <= endDay,
              let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay)
        else {
            return nil
        }
        return ExportDateRange(start: start, endExclusive: endExclusive)
    }

    var body: some View {
        Form {
            Section("导出范围") {
                DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                DatePicker("结束日期", selection: $endDate, displayedComponents: .date)

                HStack {
                    rangeButton("今天", action: selectToday)
                    rangeButton("本周", action: selectThisWeek)
                    rangeButton("本月", action: selectThisMonth)
                }

                if selectedRange == nil {
                    Text("结束日期不能早于开始日期")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("导出内容") {
                Toggle("仅导出已确认", isOn: Binding(
                    get: { settings?.exportOnlyConfirmed ?? true },
                    set: { newValue in
                        settings?.exportOnlyConfirmed = newValue
                        try? modelContext.save()
                    }
                ))

                Label("不包含图片和视频原件", systemImage: "photo.on.rectangle.angled")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    beginExport(.json)
                } label: {
                    Label("导出 JSON 数据", systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting || selectedRange == nil)
            }

            Section("Mac 镜像") {
                Button {
                    beginExport(.syncEnvelope)
                } label: {
                    Label("导出到 Mac", systemImage: "desktopcomputer")
                }
                .disabled(isExporting || selectedRange == nil)

                Button("导入 Mac 回写（mac-to-phone）") {
                    showingMacImporter = true
                }
                .disabled(isExporting)
            }

            if isExporting {
                Section {
                    HStack {
                        ProgressView()
                        Text("正在后台生成导出文件…")
                    }
                }
            } else if let statusMessage {
                Section("结果") {
                    Text(statusMessage)
                        .font(.footnote)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
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
        .onDisappear {
            exportTask?.cancel()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let artifact {
                ShareSheet(activityItems: [artifact.url])
            }
        }
        .fileImporter(
            isPresented: $showingMacImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importMacBatch(result)
        }
    }

    private func rangeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
    }

    private func selectToday() {
        startDate = Date()
        endDate = Date()
    }

    private func selectThisWeek() {
        let now = Date()
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        startDate = week?.start ?? now
        endDate = calendar.date(byAdding: .day, value: 6, to: week?.start ?? now) ?? now
    }

    private func selectThisMonth() {
        let now = Date()
        guard let month = calendar.dateInterval(of: .month, for: now),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end)
        else {
            return
        }
        startDate = month.start
        endDate = lastDay
    }

    private func loadSettings() {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            settings = existing
        } else {
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            try? modelContext.save()
            settings = newSettings
        }
    }

    private func beginExport(_ kind: ExportKind) {
        guard let range = selectedRange else { return }

        exportTask?.cancel()
        isExporting = true
        statusMessage = nil
        errorMessage = nil
        artifact = nil

        let onlyConfirmed = settings?.exportOnlyConfirmed ?? true
        let exporter = ExportFileService(modelContainer: modelContext.container)
        exportTask = Task {
            do {
                let result: ExportArtifact
                switch kind {
                case .json:
                    result = try await exporter.exportJSON(range: range, onlyConfirmed: onlyConfirmed)
                case .syncEnvelope:
                    result = try await exporter.exportSyncEnvelope(range: range, onlyConfirmed: onlyConfirmed)
                }

                guard !Task.isCancelled else { return }
                artifact = result
                statusMessage = "已生成 \(result.entryCount) 条记录、\(result.thoughtCount) 条随记，文件 \(ByteCountFormatter.string(fromByteCount: Int64(result.byteCount), countStyle: .file))"
                showingShareSheet = true
            } catch is CancellationError {
                // Leaving the screen cancels the pending export without showing an error.
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func importMacBatch(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let count = try MirrorSyncImportService(modelContext: modelContext).importMacBatchFile(at: url)
                statusMessage = "已从 Mac 回写应用 \(count) 条变更"
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

private enum ExportKind {
    case json
    case syncEnvelope
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        ExportView()
    }
    .modelContainer(previewModelContainer)
}
