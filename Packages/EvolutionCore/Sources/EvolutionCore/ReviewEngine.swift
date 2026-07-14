import Foundation

public enum FactLevel: String, Codable, Sendable, Hashable {
    case verified = "已验证"
    case inferred = "有证据推断"
    case selfReported = "用户自述"
    case insufficient = "信息不足"
}

public struct ReviewFactLine: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var level: FactLevel
    public var evidenceIds: [String]

    public init(id: String = UUID().uuidString, text: String, level: FactLevel, evidenceIds: [String] = []) {
        self.id = id
        self.text = text
        self.level = level
        self.evidenceIds = evidenceIds
    }
}

public struct ReviewDraft: Codable, Sendable, Hashable {
    public var date: String
    public var mainFocus: String
    public var verifiedOutputs: [ReviewFactLine]
    public var keyInsights: [ReviewFactLine]
    public var mainDeviation: String
    public var nextAdjustment: String
    public var evidenceIds: [String]
    public var deterministicMarkdown: String
    public var aiDraft: String?
    public var schemaVersion: Int

    public init(
        date: String,
        mainFocus: String = "",
        verifiedOutputs: [ReviewFactLine] = [],
        keyInsights: [ReviewFactLine] = [],
        mainDeviation: String = "",
        nextAdjustment: String = "",
        evidenceIds: [String] = [],
        deterministicMarkdown: String = "",
        aiDraft: String? = nil,
        schemaVersion: Int = EvolutionSchema.current
    ) {
        self.date = date
        self.mainFocus = mainFocus
        self.verifiedOutputs = verifiedOutputs
        self.keyInsights = keyInsights
        self.mainDeviation = mainDeviation
        self.nextAdjustment = nextAdjustment
        self.evidenceIds = evidenceIds
        self.deterministicMarkdown = deterministicMarkdown
        self.aiDraft = aiDraft
        self.schemaVersion = schemaVersion
    }
}

public struct DailyContextPackage: Sendable {
    public var dateKey: String
    public var entries: [TimelineEntryLike]
    public var thoughtBodies: [String]
    public var events: [ContextEvent]
    public var links: [EvidenceLink]
    public var gitEvidence: [GitEvidenceSummary]
    public var yesterdayAdjustment: String?

    public init(
        dateKey: String,
        entries: [TimelineEntryLike],
        thoughtBodies: [String],
        events: [ContextEvent],
        links: [EvidenceLink],
        gitEvidence: [GitEvidenceSummary] = [],
        yesterdayAdjustment: String? = nil
    ) {
        self.dateKey = dateKey
        self.entries = entries
        self.thoughtBodies = thoughtBodies
        self.events = events
        self.links = links
        self.gitEvidence = gitEvidence
        self.yesterdayAdjustment = yesterdayAdjustment
    }
}

public struct GitEvidenceSummary: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var repoPath: String
    public var commitHash: String
    public var commitMessage: String
    public var changedFiles: Int
    public var insertions: Int
    public var deletions: Int
    public var buildStatus: String?
    public var testStatus: String?
    public var capturedAt: Date

    public init(
        id: String = UUID().uuidString,
        repoPath: String,
        commitHash: String,
        commitMessage: String,
        changedFiles: Int = 0,
        insertions: Int = 0,
        deletions: Int = 0,
        buildStatus: String? = nil,
        testStatus: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.repoPath = repoPath
        self.commitHash = commitHash
        self.commitMessage = commitMessage
        self.changedFiles = changedFiles
        self.insertions = insertions
        self.deletions = deletions
        self.buildStatus = buildStatus
        self.testStatus = testStatus
        self.capturedAt = capturedAt
    }
}

public protocol ReviewProvider: Sendable {
    func createDraft(from package: DailyContextPackage) async throws -> ReviewDraft
}

/// Always available: no model required.
public struct DeterministicReviewProvider: ReviewProvider {
    public init() {}

    public func createDraft(from package: DailyContextPackage) async throws -> ReviewDraft {
        DeterministicReviewBuilder.build(package: package)
    }
}

