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
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                if let actionError {
                    Label(actionError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                projectValueSection
                independentThoughtSection
                recognizedLaterSection
                userContentSection
                sourceSection
            }
            .padding(20)
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
        VStack(alignment: .leading, spacing: 8) {
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

    private var projectValueSection: some View {
        LedgerSection(title: "当天产生的价值", systemImage: "sparkles") {
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
        LedgerSection(title: "独立思考 / 跨项目价值", systemImage: "lightbulb.max") {
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
        LedgerSection(title: "后来认识", systemImage: "clock.arrow.circlepath") {
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
        LedgerSection(title: "用户内容", systemImage: "person.text.rectangle") {
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
        LedgerSection(title: "来源 \(day?.sourceSlices.count ?? 0) 个", systemImage: "text.quote") {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(project?.name ?? slice.projectId).font(.title3.bold())
                FactLevelBadge(level: slice.factLevel)
                Spacer()
                Text(slice.reviewState == .confirmed ? "已确认" : "候选")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: onAnnotate) {
                    Label("补充切片", systemImage: "square.and.pencil")
                }
            }
            LabeledContent("目的", value: slice.purpose)
            if !slice.actions.isEmpty {
                RecordGroup(title: "动作") {
                    ForEach(slice.actions.sorted(), id: \.self) { action in
                        Text("• \(action)").textSelection(.enabled)
                    }
                }
            }
            LabeledContent("进展", value: slice.progress)
            RecordGroup(title: "决策") {
                if slice.decisions.isEmpty {
                    Text("无").foregroundStyle(.secondary)
                } else {
                    ForEach(slice.decisions.sorted(by: decisionOrdering)) { decision in
                        DecisionRow(decision: decision)
                    }
                }
            }
            RecordGroup(title: "错误 / 假设变化 / 方法") {
                if slice.learnings.isEmpty {
                    Text("无").foregroundStyle(.secondary)
                } else {
                    ForEach(slice.learnings.sorted(by: learningOrdering)) { learning in
                        LearningRow(learning: learning)
                    }
                }
            }
            ValueGroups(values: slice.values)
        }
        .ledgerCard()
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
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.title2.bold())
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12)))
    }
}

private func decisionOrdering(_ lhs: DecisionRecord, _ rhs: DecisionRecord) -> Bool {
    (lhs.title, lhs.id) < (rhs.title, rhs.id)
}

private func learningOrdering(_ lhs: LearningRecord, _ rhs: LearningRecord) -> Bool {
    (lhs.kind.rawValue, lhs.observation, lhs.id) < (rhs.kind.rawValue, rhs.observation, rhs.id)
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
