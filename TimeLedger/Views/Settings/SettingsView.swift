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

                    Toggle("今日汇总含待确认", isOn: Binding(
                        get: { settings?.includeDraftInTodaySummary ?? true },
                        set: { newValue in
                            settings?.includeDraftInTodaySummary = newValue
                            saveSettings()
                        }
                    ))
                } header: {
                    Text("记录")
                } footer: {
                    Text("超过阈值再打标时，会打开记录详情。")
                }

                Section {
                    Picker("媒体原件存放位置", selection: Binding(
                        get: {
                            MediaStoragePreference(
                                rawValue: settings?.mediaStoragePreference
                                    ?? MediaStoragePreference.photosLibrary.rawValue
                            ) ?? .photosLibrary
                        },
                        set: { newValue in
                            settings?.mediaStoragePreference = newValue.rawValue
                            saveSettings()
                        }
                    )) {
                        ForEach(MediaStoragePreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .accessibilityIdentifier("settings.mediaStorage")
                } header: {
                    Text("媒体")
                } footer: {
                    Text("修改后从下一次拍摄生效。TimeLedger 始终保存时间点和小缩略图。")
                }

                Section("Mac 镜像") {
                    NavigationLink {
                        MirrorConnectView()
                    } label: {
                        Label("连接 Mac 镜像", systemImage: "desktopcomputer")
                    }
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
        settings = try? TimeLedgerEngine(modelContext: modelContext).getOrCreateAppSettings()
    }

    private func saveSettings() {
        if let settings {
            try? TimeLedgerEngine(modelContext: modelContext).saveAppSettings(settings)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(previewModelContainer)
}
