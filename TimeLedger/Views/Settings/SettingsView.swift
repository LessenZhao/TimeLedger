import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: AppSettings?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("未记录提醒阈值")
                        Spacer()
                        Stepper(value: Binding(
                            get: { settings?.longUnclassifiedThresholdMinutes ?? 90 },
                            set: { newValue in
                                settings?.longUnclassifiedThresholdMinutes = newValue
                                saveSettings()
                            }
                        ), in: 10...480, step: 5) {
                            Text("\(settings?.longUnclassifiedThresholdMinutes ?? 90) 分钟")
                        }
                    }

                    Toggle("今日汇总含草稿", isOn: Binding(
                        get: { settings?.includeDraftInTodaySummary ?? true },
                        set: { newValue in
                            settings?.includeDraftInTodaySummary = newValue
                            saveSettings()
                        }
                    ))
                } header: {
                    Text("记录")
                } footer: {
                    Text("超过阈值再打标时，会弹出调整时间。")
                }

                Section("导出") {
                    Toggle("仅导出已确认", isOn: Binding(
                        get: { settings?.exportOnlyConfirmed ?? true },
                        set: { newValue in
                            settings?.exportOnlyConfirmed = newValue
                            saveSettings()
                        }
                    ))

                    NavigationLink {
                        ExportView()
                    } label: {
                        Label("导出数据", systemImage: "square.and.arrow.up")
                    }
                }
 
                Section("项目") {
                    NavigationLink {
                        ProjectManageView()
                    } label: {
                        Label("项目管理", systemImage: "list.bullet.rectangle")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
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
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            try? modelContext.save()
            settings = newSettings
        }
    }

    private func saveSettings() {
        try? modelContext.save()
    }
}

#Preview {
    SettingsView()
        .modelContainer(previewModelContainer)
}