public enum DeterministicReviewBuilder {
    public static func build(package: DailyContextPackage) -> ReviewDraft {
        var durationByProject: [String: TimeInterval] = [:]
        for entry in package.entries {
            durationByProject[entry.projectName, default: 0] += entry.endAt.timeIntervalSince(entry.startAt)
        }
        let sortedProjects = durationByProject.sorted { $0.value > $1.value }
        let mainFocus = sortedProjects.first.map { "\($0.key)（\(minutes($0.value)) 分钟）" } ?? "信息不足：无时间记录"

        let confirmedLinks = package.links.filter { $0.userState == .confirmed }
        let linkedEventIds = Set(confirmedLinks.map(\.contextEventId))
        let linkedEvents = package.events.filter { linkedEventIds.contains($0.id) }
        let unlinked = package.events.filter { !linkedEventIds.contains($0.id) }

        var outputs: [ReviewFactLine] = []
        for git in package.gitEvidence {
            outputs.append(ReviewFactLine(
                text: "Git \(git.commitHash.prefix(7)): \(git.commitMessage)",
                level: .verified,
                evidenceIds: [git.id]
            ))
        }
        for event in linkedEvents {
            outputs.append(ReviewFactLine(
                text: "[\(event.source.rawValue)] \(event.title)",
                level: .inferred,
                evidenceIds: [event.id]
            ))
        }
        if outputs.isEmpty {
            outputs.append(ReviewFactLine(text: "无已验证产出证据", level: .insufficient))
        }

        var insights: [ReviewFactLine] = package.thoughtBodies.prefix(5).map {
            ReviewFactLine(text: $0, level: .selfReported)
        }
        if insights.isEmpty {
            insights.append(ReviewFactLine(text: "无思考卡片", level: .insufficient))
        }

        let deviation: String = {
            if let y = package.yesterdayAdjustment, !y.isEmpty {
                let matched = package.entries.contains { $0.projectName.localizedCaseInsensitiveContains(y) || y.localizedCaseInsensitiveContains($0.projectName) }
                    || package.thoughtBodies.contains { $0.localizedCaseInsensitiveContains(y) }
                return matched
                    ? "昨日调整「\(y)」在今日记录中有相关痕迹（有证据推断）"
                    : "昨日调整「\(y)」在今日时间记录中未见明显对应（信息不足）"
            }
            if !unlinked.isEmpty {
                return "有 \(unlinked.count) 条上下文未关联时间线"
            }
            return "信息不足：无明确偏差信号"
        }()

        let md = buildMarkdown(
            date: package.dateKey,
            mainFocus: mainFocus,
            projects: sortedProjects,
            entries: package.entries.count,
            thoughts: package.thoughtBodies.count,
            events: package.events.count,
            linked: linkedEvents.count,
            unlinked: unlinked.count,
            sessions: linkedEvents.map { "- [\($0.source.rawValue)] \($0.title)" },
            thoughtsList: package.thoughtBodies,
            git: package.gitEvidence,
            unlinkedTitles: unlinked.map(\.title),
            deviation: deviation,
            yesterday: package.yesterdayAdjustment
        )

        return ReviewDraft(
            date: package.dateKey,
            mainFocus: mainFocus,
            verifiedOutputs: outputs,
            keyInsights: insights,
            mainDeviation: deviation,
            nextAdjustment: "",
            evidenceIds: linkedEvents.map(\.id) + package.gitEvidence.map(\.id),
            deterministicMarkdown: md
        )
    }

    private static func minutes(_ t: TimeInterval) -> Int {
        Int((t / 60).rounded())
    }

    private static func buildMarkdown(
        date: String,
        mainFocus: String,
        projects: [(key: String, value: TimeInterval)],
        entries: Int,
        thoughts: Int,
        events: Int,
        linked: Int,
        unlinked: Int,
        sessions: [String],
        thoughtsList: [String],
        git: [GitEvidenceSummary],
        unlinkedTitles: [String],
        deviation: String,
        yesterday: String?
    ) -> String {
        var lines: [String] = []
        lines.append("# 每日复盘 \(date)")
        lines.append("")
        lines.append("## 今日主要投入")
        lines.append(mainFocus)
        for p in projects {
            lines.append("- \(p.key): \(minutes(p.value)) 分钟")
        }
        lines.append("")
        lines.append("## 已验证产出")
        if git.isEmpty {
            lines.append("- （无 Git 证据）")
        } else {
            for g in git {
                lines.append("- [\(FactLevel.verified.rawValue)] \(g.commitHash.prefix(7)) \(g.commitMessage)")
            }
        }
        lines.append("")
        lines.append("## 重要讨论与决策")
        lines.append("- 关联会话 \(linked) / 总上下文 \(events)")
        lines.append(contentsOf: sessions.isEmpty ? ["- （无）"] : sessions)
        lines.append("")
        lines.append("## 值得保留的思考")
        if thoughtsList.isEmpty {
            lines.append("- （无）")
        } else {
            for t in thoughtsList {
                lines.append("- \(t)")
            }
        }
        lines.append("")
        lines.append("## 主要偏差")
        lines.append(deviation)
        if let yesterday, !yesterday.isEmpty {
            lines.append("- 昨日调整：\(yesterday)")
        }
        lines.append("")
        lines.append("## 数据缺口")
        lines.append("- 时间记录 \(entries) 条，思考 \(thoughts) 条")
        lines.append("- 未关联上下文 \(unlinked) 条")
        for title in unlinkedTitles.prefix(10) {
            lines.append("  - \(title)")
        }
        lines.append("")
        lines.append("## 明日唯一调整")
        lines.append("（待用户填写）")
        return lines.joined(separator: "\n")
    }
}
