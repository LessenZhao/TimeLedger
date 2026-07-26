import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct WorkEvolutionDayView: View {
    @EnvironmentObject private var store: WorkEvolutionHubStore
    let dateKey: String

    @State private var composerContext: UserAnnotationComposerContext?
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                if let actionError {
                    Label(actionError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if day != nil {
                    dayOverview
                }
                projectValueSection
                if day?.independentThoughts.isEmpty == false {
                    independentThoughtSection
                }
                if !recognizedNodes.isEmpty {
                    recognizedLaterSection
                }
                if !recognizedAnnotations.isEmpty {
                    userContentSection
                }
                sourceSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .sheet(item: $composerContext) { context in
            UserAnnotationComposer(context: context)
                .environmentObject(store)
        }
    }

    private var day: WorkEvolutionDayRecord? {
        store.snapshot.days.first { $0.date == dateKey }
    }

    private var recognizedNodes: [EvolutionNode] {
        store.snapshot.nodes
            .filter { EvolutionUIDate.dayKey($0.recognizedAt) == dateKey }
            .sorted {
                if $0.recognizedAt != $1.recognizedAt { return $0.recognizedAt < $1.recognizedAt }
                return $0.id < $1.id
            }
    }

    private var recognizedAnnotations: [UserAnnotation] {
        store.snapshot.annotations
            .filter { EvolutionUIDate.dayKey($0.recognizedAt) == dateKey }
            .sorted {
                if $0.recognizedAt != $1.recognizedAt { return $0.recognizedAt < $1.recognizedAt }
                return $0.id < $1.id
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(dateKey)
                    .font(.largeTitle.bold())
                Spacer()
                if let day {
                    if day.reviewState == .candidate {
                        Button("确认当天") { confirmDay() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        ReviewStateBadge(state: day.reviewState)
                    }
                    Button {
                        composerContext = UserAnnotationComposerContext(
                            target: AnnotationTarget(kind: .day, targetId: dateKey),
                            targetSummary: "日期：\(dateKey)",
                            entryLabel: "补充当天"
                        )
                    } label: {
                        Label("补充当天", systemImage: "square.and.pencil")
                    }
                } else {
                    Text("识别记录日")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.12), in: Capsule())
                }
            }
            if let day {
                Text("来源截止：\(EvolutionUIDate.timestamp(day.sourceCutoffAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("当天没有项目动作，但有后来认识或用户补充。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dayOverview: some View {
        let slices = (day?.projectSlices ?? []).sorted(by: sliceOrdering)
        let decisions = slices.flatMap(\.decisions)
        let realizedValues = slices
            .flatMap(\.values)
            .filter { $0.status == .realized }
            .sorted(by: valueOrdering)
        let primaryValue = realizedValues.first

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("今日结论")
                    .font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    SummaryMetric(value: slices.count, label: "项目")
                    SummaryMetric(value: decisions.count, label: "关键决策")
                    SummaryMetric(value: realizedValues.count, label: "已实现价值")
                }
            }

            if let primaryValue {
                Text(primaryValue.title)
                    .font(.title2.bold())
                    .textSelection(.enabled)
                Text(primaryValue.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            } else if let progress = slices.first?.progress.nonEmpty {
                Text(progress)
                    .font(.title3.weight(.semibold))
                    .lineSpacing(3)
                    .textSelection(.enabled)
            } else {
                Text("当天尚未形成已实现价值。")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.13), Color.accentColor.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor.opacity(0.20)))
    }

    private var projectValueSection: some View {
        LedgerSection(title: "项目进展", systemImage: "square.stack.3d.up") {
            let slices = (day?.projectSlices ?? []).sorted(by: sliceOrdering)
            if slices.isEmpty {
                EmptyLedgerMessage(text: "当天没有项目价值切片。")
            } else {
                ForEach(slices) { slice in
                    ProjectValueCard(
                        slice: slice,
                        project: project(for: slice.projectId),
                        onAnnotate: {
                            composerContext = UserAnnotationComposerContext(
                                target: AnnotationTarget(kind: .projectDaySlice, targetId: slice.id),
                                targetSummary: "\(dateKey) · \(slice.purpose)",
                                entryLabel: "补充这个切片"
                            )
                        }
                    )
                }
            }
        }
    }

    private var independentThoughtSection: some View {
        CollapsibleLedgerSection(
            title: "独立思考 / 跨项目价值",
            systemImage: "lightbulb.max",
            count: day?.independentThoughts.count ?? 0
        ) {
            let thoughts = (day?.independentThoughts ?? []).sorted { ($0.title, $0.id) < ($1.title, $1.id) }
            if thoughts.isEmpty {
                EmptyLedgerMessage(text: "当天没有独立思考记录。")
            } else {
                ForEach(thoughts) { thought in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(thought.title).font(.headline)
                            FactLevelBadge(level: thought.factLevel)
                        }
                        Text(thought.body).textSelection(.enabled)
                        if !thought.decisions.isEmpty {
                            RecordGroup(title: "决策") {
                                ForEach(thought.decisions.sorted(by: decisionOrdering)) { decision in
                                    DecisionRow(decision: decision)
                                }
                            }
                        }
                        if !thought.learnings.isEmpty {
                            RecordGroup(title: "方法 / 教训") {
                                ForEach(thought.learnings.sorted(by: learningOrdering)) { learning in
                                    LearningRow(learning: learning)
                                }
                            }
                        }
                        ValueGroups(values: thought.values)
                    }
                    .ledgerCard()
                }
            }
        }
    }

    private var recognizedLaterSection: some View {
        CollapsibleLedgerSection(
            title: "后来认识",
            systemImage: "clock.arrow.circlepath",
            count: recognizedNodes.count
        ) {
            if recognizedNodes.isEmpty {
                EmptyLedgerMessage(text: "当天没有新增的演化认识。")
            } else {
                ForEach(recognizedNodes) { node in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(node.title).font(.headline)
                            Text(node.kind.rawValue)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.purple.opacity(0.12), in: Capsule())
                            Spacer()
                            FactLevelBadge(level: node.factLevel)
                            if node.reviewState == .candidate {
                                Button("确认节点") { confirmNode(node.id) }
                            } else {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                                    .help("已确认")
                            }
                            Button {
                                composerContext = UserAnnotationComposerContext(
                                    target: AnnotationTarget(kind: .evolutionNode, targetId: node.id),
                                    targetSummary: "节点：\(node.title)",
                                    entryLabel: "补充这个节点"
                                )
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .help("补充这个节点")
                        }
                        Text(node.detail).textSelection(.enabled)
                        if !node.reason.isEmpty {
                            LabeledContent("原因", value: node.reason)
                        }
                        LabeledContent("实际发生", value: EvolutionUIDate.timestamp(node.happenedAt))
                        if EvolutionUIDate.dayKey(node.happenedAt) != dateKey {
                            Text("于 \(dateKey) 才被认识并记录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .ledgerCard()
                }
            }
        }
    }

    private var userContentSection: some View {
        CollapsibleLedgerSection(
            title: "用户内容",
            systemImage: "person.text.rectangle",
            count: recognizedAnnotations.count
        ) {
            if recognizedAnnotations.isEmpty {
                EmptyLedgerMessage(text: "当天没有用户补充、纠正或后来认识。")
            } else {
                ForEach(recognizedAnnotations) { annotation in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(annotationKindLabel(annotation.kind))
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(EvolutionUIDate.timestamp(annotation.recognizedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(annotation.body).textSelection(.enabled)
                        Text("关联：\(annotation.target.kind.rawValue) / \(annotation.target.targetId)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if let happenedAt = annotation.happenedAt {
                            Text("实际发生：\(EvolutionUIDate.timestamp(happenedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .ledgerCard()
                }
            }
        }
    }

    private var sourceSection: some View {
        CollapsibleLedgerSection(
            title: "来源会话",
            systemImage: "text.quote",
            count: day?.sourceSlices.count ?? 0
        ) {
            if let coverage = day?.coverage {
                HStack(spacing: 8) {
                    CoverageBadge(title: "纳入", count: coverage.includedSessionIds.count, color: .green)
                    CoverageBadge(title: "待定", count: coverage.pendingSessionIds.count, color: .orange)
                    CoverageBadge(title: "排除", count: coverage.excludedSessionIds.count, color: .secondary)
                    CoverageBadge(title: "处理任务", count: coverage.processorSessionIds.count, color: .blue)
                    Spacer()
                    Text("应有 \(coverage.expectedSessionCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            let slices = (day?.sourceSlices ?? []).sorted(by: sourceSliceOrdering)
            if slices.isEmpty {
                EmptyLedgerMessage(text: "当天没有来源会话；后来认识和用户内容仍会保留。")
            } else {
                ForEach(slices) { slice in
                    HStack(spacing: 6) {
                        Button {
                            store.selectedSourceSessionId = slice.sessionId
                        } label: {
                            SourceSessionRow(
                                slice: slice,
                                session: session(for: slice.sessionId),
                                isSelected: store.selectedSourceSessionId == slice.sessionId
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            composerContext = UserAnnotationComposerContext(
                                target: AnnotationTarget(kind: .sourceSession, targetId: slice.sessionId),
                                targetSummary: "来源：\(session(for: slice.sessionId)?.title ?? slice.sessionId)",
                                entryLabel: "补充这个来源"
                            )
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("补充这个来源")
                    }
                }
            }
        }
    }

    private func project(for id: String) -> EvolutionProject? {
        store.snapshot.projects.first { $0.id == id }
    }

    private func session(for id: String) -> SourceSessionRecord? {
        store.snapshot.sourceSessions.first { $0.id == id }
    }

    private func sliceOrdering(_ lhs: ProjectDaySlice, _ rhs: ProjectDaySlice) -> Bool {
        let left = project(for: lhs.projectId)?.name ?? lhs.projectId
        let right = project(for: rhs.projectId)?.name ?? rhs.projectId
        return (left, lhs.id) < (right, rhs.id)
    }

    private func sourceSliceOrdering(_ lhs: DailySessionSlice, _ rhs: DailySessionSlice) -> Bool {
        let left = session(for: lhs.sessionId)?.title ?? lhs.sessionId
        let right = session(for: rhs.sessionId)?.title ?? rhs.sessionId
        return (lhs.classification.rawValue, left, lhs.id) < (rhs.classification.rawValue, right, rhs.id)
    }

    private func confirmDay() {
        do {
            // Coverage may still contain pending sessions; confirmation locks the
            // reviewed day without pretending those sources were classified.
            try store.confirmDay(dateKey)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func confirmNode(_ id: String) {
        do {
            try store.confirmNode(id)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct ProjectValueCard: View {
    let slice: ProjectDaySlice
    let project: EvolutionProject?
    let onAnnotate: () -> Void

    @State private var isExpanded = false

    private var orderedDecisions: [DecisionRecord] {
        slice.decisions.sorted(by: decisionOrdering)
    }

    private var orderedLearnings: [LearningRecord] {
        slice.learnings.sorted(by: learningOrdering)
    }

    private var orderedValues: [ValueRecord] {
        slice.values.sorted(by: valueOrdering)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(project?.name ?? slice.projectId)
                    .font(.title2.bold())
                ProjectProgressBadge(status: project?.progressStatus)
                Spacer()
                ReviewStateBadge(state: slice.reviewState)
                Button(action: onAnnotate) {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("补充这个项目切片")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("目标")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(slice.purpose)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 7) {
                Label("当前结果", systemImage: "flag.checkered")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Text(slice.progress)
                    .font(.body.weight(.medium))
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))

            if let decision = orderedDecisions.first {
                VStack(alignment: .leading, spacing: 6) {
                    Label("关键变化", systemImage: "arrow.triangle.branch")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(decision.title)
                        .font(.headline)
                    Text(decision.decision)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                    Text("为什么：\(decision.reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
            }

            if !orderedValues.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("今日价值", systemImage: "diamond.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(orderedValues) { value in
                        ValueSummaryRow(value: value)
                    }
                }
            }

            Divider()

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 18) {
                    if !slice.actions.isEmpty {
                        RecordGroup(title: "完整动作") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(slice.actions.sorted(), id: \.self) { action in
                                    Label(action, systemImage: "circle.fill")
                                        .labelStyle(BulletLabelStyle())
                                        .lineSpacing(2)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }

                    if !orderedDecisions.isEmpty {
                        RecordGroup(title: "全部决策及原因") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(orderedDecisions) { decision in
                                    DecisionRow(decision: decision)
                                }
                            }
                        }
                    }

                    if !orderedLearnings.isEmpty {
                        RecordGroup(title: "错误 / 假设变化 / 可复用方法") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(orderedLearnings) { learning in
                                    LearningRow(learning: learning)
                                }
                            }
                        }
                    }

                    HStack {
                        FactLevelBadge(level: slice.factLevel)
                        Text("详细内容来自完整会话和工作树证据")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 12)
            } label: {
                Label(
                    isExpanded ? "收起详细过程" : "展开详细过程",
                    systemImage: isExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
                )
                .font(.subheadline.weight(.semibold))
            }
        }
        .ledgerCard()
    }
}

private struct ValueSummaryRow: View {
    let value: ValueRecord

    private var color: Color {
        switch value.status {
        case .realized: return .green
        case .pending: return .orange
        case .notFormed: return .secondary
        }
    }

    private var systemImage: String {
        switch value.status {
        case .realized: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .notFormed: return "minus.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(value.title)
                        .font(.subheadline.weight(.semibold))
                    Text(valueKindLabel(value.kind))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }
                Text(value.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Text(valueStatusLabel(value.status))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}

private struct DecisionRow: View {
    let decision: DecisionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(decision.title).font(.subheadline.weight(.semibold))
            Text(decision.decision).textSelection(.enabled)
            Text("原因：\(decision.reason)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private struct LearningRow: View {
    let learning: LearningRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(learningKindLabel(learning.kind))：\(learning.observation)")
                .font(.subheadline.weight(.semibold))
                .textSelection(.enabled)
            Text("得到：\(learning.lesson)").textSelection(.enabled)
            if let principle = learning.reusablePrinciple, !principle.isEmpty {
                Text("可复用原则：\(principle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct ValueGroups: View {
    let values: [ValueRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            valueGroup(.project, title: "项目本身价值")
            valueGroup(.process, title: "过程价值")
            valueGroup(.crossProject, title: "跨项目价值")
        }
    }

    @ViewBuilder
    private func valueGroup(_ kind: ValueKind, title: String) -> some View {
        let records = values.filter { $0.kind == kind }.sorted { ($0.title, $0.id) < ($1.title, $1.id) }
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            if records.isEmpty {
                Text("未形成").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(records) { value in
                    HStack(alignment: .top) {
                        Text(value.title + "：" + value.detail)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        Text(valueStatusLabel(value.status))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(value.status == .realized ? .green : .secondary)
                    }
                }
            }
        }
    }
}

private struct SourceSessionRow: View {
    let slice: DailySessionSlice
    let session: SourceSessionRecord?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session?.title.nonEmpty ?? slice.sessionId)
                        .font(.subheadline.weight(.semibold))
                    SourceClassificationBadge(classification: slice.classification)
                }
                Text(slice.sessionId)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(sourceExplanation(slice))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("当天消息 \(slice.messageReferences.count) 条")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

private struct LedgerSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage).font(.title3.bold())
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CollapsibleLedgerSection<Content: View>: View {
    let title: String
    let systemImage: String
    let count: Int
    let content: Content

    @State private var isExpanded = false

    init(
        title: String,
        systemImage: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.headline)
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
                Spacer()
                Text(isExpanded ? "收起" : "查看")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.10)))
    }
}

private struct SummaryMetric: View {
    let value: Int
    let label: String

    var body: some View {
        Text("\(value) \(label)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.75), in: Capsule())
    }
}

private struct ProjectProgressBadge: View {
    let status: ProjectProgressStatus?

    private var label: String {
        switch status {
        case .exploring: return "探索中"
        case .active: return "进行中"
        case .paused: return "已暂停"
        case .ended: return "已结束"
        case nil: return "状态未知"
        }
    }

    private var color: Color {
        switch status {
        case .exploring: return .blue
        case .active: return .green
        case .paused: return .orange
        case .ended, nil: return .secondary
        }
    }

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(Color.secondary)
            configuration.title
        }
    }
}

private struct RecordGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            content
        }
    }
}

private struct EmptyLedgerMessage: View {
    let text: String
    var body: some View {
        Text(text).foregroundStyle(.secondary).padding(.vertical, 4)
    }
}

private struct ReviewStateBadge: View {
    let state: ReviewState
    var body: some View {
        Label(state == .confirmed ? "已确认" : "候选", systemImage: state == .confirmed ? "lock.fill" : "circle.dashed")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

private struct FactLevelBadge: View {
    let level: FactLevel
    var body: some View {
        Text(level.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

private struct CoverageBadge: View {
    let title: String
    let count: Int
    let color: Color
    var body: some View {
        Text("\(title) \(count)")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct SourceClassificationBadge: View {
    let classification: DailySourceClassification
    var body: some View {
        Text(sourceClassificationLabel(classification))
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(classificationColor(classification).opacity(0.12), in: Capsule())
    }
}

private extension View {
    func ledgerCard() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.12)))
    }
}

private func decisionOrdering(_ lhs: DecisionRecord, _ rhs: DecisionRecord) -> Bool {
    (lhs.title, lhs.id) < (rhs.title, rhs.id)
}

private func learningOrdering(_ lhs: LearningRecord, _ rhs: LearningRecord) -> Bool {
    (lhs.kind.rawValue, lhs.observation, lhs.id) < (rhs.kind.rawValue, rhs.observation, rhs.id)
}

private func valueOrdering(_ lhs: ValueRecord, _ rhs: ValueRecord) -> Bool {
    let statusRank: [ValueRealizationStatus: Int] = [.realized: 0, .pending: 1, .notFormed: 2]
    let kindRank: [ValueKind: Int] = [.project: 0, .process: 1, .crossProject: 2]
    let leftStatus = statusRank[lhs.status] ?? 3
    let rightStatus = statusRank[rhs.status] ?? 3
    if leftStatus != rightStatus { return leftStatus < rightStatus }
    let leftKind = kindRank[lhs.kind] ?? 3
    let rightKind = kindRank[rhs.kind] ?? 3
    if leftKind != rightKind { return leftKind < rightKind }
    return (lhs.title, lhs.id) < (rhs.title, rhs.id)
}

private func sourceClassificationLabel(_ classification: DailySourceClassification) -> String {
    switch classification {
    case .project: return "项目"
    case .crossProject: return "跨项目"
    case .independentThought: return "独立思考"
    case .pending: return "待定"
    case .excluded: return "排除"
    case .processor: return "处理任务"
    }
}

private func classificationColor(_ classification: DailySourceClassification) -> Color {
    switch classification {
    case .project, .crossProject, .independentThought: return .green
    case .pending: return .orange
    case .excluded: return .secondary
    case .processor: return .blue
    }
}

private func sourceExplanation(_ slice: DailySessionSlice) -> String {
    switch slice.classification {
    case .processor:
        return "处理任务"
    case .pending, .excluded:
        return slice.exclusionReason?.nonEmpty ?? "待人工说明"
    case .project, .crossProject, .independentThought:
        return slice.exclusionReason?.nonEmpty ?? "已纳入当天沉淀"
    }
}

private func learningKindLabel(_ kind: LearningKind) -> String {
    switch kind {
    case .mistake: return "错误"
    case .failedAssumption: return "假设变化"
    case .constraint: return "约束"
    case .reusableMethod: return "可复用方法"
    }
}

private func valueStatusLabel(_ status: ValueRealizationStatus) -> String {
    switch status {
    case .realized: return "已实现"
    case .pending: return "待验证"
    case .notFormed: return "未形成"
    }
}

private func valueKindLabel(_ kind: ValueKind) -> String {
    switch kind {
    case .project: return "项目"
    case .process: return "流程"
    case .crossProject: return "跨项目"
    }
}

private func annotationKindLabel(_ kind: AnnotationKind) -> String {
    switch kind {
    case .supplement: return "补充"
    case .correction: return "纠正"
    case .reflection: return "后来认识"
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
