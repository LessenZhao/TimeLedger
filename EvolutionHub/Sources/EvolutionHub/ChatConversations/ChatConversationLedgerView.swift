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
    @Binding var stageMode: ChatStageMode

    @State private var mode: LedgerProjectionMode = .conversation
    @State private var conversationFilter: ConversationAssetFilter = .all
    @State private var kindUseFilter: KindUseFilter = .all
    @State private var selectedAssetID: String?
    @State private var versionAssetID: String?
    @State private var editText = ""
    @State private var editBaseline = ""
    @State private var saveError: String?

    var body: some View {
        Group {
            if store.ledgerSchemaState == .requiresV1Migration {
                migrationBanner
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                HSplitView {
                    catalogPane
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
                    stagePane
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            ensureValidSelection()
            syncEditBuffer()
        }
        .onChange(of: mode) { _, _ in
            ensureValidSelection()
        }
        .onChange(of: conversationFilter) { _, _ in
            ensureValidSelection()
        }
        .onChange(of: kindUseFilter) { _, _ in
            ensureValidSelection()
        }
        .onChange(of: store.ledgerDocument.assets.map(\.id)) { _, _ in
            ensureValidSelection()
        }
        .onChange(of: selectedAssetID) { _, _ in
            syncEditBuffer()
            saveError = nil
            if stageMode == .source || stageMode == .excerpt {
                // keep source-oriented modes
            } else if stageMode == .edit {
                // keep editing
            } else {
                stageMode = .read
            }
        }
        .onChange(of: stageMode) { _, newMode in
            if newMode == .edit {
                syncEditBuffer()
            }
        }
        .sheet(item: Binding(
            get: { versionAssetID.map(Identified.init) },
            set: { versionAssetID = $0?.id }
        )) { item in
            if let asset = store.asset(id: item.id) {
                versionSheet(asset)
            }
        }
    }

    private var catalogPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("材料目录")
                    .font(.headline)

                Picker("投影", selection: $mode) {
                    ForEach(LedgerProjectionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                filterControl
            }
            .padding(14)

            Divider()

            if visibleCatalogAssetIDs.isEmpty {
                ContentUnavailableView(
                    "尚未确认正式内容",
                    systemImage: "checkmark.seal",
                    description: Text("确认候选后，这里会显示片段目录与备考资产。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        switch mode {
                        case .conversation:
                            conversationCatalog
                        case .topic:
                            topicCatalog
                        case .kind:
                            kindCatalog
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var filterControl: some View {
        switch mode {
        case .conversation:
            Picker("过滤", selection: $conversationFilter) {
                ForEach(ConversationAssetFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
        case .kind:
            Picker("用途", selection: $kindUseFilter) {
                ForEach(KindUseFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
        case .topic:
            EmptyView()
        }
    }

    @ViewBuilder
    private var stagePane: some View {
        if let selectedAssetID, let asset = store.asset(id: selectedAssetID) {
            VStack(spacing: 0) {
                ChatStageHeader(
                    mode: $stageMode,
                    title: asset.title,
                    subtitle: stageSubtitle(for: asset)
                )
                Divider()
                stageBody(asset)
            }
        } else {
            ContentUnavailableView(
                "选择一份材料",
                systemImage: "doc.richtext",
                description: Text("从左侧目录点选资产后，在这里阅读完整正文。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func stageSubtitle(for asset: ChatStudyAsset) -> String {
        switch stageMode {
        case .read: return "正式库 · 阅读"
        case .edit: return "正式库 · Markdown 源码编辑（保存=新版本）"
        case .source: return "正式库 · 原文大阅读"
        case .excerpt: return "正式库 · 选中摘录入库"
        }
    }

    @ViewBuilder
    private func stageBody(_ asset: ChatStudyAsset) -> some View {
        switch stageMode {
        case .read:
            formalReader(asset, showSourceButton: false)
        case .edit:
            formalEditor(asset)
        case .source, .excerpt:
            formalSourceStage(asset, excerptMode: stageMode == .excerpt)
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
    private var conversationCatalog: some View {
        ForEach(store.formalConversationProjections, id: \.id) { projection in
            let assets = filteredAssets(projection.assets)
            if !assets.isEmpty {
                catalogSection(
                    title: projection.title,
                    subtitle: "\(projection.segments.count) 片段 · \(assets.count) 资产"
                ) {
                    ForEach(projection.segments, id: \.id) { segment in
                        let segmentAssets = assets.filter { $0.segmentID == segment.id }
                        if !segmentAssets.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(segment.title)
                                        .font(.subheadline.weight(.semibold))
                                    if !segment.summary.isEmpty {
                                        Text(segment.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.horizontal, 4)

                                ForEach(segmentAssets) { ref in
                                    catalogAssetButton(ref)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var topicCatalog: some View {
        ForEach(store.topicProjections, id: \.id) { projection in
            if !projection.assets.isEmpty {
                catalogSection(
                    title: projection.topic.name,
                    subtitle: "\(projection.assets.count) 资产"
                ) {
                    ForEach(projection.assets) { ref in
                        catalogAssetButton(ref)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var kindCatalog: some View {
        ForEach(store.kindProjections, id: \.id) { projection in
            let assets = projection.assets.filter(matchesKindUseFilter)
            if !assets.isEmpty {
                catalogSection(
                    title: ChatStudyAssetKindLabel.title(for: projection.kind),
                    subtitle: "\(assets.count) 资产"
                ) {
                    ForEach(assets) { ref in
                        catalogAssetButton(ref)
                    }
                }
            }
        }
    }

    private func catalogSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            content()
        }
    }

    private func catalogAssetButton(_ ref: ChatStudyAssetRef) -> some View {
        Button {
            selectedAssetID = ref.assetID
        } label: {
            ChatStudyAssetCatalogRow(
                title: ref.title,
                kind: ref.kind,
                subtype: ref.subtype,
                uses: ref.uses,
                isHighlighted: ref.isHighlighted,
                isSelected: selectedAssetID == ref.assetID
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func formalReader(_ asset: ChatStudyAsset, showSourceButton: Bool) -> some View {
        let version = asset.currentVersion
        let sourceContext = store.formalSourceContext(for: asset)
        ChatStudyAssetReaderPane(
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
            // Secondary sheet entry only; primary is center-stage 「原文」.
            sourceView: showSourceButton ? sourceContext.map {
                ChatConversationSourceView(
                    store: store,
                    references: $0.references,
                    purpose: .evidence,
                    destination: $0.destination
                )
            } : nil,
            onShowVersions: { versionAssetID = asset.id },
            onEditVersion: {
                stageMode = .edit
                syncEditBuffer()
            }
        )
    }

    private func formalEditor(_ asset: ChatStudyAsset) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Markdown 源码")
                    .font(.headline)
                Text("保存将调用 appendUserEditedVersion，旧版本保留")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("放弃更改") {
                    syncEditBuffer()
                    saveError = nil
                }
                .disabled(editText == editBaseline)
                Button("保存为新版本") {
                    saveEditedVersion(assetID: asset.id)
                }
                .buttonStyle(.borderedProminent)
                .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || editText == editBaseline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }

            Divider()

            TextEditor(text: $editText)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func formalSourceStage(_ asset: ChatStudyAsset, excerptMode: Bool) -> some View {
        if let context = store.formalSourceContext(for: asset) {
            ChatConversationSourceStage(
                store: store,
                references: context.references,
                purpose: .evidence,
                destination: context.destination,
                allowsExcerpt: true,
                excerptMode: excerptMode
            )
        } else {
            ContentUnavailableView(
                "没有可打开的原文引用",
                systemImage: "text.badge.xmark",
                description: Text("该材料未绑定 sourceMessages，无法对照原文。仍可在阅读模式查看已确认快照。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func versionSheet(_ asset: ChatStudyAsset) -> some View {
        NavigationStack {
            List(asset.versions.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { version in
                VStack(alignment: .leading, spacing: 8) {
                    Text(version.id).font(.headline)
                    Text(version.createdAt).font(.caption).foregroundStyle(.secondary)
                    MarkdownBodyView(text: version.textSnapshot, bodyFontSize: 14)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("历史版本")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { versionAssetID = nil }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var visibleCatalogAssetIDs: [String] {
        switch mode {
        case .conversation:
            return store.formalConversationProjections
                .flatMap { filteredAssets($0.assets) }
                .map(\.assetID)
        case .topic:
            return store.topicProjections.flatMap(\.assets).map(\.assetID)
        case .kind:
            return store.kindProjections
                .flatMap { $0.assets.filter(matchesKindUseFilter) }
                .map(\.assetID)
        }
    }

    private func ensureValidSelection() {
        let ids = visibleCatalogAssetIDs
        if let selectedAssetID, ids.contains(selectedAssetID) {
            return
        }
        selectedAssetID = ids.first
        syncEditBuffer()
    }

    private func syncEditBuffer() {
        guard let selectedAssetID, let asset = store.asset(id: selectedAssetID) else {
            editText = ""
            editBaseline = ""
            return
        }
        let text = asset.currentVersion?.textSnapshot ?? ""
        editText = text
        editBaseline = text
    }

    private func saveEditedVersion(assetID: String) {
        do {
            try store.appendUserEditedVersion(assetID: assetID, text: editText)
            syncEditBuffer()
            saveError = nil
            stageMode = .read
        } catch {
            saveError = error.localizedDescription
        }
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
