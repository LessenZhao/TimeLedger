import EvolutionHubCore
import SwiftUI

struct ThoughtsMirrorPane: View {
    @EnvironmentObject private var mirror: MirrorSessionController
    @State private var draft = ""
    @State private var errorText: String?

    var body: some View {
        if !mirror.canBookkeep {
            VStack(spacing: 12) {
                Image(systemName: "lock.fill").font(.system(size: 36)).foregroundStyle(.secondary)
                Text("思考 · 未连接").font(.title2)
                Text("连接 iPhone 后可记录思考卡片。").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("思考").font(.title2.weight(.semibold))
                HStack {
                    TextField("写下一句想法…", text: $draft, axis: .vertical)
                        .lineLimit(2...4)
                    Button("保存") {
                        do {
                            try mirror.addThought(body: draft)
                            draft = ""
                        } catch {
                            errorText = error.localizedDescription
                        }
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                List {
                    ForEach(mirror.engine.thoughts.sorted(by: { $0.capturedAt > $1.capturedAt })) { thought in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thought.body)
                            Text(thought.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let link = thought.linkedEntryId {
                                Text("关联: \(link.prefix(8))… · \(thought.linkSource)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .padding()
            .alert("失败", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: { Text(errorText ?? "") }
        }
    }
}

struct ReviewStatsPane: View {
    @EnvironmentObject private var mirror: MirrorSessionController

    var body: some View {
        let day = mirror.selectedDay
        let entries = mirror.engine.entries(on: day)
        let drafts = entries.filter(\.isDraft)
        let confirmed = entries.filter(\.isConfirmed)
        var byProject: [String: TimeInterval] = [:]
        for e in entries {
            byProject[e.projectNameSnapshot, default: 0] += e.endAt.timeIntervalSince(e.startAt)
        }

        return Form {
            Section("今日统计（镜像）") {
                if !mirror.canBookkeep {
                    Text("未连接 — 无统计数据")
                } else {
                    LabeledContent("日期", value: day.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("记录", value: "\(entries.count)（草稿 \(drafts.count) / 确认 \(confirmed.count)）")
                    LabeledContent("思考", value: "\(mirror.engine.thoughts.count)")
                    LabeledContent("未记录", value: "\(Int(mirror.unclassifiedDuration / 60)) 分钟")
                }
            }
            Section("项目投入") {
                if byProject.isEmpty {
                    Text("暂无").foregroundStyle(.secondary)
                } else {
                    ForEach(byProject.sorted(by: { $0.value > $1.value }), id: \.key) { item in
                        LabeledContent(item.key, value: "\(Int(item.value / 60)) 分钟")
                    }
                }
            }
        }
        .padding()
        .navigationTitle("复盘")
    }
}

struct SettingsCombinedPane: View {
    @EnvironmentObject private var hubStore: HubStore
    @EnvironmentObject private var mirror: MirrorSessionController

    var body: some View {
        TabView {
            SettingsHubView()
                .environmentObject(hubStore)
                .tabItem { Text("进化 / Collector") }
            Form {
                Section("镜像") {
                    LabeledContent("状态", value: mirror.canBookkeep ? "已连接" : "未连接")
                    LabeledContent("Mac 设备", value: String(mirror.engine.macDeviceId.prefix(8)) + "…")
                    if let phone = mirror.engine.phoneDeviceId {
                        LabeledContent("手机设备", value: String(phone.prefix(8)) + "…")
                    }
                    TextField("同步目录", text: $mirror.syncFolderPath)
                }
                Section {
                    Text("未连接时不可记账。断开后本地镜像清空，避免形成第二本账。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .tabItem { Text("镜像连接") }
        }
    }
}
