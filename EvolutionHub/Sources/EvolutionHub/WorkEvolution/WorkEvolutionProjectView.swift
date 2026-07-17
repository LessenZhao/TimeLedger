import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct WorkEvolutionProjectView: View {
    @EnvironmentObject private var store: WorkEvolutionHubStore
    let projectId: String

    @State private var composerContext: UserAnnotationComposerContext?
    @State private var actionError: String?

    var body: some View {
        Group {
            if let project {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        projectHeader(project)
                        if let actionError {
                            Label(actionError, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                        statusSection(project)
                        routeSection(project)
                        nodeSection
                        contributionSection
                        userContentSection
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            } else {
                ContentUnavailableView("找不到项目", systemImage: "square.stack.3d.up.slash")
            }
        }
        .sheet(item: $composerContext) { context in
            UserAnnotationComposer(context: context)
                .environmentObject(store)
        }
    }

    private var project: EvolutionProject? {
        store.snapshot.projects.first { $0.id == projectId }
    }

    private var nodes: [EvolutionNode] {
        store.snapshot.nodes
            .filter { $0.projectId == projectId }
            .sorted {
                if $0.happenedAt != $1.happenedAt { return $0.happenedAt < $1.happenedAt }
                if $0.recognizedAt != $1.recognizedAt { return $0.recognizedAt < $1.recognizedAt }
                return $0.id < $1.id
            }
    }

    private var contributions: [(day: WorkEvolutionDayRecord, slice: ProjectDaySlice)] {
        store.snapshot.days
            .flatMap { day in day.projectSlices.filter { $0.projectId == projectId }.map { (day, $0) } }
            .sorted {
                if $0.day.date != $1.day.date { return $0.day.date > $1.day.date }
                return $0.slice.id < $1.slice.id
            }
    }

    private var projectAnnotations: [UserAnnotation] {
        let nodeIds = Set(nodes.map(\.id))
        let sliceIds = Set(contributions.map(\.slice.id))
        let sourceSessionIds = Set(
            store.snapshot.days.flatMap(\.sourceSlices).compactMap { slice in
                slice.projectIds.contains(projectId) ? slice.sessionId : nil
            }
        )
        return store.snapshot.annotations.filter { annotation in
            switch annotation.target.kind {
            case .project:
                return annotation.target.targetId == projectId
            case .projectDaySlice:
                return sliceIds.contains(annotation.target.targetId)
            case .evolutionNode:
                return nodeIds.contains(annotation.target.targetId)
            case .sourceSession:
                return sourceSessionIds.contains(annotation.target.targetId)
            case .day:
                return false
            }
        }
        .sorted {
            if $0.recognizedAt != $1.recognizedAt { return $0.recognizedAt < $1.recognizedAt }
            return $0.id < $1.id
        }
    }

    private func projectHeader(_ project: EvolutionProject) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.name).font(.largeTitle.bold())
                Spacer()
                if project.reviewState == .candidate {
                    Button("确认项目") { confirmProject(project.id) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Label("已确认", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                }
                Button {
                    composerContext = UserAnnotationComposerContext(
                        target: AnnotationTarget(kind: .project, targetId: project.id),
                        targetSummary: "项目：\(project.name)",
                        entryLabel: "补充项目"
                    )
                } label: {
                    Label("补充项目", systemImage: "square.and.pencil")
                }
            }
            Text(project.goal)
                .font(.title3)
                .textSelection(.enabled)
            if !project.aliases.isEmpty {
                Text("别名：\(project.aliases.sorted().joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func statusSection(_ project: EvolutionProject) -> some View {
        ProjectSection(title: "当前状态", systemImage: "gauge.with.dots.needle.33percent") {
            HStack(spacing: 10) {
                ProjectStatusCard(title: "进展", value: progressLabel(project.progressStatus))
                ProjectStatusCard(title: "结束方式", value: project.endMode.map(endModeLabel) ?? "尚未结束")
                ProjectStatusCard(title: "成果", value: artifactLabel(project.artifactStatus))
            }
        }
    }

    private func routeSection(_ project: EvolutionProject) -> some View {
        ProjectSection(title: "路线", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
            if project.routes.isEmpty {
                ProjectEmptyMessage(text: "还没有路线记录。")
            } else {
                ForEach(project.routes.sorted(by: routeOrdering)) { route in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(route.name).font(.headline)
                            Text(routeStatusLabel(route.status))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(routeStatusColor(route.status).opacity(0.12), in: Capsule())
                            Spacer()
                            if route.reviewState == .confirmed {
                                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                            }
                        }
                        Text(route.summary).textSelection(.enabled)
                        if !route.repoPaths.isEmpty {
                            Text("仓库：\(route.repoPaths.sorted().joined(separator: " · "))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Text(routePeriod(route))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .projectCard()
                }
            }
        }
    }

    private var nodeSection: some View {
        ProjectSection(title: "关键演化节点", systemImage: "point.3.connected.trianglepath.dotted") {
            if nodes.isEmpty {
                ProjectEmptyMessage(text: "还没有关键节点；普通聊天不会堆到这里。")
            } else {
                ForEach(nodes) { node in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(node.title).font(.headline)
                            Text(nodeKindLabel(node.kind))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.purple.opacity(0.12), in: Capsule())
                            Spacer()
                            if node.reviewState == .candidate {
                                Button("确认节点") { confirmNode(node.id) }
                            } else {
                                Label("已确认", systemImage: "lock.fill")
                                    .font(.caption)
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
                        LabeledContent("发生", value: EvolutionUIDate.timestamp(node.happenedAt))
                        LabeledContent("形成者", value: nodeOriginLabel(node.origin))
                        if !node.reason.isEmpty {
                            LabeledContent("原因", value: node.reason)
                        }
                        let happenedDay = EvolutionUIDate.dayKey(node.happenedAt)
                        let recognizedDay = EvolutionUIDate.dayKey(node.recognizedAt)
                        if happenedDay != recognizedDay {
                            Text("后来于 \(recognizedDay) 认识")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.purple)
                        }
                        nodeSourceButtons(node)
                        if !node.evidenceIds.isEmpty {
                            DisclosureGroup("证据 \(node.evidenceIds.count) 项") {
                                ForEach(node.evidenceIds.sorted(), id: \.self) { evidenceId in
                                    Text(evidenceId)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .projectCard()
                }
            }
        }
    }

    private var contributionSection: some View {
        ProjectSection(title: "每日贡献", systemImage: "calendar.badge.clock") {
            if contributions.isEmpty {
                ProjectEmptyMessage(text: "还没有项目日切片。")
            } else {
                ForEach(contributions, id: \.slice.id) { contribution in
                    let slice = contribution.slice
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(slice.date).font(.headline)
                            Text(slice.reviewState == .confirmed ? "已确认" : "候选")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                composerContext = UserAnnotationComposerContext(
                                    target: AnnotationTarget(kind: .projectDaySlice, targetId: slice.id),
                                    targetSummary: "\(slice.date) · \(slice.purpose)",
                                    entryLabel: "补充这个切片"
                                )
                            } label: {
                                Label("补充切片", systemImage: "square.and.pencil")
                            }
                        }
                        LabeledContent("目的", value: slice.purpose)
                        LabeledContent("进展", value: slice.progress)
                        if !slice.actions.isEmpty {
                            Text("动作：\(slice.actions.joined(separator: "；"))")
                                .textSelection(.enabled)
                        }
                        if !slice.decisions.isEmpty {
                            ProjectRecordBlock(title: "决策") {
                                ForEach(slice.decisions.sorted(by: { ($0.title, $0.id) < ($1.title, $1.id) })) { decision in
                                    Text("• \(decision.decision)（\(decision.reason)）")
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        if !slice.learnings.isEmpty {
                            ProjectRecordBlock(title: "错误 / 方法") {
                                ForEach(slice.learnings.sorted(by: { ($0.kind.rawValue, $0.id) < ($1.kind.rawValue, $1.id) })) { learning in
                                    Text("• \(learning.observation) → \(learning.lesson)")
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        if !slice.values.isEmpty {
                            ProjectRecordBlock(title: "价值") {
                                ForEach(slice.values.sorted(by: { ($0.kind.rawValue, $0.title, $0.id) < ($1.kind.rawValue, $1.title, $1.id) })) { value in
                                    Text("• \(value.title)：\(value.detail)")
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        contributionSources(day: contribution.day, slice: slice)
                    }
                    .projectCard()
                }
            }
        }
    }

    private var userContentSection: some View {
        ProjectSection(title: "项目相关用户内容", systemImage: "person.text.rectangle") {
            if projectAnnotations.isEmpty {
                ProjectEmptyMessage(text: "还没有项目相关的补充、纠正或后来认识。")
            } else {
                ForEach(projectAnnotations) { annotation in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(annotationKindLabelForProject(annotation.kind))
                                .font(.caption.weight(.bold))
                            Spacer()
                            Text(EvolutionUIDate.timestamp(annotation.recognizedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(annotation.body).textSelection(.enabled)
                        Text("关联：\(annotation.target.kind.rawValue) / \(annotation.target.targetId)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if let happenedAt = annotation.happenedAt {
                            Text("实际发生：\(EvolutionUIDate.timestamp(happenedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .projectCard()
                }
            }
        }
    }

    @ViewBuilder
    private func nodeSourceButtons(_ node: EvolutionNode) -> some View {
        let sources = node.sourceSliceIds.compactMap(sourceSlice)
        if !sources.isEmpty {
            ProjectRecordBlock(title: "来源") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sources, id: \.slice.id) { source in
                        sourceControl(day: source.day, slice: source.slice)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contributionSources(day: WorkEvolutionDayRecord, slice: ProjectDaySlice) -> some View {
        let sources = slice.sourceSliceIds.compactMap { id in day.sourceSlices.first { $0.id == id } }
        if !sources.isEmpty {
            ProjectRecordBlock(title: "来源") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sources) { source in
                        sourceControl(day: day, slice: source)
                    }
                }
            }
        }
    }

    private func sourceControl(day: WorkEvolutionDayRecord, slice: DailySessionSlice) -> some View {
        HStack(spacing: 2) {
            Button {
                openSource(day: day, slice: slice)
            } label: {
                Label(sessionTitle(slice.sessionId), systemImage: "text.bubble")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)

            Button {
                composerContext = UserAnnotationComposerContext(
                    target: AnnotationTarget(kind: .sourceSession, targetId: slice.sessionId),
                    targetSummary: "来源：\(sessionTitle(slice.sessionId))",
                    entryLabel: "补充这个来源"
                )
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("补充这个来源")
        }
    }

    private func sourceSlice(id: String) -> (day: WorkEvolutionDayRecord, slice: DailySessionSlice)? {
        for day in store.snapshot.days {
            if let slice = day.sourceSlices.first(where: { $0.id == id }) {
                return (day, slice)
            }
        }
        return nil
    }

    private func sessionTitle(_ id: String) -> String {
        store.snapshot.sourceSessions.first { $0.id == id }?.title ?? id
    }

    private func openSource(day: WorkEvolutionDayRecord, slice: DailySessionSlice) {
        if let date = EvolutionUIDate.date(from: day.date) {
            store.selectedDay = date
        }
        store.selectedSourceSessionId = slice.sessionId
    }

    private func confirmProject(_ id: String) {
        do {
            try store.confirmProject(id)
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

    private func routeOrdering(_ lhs: ProjectRoute, _ rhs: ProjectRoute) -> Bool {
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
        return lhs.id < rhs.id
    }

    private func routePeriod(_ route: ProjectRoute) -> String {
        let start = EvolutionUIDate.dayKey(route.startedAt)
        return route.endedAt.map { "\(start) → \(EvolutionUIDate.dayKey($0))" } ?? "\(start) → 至今"
    }
}

private struct ProjectSection<Content: View>: View {
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

private struct ProjectStatusCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .projectCard()
    }
}

private struct ProjectRecordBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            content
        }
    }
}

private struct ProjectEmptyMessage: View {
    let text: String
    var body: some View { Text(text).foregroundStyle(.secondary).padding(.vertical, 4) }
}

private extension View {
    func projectCard() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12)))
    }
}

private func progressLabel(_ status: ProjectProgressStatus) -> String {
    switch status {
    case .exploring: return "探索中"
    case .active: return "推进中"
    case .paused: return "暂停"
    case .ended: return "已结束"
    }
}

private func endModeLabel(_ mode: ProjectEndMode) -> String {
    switch mode {
    case .completed: return "完成"
    case .abandoned: return "放弃"
    case .replaced: return "被替代"
    }
}

private func artifactLabel(_ status: ArtifactStatus) -> String {
    switch status {
    case .notFormed: return "未形成"
    case .pendingValidation: return "待验证"
    case .verifiedUsable: return "已验证可用"
    case .inUse: return "使用中"
    case .stopped: return "已停用"
    }
}

private func routeStatusLabel(_ status: ProjectRouteStatus) -> String {
    switch status {
    case .active: return "进行中"
    case .paused: return "暂停"
    case .stopped: return "停止"
    case .replaced: return "被替代"
    }
}

private func routeStatusColor(_ status: ProjectRouteStatus) -> Color {
    switch status {
    case .active: return .green
    case .paused: return .orange
    case .stopped, .replaced: return .secondary
    }
}

private func nodeKindLabel(_ kind: EvolutionNodeKind) -> String {
    switch kind {
    case .purpose: return "目的"
    case .decision: return "决策"
    case .pivot: return "转向"
    case .failedRoute: return "走不通"
    case .outcome: return "结果"
    case .statusChange: return "状态变化"
    case .reflection: return "后来认识"
    }
}

private func nodeOriginLabel(_ origin: EvolutionNodeOrigin) -> String {
    switch origin {
    case .user: return "用户提出"
    case .assistant: return "AI 提出"
    case .joint: return "共同形成"
    }
}

private func annotationKindLabelForProject(_ kind: AnnotationKind) -> String {
    switch kind {
    case .supplement: return "补充"
    case .correction: return "纠正"
    case .reflection: return "后来认识"
    }
}
