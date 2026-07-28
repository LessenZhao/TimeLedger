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

struct ChatConversationLedgerView<LeftHeaderPrefix: View, RightHeaderTrailing: View>: View {
    @ObservedObject var store: ChatConversationHubStore
    @Binding var stageMode: ChatStageMode
    @ViewBuilder var leftHeaderPrefix: () -> LeftHeaderPrefix
    @ViewBuilder var rightHeaderTrailing: () -> RightHeaderTrailing

    @State private var mode: LedgerProjectionMode = .conversation
    @State private var conversationFilter: ConversationAssetFilter = .all
    @State private var kindUseFilter: KindUseFilter = .all
    @State private var selectedAssetID: String?
    @State private var focusedSegmentID: String?
    @State private var expandedGroupIDs: Set<String> = []
    @State private var versionAssetID: String?
    @State private var editText = ""
    @State private var editBaseline = ""
    @State private var saveError: String?

    init(
        store: ChatConversationHubStore,
        stageMode: Binding<ChatStageMode>,
        @ViewBuilder leftHeaderPrefix: @escaping () -> LeftHeaderPrefix = { EmptyView() },
        @ViewBuilder rightHeaderTrailing: @escaping () -> RightHeaderTrailing = { EmptyView() }
    ) {
        self.store = store
        self._stageMode = stageMode
        self.leftHeaderPrefix = leftHeaderPrefix
        self.rightHeaderTrailing = rightHeaderTrailing
    }

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
            expandAncestorsOfSelection(defaultExpandFirst: true)
            syncEditBuffer()
        }
        .onChange(of: mode) { _, _ in
            ensureValidSelection()
            expandAncestorsOfSelection(defaultExpandFirst: true)
        }
        .onChange(of: conversationFilter) { _, _ in
            ensureValidSelection()
            expandAncestorsOfSelection(defaultExpandFirst: false)
        }
        .onChange(of: kindUseFilter) { _, _ in
            ensureValidSelection()
            expandAncestorsOfSelection(defaultExpandFirst: false)
        }
        .onChange(of: store.ledgerDocument.assets.map(\.id)) { _, _ in
            ensureValidSelection()
            expandAncestorsOfSelection(defaultExpandFirst: false)
        }
        .onChange(of: selectedAssetID) { _, newID in
            if let newID {
                focusedSegmentID = store.asset(id: newID)?.segmentId
            }
            expandAncestorsOfSelection(defaultExpandFirst: false)
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
            HStack(spacing: 8) {
                leftHeaderPrefix()
                Picker("投影", selection: $mode) {
                    ForEach(LedgerProjectionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
                .controlSize(.small)
                filterControl
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .frame(height: ChatChromeMetrics.headerHeight)
            .background(Color(nsColor: .windowBackgroundColor))

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
                    LazyVStack(alignment: .leading, spacing: 12) {
                        switch mode {
                        case .conversation:
                            conversationCatalog
                        case .topic:
                            topicCatalog
                        case .kind:
                            kindCatalog
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
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
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 100)
        case .kind:
            Picker("用途", selection: $kindUseFilter) {
                ForEach(KindUseFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 100)
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
                ) {
                    if stageMode == .source || stageMode == .excerpt {
                        SourceCatalogToggle()
                    }
                    rightHeaderTrailing()
                }
                Divider()
                stageBody(asset)
            }
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("选择左侧材料")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    rightHeaderTrailing()
                }
                .padding(.horizontal, 12)
                .frame(height: ChatChromeMetrics.headerHeight)
                .background(Color(nsColor: .windowBackgroundColor))
                Divider()
                ContentUnavailableView(
                    "选择一份材料",
                    systemImage: "doc.richtext",
                    description: Text("从左侧目录点选资产后，在这里阅读完整正文。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private func stageSubtitle(for asset: ChatStudyAsset) -> String? {
        switch stageMode {
        case .read: return nil
        case .edit: return "保存=新版本"
        case .source: return "原文对照"
        case .excerpt: return "选中摘录"
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
                let groupID = "conversation:\(projection.id)"
                let isExpanded = expandedGroupIDs.contains(groupID)
                let segments = orderedSegments(projection.segments, assets: assets)
                VStack(alignment: .leading, spacing: 0) {
                    CatalogTreeGroupHeader(
                        title: projection.title,
                        subtitle: "\(segments.count) 片段 · \(assets.count) 资产",
                        isExpanded: isExpanded,
                        icon: "bubble.left.and.bubble.right.fill",
                        onToggle: { toggleGroup(groupID, exclusive: true) }
                    )

                    if isExpanded {
                        CatalogTreeBranch {
                            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                                let segmentAssets = assets.filter { $0.segmentID == segment.id }
                                if !segmentAssets.isEmpty {
                                    let isFocused = focusedSegmentID == segment.id
                                    CatalogTreeSegmentRow(
                                        index: index + 1,
                                        title: segment.title,
                                        meta: "\(segmentAssets.count) 资产",
                                        isFocused: isFocused,
                                        isExpanded: isFocused,
                                        action: {
                                            focusedSegmentID = segment.id
                                            if let first = segmentAssets.first {
                                                selectedAssetID = first.assetID
                                            }
                                        }
                                    )
                                    // L3 only under the active segment — keeps the TOC readable.
                                    if isFocused {
                                        ForEach(segmentAssets) { ref in
                                            catalogAssetButton(ref, indent: 36)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var topicCatalog: some View {
        ForEach(store.topicProjections, id: \.id) { projection in
            if !projection.assets.isEmpty {
                let groupID = "topic:\(projection.id)"
                let isExpanded = expandedGroupIDs.contains(groupID)
                let segments = orderedSegments(projection.segments, assets: projection.assets)
                VStack(alignment: .leading, spacing: 0) {
                    CatalogTreeGroupHeader(
                        title: projection.topic.name,
                        subtitle: "\(projection.assets.count) 资产",
                        isExpanded: isExpanded,
                        icon: "tag.fill",
                        onToggle: { toggleGroup(groupID, exclusive: true) }
                    )
                    if isExpanded {
                        CatalogTreeBranch {
                            if segments.isEmpty {
                                ForEach(projection.assets) { ref in
                                    catalogAssetButton(ref, indent: 22)
                                }
                            } else {
                                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                                    let segmentAssets = projection.assets.filter { $0.segmentID == segment.id }
                                    if !segmentAssets.isEmpty {
                                        let isFocused = focusedSegmentID == segment.id
                                        CatalogTreeSegmentRow(
                                            index: index + 1,
                                            title: segment.title,
                                            meta: "\(segmentAssets.count) 资产",
                                            isFocused: isFocused,
                                            isExpanded: isFocused,
                                            action: {
                                                focusedSegmentID = segment.id
                                                if let first = segmentAssets.first {
                                                    selectedAssetID = first.assetID
                                                }
                                            }
                                        )
                                        if isFocused {
                                            ForEach(segmentAssets) { ref in
                                                catalogAssetButton(ref, indent: 36)
                                            }
                                        }
                                    }
                                }
                                let known = Set(segments.map(\.id))
                                let orphans = projection.assets.filter { !known.contains($0.segmentID) }
                                ForEach(orphans) { ref in
                                    catalogAssetButton(ref, indent: 22)
                                }
                            }
                        }
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var kindCatalog: some View {
        ForEach(store.kindProjections, id: \.id) { projection in
            let assets = projection.assets.filter(matchesKindUseFilter)
            if !assets.isEmpty {
                let groupID = "kind:\(projection.id)"
                let isExpanded = expandedGroupIDs.contains(groupID)
                VStack(alignment: .leading, spacing: 0) {
                    CatalogTreeGroupHeader(
                        title: ChatStudyAssetKindLabel.title(for: projection.kind),
                        subtitle: "\(assets.count) 资产",
                        isExpanded: isExpanded,
                        icon: "square.grid.2x2.fill",
                        onToggle: { toggleGroup(groupID, exclusive: false) }
                    )
                    if isExpanded {
                        CatalogTreeBranch {
                            ForEach(assets) { ref in
                                catalogAssetButton(ref, indent: 22)
                            }
                        }
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    private func catalogAssetButton(_ ref: ChatStudyAssetRef, indent: CGFloat = 28) -> some View {
        CatalogTreeAssetRow(
            title: ref.title,
            kind: ref.kind,
            uses: ref.uses,
            isHighlighted: ref.isHighlighted,
            isSelected: selectedAssetID == ref.assetID,
            indent: indent,
            action: {
                selectedAssetID = ref.assetID
                focusedSegmentID = ref.segmentID
            }
        )
    }

    private func toggleGroup(_ id: String, exclusive: Bool) {
        if expandedGroupIDs.contains(id) {
            expandedGroupIDs.remove(id)
            return
        }
        if exclusive {
            // Accordion: only one L1 group open in conversation/topic modes.
            let prefix: String
            if id.hasPrefix("conversation:") {
                prefix = "conversation:"
            } else if id.hasPrefix("topic:") {
                prefix = "topic:"
            } else {
                prefix = ""
            }
            if !prefix.isEmpty {
                expandedGroupIDs = expandedGroupIDs.filter { !$0.hasPrefix(prefix) }
            }
        }
        expandedGroupIDs.insert(id)
    }

    private func orderedSegments(
        _ segments: [ChatConversationSegment],
        assets: [ChatStudyAssetRef]
    ) -> [ChatConversationSegment] {
        let assetSegmentIDs = Set(assets.map(\.segmentID))
        return segments.filter { assetSegmentIDs.contains($0.id) }
    }

    private func visibleSegmentCount(
        _ segments: [ChatConversationSegment],
        assets: [ChatStudyAssetRef]
    ) -> Int {
        orderedSegments(segments, assets: assets).count
    }

    private func expandAncestorsOfSelection(defaultExpandFirst: Bool) {
        switch mode {
        case .conversation:
            let projections = store.formalConversationProjections.filter {
                !filteredAssets($0.assets).isEmpty
            }
            let target: String?
            if let selectedAssetID,
               let match = projections.first(where: {
                   filteredAssets($0.assets).contains(where: { $0.assetID == selectedAssetID })
               }) {
                target = "conversation:\(match.id)"
            } else if defaultExpandFirst, let first = projections.first {
                target = "conversation:\(first.id)"
            } else {
                target = expandedGroupIDs.first(where: { $0.hasPrefix("conversation:") })
            }
            // Accordion: keep only the active conversation open.
            var next = expandedGroupIDs.filter { !$0.hasPrefix("conversation:") }
            if let target { next.insert(target) }
            expandedGroupIDs = next

        case .topic:
            let projections = store.topicProjections.filter { !$0.assets.isEmpty }
            let target: String?
            if let selectedAssetID,
               let match = projections.first(where: { $0.assets.contains(where: { $0.assetID == selectedAssetID }) }) {
                target = "topic:\(match.id)"
            } else if defaultExpandFirst, let first = projections.first {
                target = "topic:\(first.id)"
            } else {
                target = expandedGroupIDs.first(where: { $0.hasPrefix("topic:") })
            }
            var next = expandedGroupIDs.filter { !$0.hasPrefix("topic:") }
            if let target { next.insert(target) }
            expandedGroupIDs = next

        case .kind:
            var next = expandedGroupIDs
            let projections = store.kindProjections.compactMap { projection -> ChatConversationKindProjection? in
                let assets = projection.assets.filter(matchesKindUseFilter)
                return assets.isEmpty ? nil : ChatConversationKindProjection(kind: projection.kind, assets: assets)
            }
            if let selectedAssetID,
               let match = projections.first(where: { $0.assets.contains(where: { $0.assetID == selectedAssetID }) }) {
                next.insert("kind:\(match.id)")
            } else if defaultExpandFirst, let first = projections.first {
                next.insert("kind:\(first.id)")
            }
            expandedGroupIDs = next
        }
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
            HStack(spacing: 10) {
                Text("Markdown 源码")
                    .font(.subheadline.weight(.semibold))
                Text("旧版本保留")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("放弃更改") {
                    syncEditBuffer()
                    saveError = nil
                }
                .controlSize(.small)
                .disabled(editText == editBaseline)
                Button("保存为新版本") {
                    saveEditedVersion(assetID: asset.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || editText == editBaseline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

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
                excerptMode: excerptMode,
                showsToolbar: false
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
            if focusedSegmentID == nil {
                focusedSegmentID = store.asset(id: selectedAssetID)?.segmentId
            }
            return
        }
        selectedAssetID = ids.first
        focusedSegmentID = ids.first.flatMap { store.asset(id: $0)?.segmentId }
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
