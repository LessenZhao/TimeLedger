import EvolutionHubCore
import SwiftUI

struct SettingsHubView: View {
    @EnvironmentObject private var store: HubStore
    @State private var excludeDraft: String = ""
    @State private var cwdPrefix: String = ""
    @State private var cwdProjectId: String = ""

    var body: some View {
        Form {
            Section("路径") {
                TextField("Raw Vault 路径", text: $store.settings.rawVaultPath)
                TextField("agent-session-archive 路径", text: $store.settings.agentSessionArchivePath)
                TextField("ChatGPT archive 根目录", text: $store.settings.chatgptArchiveRoot)
            }
            Section("状态") {
                LabeledContent("Companion", value: store.settings.companionStatus)
                LabeledContent("iPhone 同步", value: store.settings.iPhoneSyncStatus)
            }
            Section("关联阈值") {
                HStack {
                    Text("自动关联 ≥")
                    TextField("", value: $store.linkingConfig.autoLinkThreshold, format: .number)
                        .frame(width: 60)
                }
                HStack {
                    Text("建议关联 ≥")
                    TextField("", value: $store.linkingConfig.suggestThreshold, format: .number)
                        .frame(width: 60)
                }
            }
            Section("cwd → 项目映射") {
                ForEach(Array(store.cwdMappings.keys.sorted()), id: \.self) { key in
                    LabeledContent(key, value: store.cwdMappings[key] ?? "")
                }
                HStack {
                    TextField("cwd 前缀", text: $cwdPrefix)
                    TextField("Project ID", text: $cwdProjectId)
                    Button("添加") {
                        guard !cwdPrefix.isEmpty, !cwdProjectId.isEmpty else { return }
                        store.cwdMappings[cwdPrefix] = cwdProjectId
                        cwdPrefix = ""
                        cwdProjectId = ""
                    }
                }
            }
            Section("隐私排除规则") {
                if store.settings.privacyExcludeRules.isEmpty {
                    Text("暂无规则").foregroundStyle(.secondary)
                } else {
                    ForEach(store.settings.privacyExcludeRules, id: \.self) { Text($0) }
                }
                HStack {
                    TextField("新增排除", text: $excludeDraft)
                    Button("添加") {
                        let t = excludeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        store.settings.privacyExcludeRules.append(t)
                        excludeDraft = ""
                    }
                }
            }
            Section {
                Text("同步不会上传聊天内容。日志仅路径/数量/状态。AI 未启用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear {
            if store.settings.agentSessionArchivePath.isEmpty {
                let guess = "/Users/lessen/coding/test/agent-session-archive"
                if FileManager.default.fileExists(atPath: guess) {
                    store.settings.agentSessionArchivePath = guess
                }
            }
        }
    }
}
