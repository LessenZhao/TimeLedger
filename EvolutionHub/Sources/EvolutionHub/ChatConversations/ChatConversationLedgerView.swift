import EvolutionCore
import EvolutionHubCore
import SwiftUI

private enum LedgerProjectionMode: String, CaseIterable, Identifiable {
    case conversation = "按会话"
    case topic = "按主题"
    case kind = "按类型"

    var id: Self { self }
}

private enum ConversationAssetFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case finishedWork = "范文"
    case expressionModule = "表达模块"
    case sourceMaterial = "素材证据"
    case methodStrategy = "方法策略"
    case viewpointKnowledge = "观点知识"
    case memorize = "待背诵"

    var id: Self { self }
}

private enum KindUseFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case memorize = "待背诵"
    case imitate = "可仿写"
    case quote = "可引用"
    case practice = "待实践"
    case review = "重点复习"

    var id: Self { self }
}

struct ChatConversationLedgerView: View {
    @ObservedObject var store: ChatConversationHubStore
    @State private var mode: LedgerProjectionMode = .conversation
    @State private var conversationFilter: ConversationAssetFilter = .all
    @State private var kindUseFilter: KindUseFilter = .all
    @State private var versionAssetID: String?
    @State private var editAssetID: String?
    @State private var editText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.ledgerSchemaState == .requiresV1Migration {
                migrationBanner
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("湖南省直遴选备考库")
                            .font(.headline)
                        Text("只处理你主动选择的会话")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("投影", selection: $mode) {
                        ForEach(LedgerProjectionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    Spacer()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        switch mode {
                        case .conversation:
                            conversationMode
                        case .topic:
                            topicMode
                        case .kind:
                            kindMode
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: Binding(
            get: { versionAssetID.map(Identified.init) },
            set: { versionAssetID = $0?.id }
        )) { item in
            if let asset = store.asset(id: item.id) {
                versionSheet(asset)
            }
        }
        .sheet(item: Binding(
            get: { editAssetID.map(Identified.init) },
            set: { editAssetID = $0?.id }
        )) { item in
            NavigationStack {
                Form {
                    TextEditor(text: $editText)
                        .frame(minHeight: 180)
                }
                .navigationTitle("创建修改版")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { editAssetID = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            try? store.appendUserEditedVersion(assetID: item.id, text: editText)
                            editAssetID = nil
                        }
                        .disabled(editText.isEmpty)
                    }
                }
            }
            .frame(minWidth: 480, minHeight: 320)
        }
    }

    private var migrationBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("需要升级备考库")
                .font(.headline)
            Text("当前正式账本仍是 schema v1。升级前会先写入备份文件，再迁移主题、片段、历史结论、重点、备注、处理版本和回执。")
                .foregroundStyle(.secondary)
            Text("备份目录：\(store.lastMigrationBackupURL?.path ?? "records/")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("备份并升级备考库") {
                _ = try? store.performLegacyLedgerMigration()
            }
            .buttonStyle(.borderedProminent)
            if let error = store.lastError {
                Text(error).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var conversationMode: some View {
        if store.formalConversationProjections.isEmpty {
            ContentUnavailableView(
                "尚未确认正式内容",
                systemImage: "checkmark.seal",
                description: Text("确认候选后，这里会按会话显示片段目录与备考资产。")
            )
        } else {
            ForEach(store.formalConversationProjections, id: \.id) { projection in
                DisclosureGroup("\(projection.title) · \(projection.segments.count) 片段 / \(projection.assets.count) 资产") {
                    Picker("过滤", selection: $conversationFilter) {
                        ForEach(ConversationAssetFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    ForEach(projection.segments, id: \.id) { segment in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(segment.title).font(.subheadline.weight(.semibold))
                            Text(segment.summary).font(.caption).foregroundStyle(.secondary)
                            let assets = filteredAssets(projection.assets.filter { $0.segmentID == segment.id })
                            ForEach(assets) { ref in
                                if let asset = store.asset(id: ref.assetID) {
                                    formalAssetCard(asset)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var topicMode: some View {
        if store.topicProjections.isEmpty {
            ContentUnavailableView("尚未确认正式主题", systemImage: "tag")
        } else {
            ForEach(store.topicProjections, id: \.id) { projection in
                DisclosureGroup("\(projection.topic.name) · \(projection.assets.count) 资产") {
                    ForEach(projection.segments, id: \.id) { segment in
                        Text("\(segment.title)：\(segment.summary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(projection.assets) { ref in
                        if let asset = store.asset(id: ref.assetID) {
                            formalAssetCard(asset)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var kindMode: some View {
        Picker("用途", selection: $kindUseFilter) {
            ForEach(KindUseFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        if store.kindProjections.isEmpty {
            ContentUnavailableView("尚未确认正式资产", systemImage: "books.vertical")
        } else {
            ForEach(store.kindProjections, id: \.id) { projection in
                let assets = projection.assets.filter(matchesKindUseFilter)
                if !assets.isEmpty {
                    DisclosureGroup("\(ChatStudyAssetKindLabel.title(for: projection.kind)) · \(assets.count)") {
                        ForEach(assets) { ref in
                            if let asset = store.asset(id: ref.assetID) {
                                formalAssetCard(asset)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func formalAssetCard(_ asset: ChatStudyAsset) -> some View {
        let version = asset.currentVersion
        ChatStudyAssetCard(
            title: asset.title,
            kind: asset.kind,
            subtype: asset.subtype,
            uses: asset.uses,
            preservation: version?.preservation ?? .distilled,
            origin: version?.origin ?? .skill,
            bodyText: version?.textSnapshot ?? "",
            isHighlighted: asset.isHighlighted,
            note: asset.note,
            sourceStatus: store.sourceStatus(for: asset),
            onOpenSource: nil,
            onShowVersions: { versionAssetID = asset.id },
            onEditVersion: {
                editText = version?.textSnapshot ?? ""
                editAssetID = asset.id
            }
        )
    }

    private func versionSheet(_ asset: ChatStudyAsset) -> some View {
        NavigationStack {
            List(asset.versions.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { version in
                VStack(alignment: .leading, spacing: 6) {
                    Text(version.id).font(.headline)
                    Text(version.createdAt).font(.caption).foregroundStyle(.secondary)
                    Text(version.textSnapshot)
                }
            }
            .navigationTitle("历史版本")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { versionAssetID = nil }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    private func filteredAssets(_ assets: [ChatStudyAssetRef]) -> [ChatStudyAssetRef] {
        assets.filter { ref in
            switch conversationFilter {
            case .all: return true
            case .finishedWork: return ref.kind == .finishedWork
            case .expressionModule: return ref.kind == .expressionModule
            case .sourceMaterial: return ref.kind == .sourceMaterial
            case .methodStrategy: return ref.kind == .methodStrategy
            case .viewpointKnowledge: return ref.kind == .viewpointKnowledge
            case .memorize: return ref.uses.contains(.memorize)
            }
        }
    }

    private func matchesKindUseFilter(_ ref: ChatStudyAssetRef) -> Bool {
        switch kindUseFilter {
        case .all: return true
        case .memorize: return ref.uses.contains(.memorize)
        case .imitate: return ref.uses.contains(.imitate)
        case .quote: return ref.uses.contains(.quote)
        case .practice: return ref.uses.contains(.practice)
        case .review: return ref.uses.contains(.review)
        }
    }
}

private struct Identified: Identifiable {
    var id: String
}
