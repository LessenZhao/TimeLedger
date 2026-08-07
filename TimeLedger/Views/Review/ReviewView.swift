import Charts
import SwiftData
import SwiftUI

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeEntry.startAt) private var refreshEntries: [TimeEntry]
    @Query(sort: \Project.updatedAt) private var refreshProjects: [Project]

    @State private var period: ReviewPeriod = .day
    @State private var anchorDate = Date()
    @State private var expandedProjectId: UUID?
    @State private var selectedBucketStart: Date?
    @State private var longTermProjectId: UUID?
    @State private var longTermGranularity: ReviewLongTermGranularity = .month
    @State private var evidenceProjectFilter: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                periodPicker
                periodNavigation
                Divider()

                if let summary {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if summary.pendingCount > 0 {
                                pendingBanner(summary)
                            }
                            observationsSection(summary)
                            projectTrendsSection(summary)
                            if period == .day {
                                evidenceSection(summary)
                            }
                        }
                        .padding(16)
                    }
                    .accessibilityIdentifier("review.scroll")
                } else {
                    ContentUnavailableView(
                        "复盘暂不可用",
                        systemImage: "exclamationmark.triangle",
                        description: Text("无法读取本地复盘数据。")
                    )
                }
            }
            .navigationTitle("复盘")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: longTermSheetItem) { item in
                longTermSheet(projectId: item.id)
            }
            .onChange(of: period) {
                selectedBucketStart = nil
                evidenceProjectFilter = nil
                syncExpandedProject()
            }
            .onChange(of: anchorDate) {
                selectedBucketStart = nil
                evidenceProjectFilter = nil
                syncExpandedProject()
            }
            .onAppear {
                syncExpandedProject()
            }
        }
    }

    private var summary: ReviewSummary? {
        _ = refreshEntries.count
        _ = refreshProjects.count
        return try? ReviewSummaryService(modelContext: modelContext).summary(
            period: period,
            anchorDate: anchorDate
        )
    }

    private var longTermSheetItem: Binding<IdentifiedUUID?> {
        Binding(
            get: { longTermProjectId.map(IdentifiedUUID.init) },
            set: { longTermProjectId = $0?.id }
        )
    }

    private var periodPicker: some View {
        Picker("复盘周期", selection: $period) {
            ForEach(ReviewPeriod.allCases) { value in
                Text(value.title)
                    .tag(value)
                    .accessibilityIdentifier("review.period.\(value.rawValue)")
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityIdentifier("review.period.picker")
    }

    private var periodNavigation: some View {
        HStack(spacing: 12) {
            Button {
                anchorDate = period.offset(anchorDate, by: -1, calendar: .current)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("上一周期")
            .accessibilityIdentifier("review.previous")

            VStack(spacing: 2) {
                Text(periodRangeTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("review.period.context")
                Text(period.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("review.active.period")
            }
            .frame(maxWidth: .infinity)

            Button {
                anchorDate = period.offset(anchorDate, by: 1, calendar: .current)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("下一周期")
            .accessibilityIdentifier("review.next")

            Button("当前") {
                anchorDate = Date()
            }
            .font(.caption.weight(.semibold))
            .accessibilityLabel("回到当前周期")
            .accessibilityIdentifier("review.current")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func pendingBanner(_ summary: ReviewSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("有 \(summary.pendingCount) 条记录待确认")
                    .font(.subheadline.weight(.semibold))
                Text("待确认记录已计入趋势（浅色），精确值单独标明。待确认时长 \(DurationFormatter.compact(summary.pendingDuration))。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("review.pending.banner")
    }

    private func observationsSection(_ summary: ReviewSummary) -> some View {
        ReviewCard(title: "值得注意") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(summary.observations.enumerated()), id: \.element.id) { index, observation in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(observation.title)
                            .font(.subheadline.weight(.semibold))
                        Text(observation.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("review.observation.\(index)")

                    if index < summary.observations.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .accessibilityIdentifier("review.observations")
    }

    private func projectTrendsSection(_ summary: ReviewSummary) -> some View {
        ReviewCard(title: "项目趋势") {
            if summary.projectTrends.isEmpty {
                Text("本期暂无记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(summary.projectTrends.enumerated()), id: \.element.id) { index, project in
                        projectCard(project, rank: index + 1, summary: summary)
                    }
                }
            }
        }
        .accessibilityIdentifier("review.projects")
    }

    private func projectCard(
        _ project: ReviewProjectTrend,
        rank: Int,
        summary: ReviewSummary
    ) -> some View {
        let isExpanded = expandedProjectId == project.projectId
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedProjectId = nil
                        selectedBucketStart = nil
                    } else {
                        expandedProjectId = project.projectId
                        selectedBucketStart = preferredBucketStart(in: project.buckets)
                        evidenceProjectFilter = project.projectId
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 18)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(rank). \(project.displayName)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Text(DurationFormatter.compact(project.totalDuration))
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                        Text(projectMetaText(project))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(rank). \(project.displayName)，\(DurationFormatter.compact(project.totalDuration))，\(projectMetaText(project))")
            .accessibilityIdentifier("review.project.header.\(project.projectId.uuidString)")

            if isExpanded {
                let selectedBucket = resolvedSelectedBucket(for: project)
                projectChart(project)
                bucketSelector(project, selected: selectedBucket?.start)
                selectedBucketDetail(selectedBucket)
                HStack(spacing: 12) {
                    if period == .week || period == .month {
                        Button("查看当天") {
                            if let start = selectedBucket?.start {
                                drillDown(to: start)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .disabled(selectedBucket == nil)
                        .accessibilityIdentifier("review.project.drill.day")
                    }
                    if period == .year {
                        Button("查看该月") {
                            if let start = selectedBucket?.start {
                                drillDown(to: start)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .disabled(selectedBucket == nil)
                        .accessibilityIdentifier("review.project.drill.month")
                    }
                    Spacer()
                    Button("长期趋势") {
                        longTermGranularity = .month
                        longTermProjectId = project.projectId
                    }
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("review.project.longterm.\(project.projectId.uuidString)")
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemBackground))
        )
        .accessibilityIdentifier("review.project.\(project.projectId.uuidString)")
    }

    private func projectChart(_ project: ReviewProjectTrend) -> some View {
        Chart {
            ForEach(project.buckets) { bucket in
                BarMark(
                    x: .value("时间", bucket.start, unit: chartUnit),
                    y: .value("小时", bucket.confirmedDuration / 3_600)
                )
                .foregroundStyle(by: .value("类型", "已确认"))

                BarMark(
                    x: .value("时间", bucket.start, unit: chartUnit),
                    y: .value("小时", bucket.draftDuration / 3_600)
                )
                .foregroundStyle(by: .value("类型", "待确认"))
            }
        }
        .chartForegroundStyleScale([
            "已确认": Color.accentColor,
            "待确认": Color.accentColor.opacity(0.35)
        ])
        .chartLegend(position: .top, alignment: .leading)
        .chartYScale(domain: chartMaximum(project.buckets))
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 180)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    HStack(spacing: 0) {
                        ForEach(Array(project.buckets.enumerated()), id: \.element.id) { index, bucket in
                            Button {
                                selectedBucketStart = bucket.start
                                if period == .day {
                                    evidenceProjectFilter = project.projectId
                                }
                            } label: {
                                Color.clear
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("选择\(bucketLabel(bucket.start))")
                            .accessibilityValue(bucketAccessibilityValue(bucket))
                            .accessibilityIdentifier(
                                "review.project.chart.bucket.\(project.projectId.uuidString).\(index)"
                            )
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .accessibilityLabel("\(project.displayName) 时间趋势")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.project.chart.\(project.projectId.uuidString)")
    }

    private func bucketSelector(_ project: ReviewProjectTrend, selected: Date?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(project.buckets.enumerated()), id: \.element.id) { index, bucket in
                    let isSelected = selected == bucket.start
                    Button {
                        selectedBucketStart = bucket.start
                        if period == .day {
                            evidenceProjectFilter = project.projectId
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text(shortBucketLabel(bucket.start))
                                .font(.caption2.weight(.semibold))
                            Text(bucket.totalDuration > 0
                                 ? DurationFormatter.compact(bucket.totalDuration)
                                 : "—")
                                .font(.system(size: 9))
                                .foregroundStyle(bucket.totalDuration > 0 ? Color.primary : Color.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(bucketLabel(bucket.start))
                    .accessibilityValue(bucketAccessibilityValue(bucket))
                    .accessibilityIdentifier(
                        "review.project.bucket.\(project.projectId.uuidString).\(index)"
                    )
                }
            }
        }
        .accessibilityIdentifier("review.project.buckets.\(project.projectId.uuidString)")
    }

    private func selectedBucketDetail(_ bucket: ReviewTimeBucket?) -> some View {
        Group {
            if let bucket {
                VStack(alignment: .leading, spacing: 4) {
                    Text("已选时段")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("review.project.selected")
                    Text(bucketLabel(bucket.start))
                        .font(.caption.weight(.semibold))
                    Text(bucketDetailText(bucket))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemBackground))
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("review.project.selected.detail")
            } else {
                Text("点击柱子查看精确时长与次数")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("review.project.selected.empty")
            }
        }
    }

    private func resolvedSelectedBucket(for project: ReviewProjectTrend) -> ReviewTimeBucket? {
        if let start = selectedBucketStart,
           let bucket = project.buckets.first(where: { $0.start == start })
        {
            return bucket
        }
        return preferredBucket(in: project.buckets)
    }

    private func preferredBucket(in buckets: [ReviewTimeBucket]) -> ReviewTimeBucket? {
        buckets.last(where: { $0.totalDuration > 0 }) ?? buckets.last ?? buckets.first
    }

    private func evidenceSection(_ summary: ReviewSummary) -> some View {
        let entries: [ReviewEvidenceEntry] = {
            if let filter = evidenceProjectFilter {
                return summary.evidenceEntries.filter { $0.projectId == filter }
            }
            if let expanded = expandedProjectId {
                return summary.evidenceEntries.filter { $0.projectId == expanded }
            }
            return summary.evidenceEntries
        }()

        return ReviewCard(title: "证据明细") {
            if entries.isEmpty {
                Text("本日暂无记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.projectName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            Spacer()
                            Text(DurationFormatter.compact(entry.confirmedDurationInPeriod))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                        HStack {
                            Text(evidenceTimeText(entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.status == .confirmed ? "已确认" : "待确认")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(entry.status == .confirmed ? Color.accentColor : Color.orange)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("review.evidence.\(entry.id.uuidString)")
                }
            }
        }
        .accessibilityIdentifier("review.evidence")
    }

    @ViewBuilder
    private func longTermSheet(projectId: UUID) -> some View {
        let detail = try? ReviewSummaryService(modelContext: modelContext).longTermDetail(
            projectId: projectId,
            granularity: longTermGranularity
        )
        NavigationStack {
            Group {
                if let detail {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("粒度", selection: $longTermGranularity) {
                                ForEach(ReviewLongTermGranularity.allCases) { value in
                                    Text(value.title).tag(value)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("review.longterm.granularity")

                            longTermStats(detail)
                            longTermChart(detail)
                            rhythmMatrixView(detail)
                        }
                        .padding(16)
                    }
                } else {
                    ContentUnavailableView("暂无长期数据", systemImage: "chart.line.uptrend.xyaxis")
                }
            }
            .navigationTitle(detail?.displayName ?? "长期趋势")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { longTermProjectId = nil }
                        .accessibilityIdentifier("review.longterm.close")
                }
            }
        }
        .accessibilityIdentifier("review.longterm.sheet")
    }

    private func longTermStats(_ detail: ReviewProjectLongTerm) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            statRow("累计时长", DurationFormatter.compact(detail.cumulativeDuration))
            statRow("活跃天数", "\(detail.activeDays) 天")
            statRow("单次时长中位数", DurationFormatter.compact(detail.medianSessionDuration))
            statRow("最长连续记录", "\(detail.longestConsecutiveDays) 天")
            statRow(
                "首条记录",
                detail.firstEntryAt.formatted(.dateTime.year().month().day().hour().minute())
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityIdentifier("review.longterm.stats")
    }

    private func longTermChart(_ detail: ReviewProjectLongTerm) -> some View {
        let unit: Calendar.Component = switch detail.granularity {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("长期趋势")
                .font(.headline)
            Chart {
                ForEach(detail.buckets) { bucket in
                    BarMark(
                        x: .value("时间", bucket.start, unit: unit),
                        y: .value("已确认", bucket.confirmedDuration / 3_600)
                    )
                    .foregroundStyle(Color.accentColor)
                    BarMark(
                        x: .value("时间", bucket.start, unit: unit),
                        y: .value("待确认", bucket.draftDuration / 3_600)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.35))
                }
            }
            .frame(height: 200)
            .accessibilityIdentifier("review.longterm.chart")
        }
    }

    private func rhythmMatrixView(_ detail: ReviewProjectLongTerm) -> some View {
        let symbols = weekdaySymbols()
        let blocks = ["00-06", "06-12", "12-18", "18-24"]
        let maxValue = max(detail.rhythmMatrix.flatMap { $0 }.max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 8) {
            Text("节律矩阵")
                .font(.headline)
            HStack(spacing: 4) {
                Text("")
                    .frame(width: 28)
                ForEach(blocks, id: \.self) { block in
                    Text(block)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<7, id: \.self) { weekday in
                HStack(spacing: 4) {
                    Text(symbols[weekday])
                        .font(.caption2)
                        .frame(width: 28, alignment: .leading)
                    ForEach(0..<4, id: \.self) { block in
                        let value = detail.rhythmMatrix[weekday][block]
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(0.12 + 0.88 * value / maxValue))
                            .frame(height: 22)
                            .overlay {
                                if value > 0 {
                                    Text(shortHours(value))
                                        .font(.system(size: 8))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .accessibilityLabel("\(symbols[weekday]) \(blocks[block]) \(DurationFormatter.compact(value))")
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityIdentifier("review.longterm.rhythm")
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func projectMetaText(_ project: ReviewProjectTrend) -> String {
        var parts = ["\(project.entryCount) 次"]
        parts.append("确认 \(DurationFormatter.compact(project.confirmedDuration))")
        if project.draftCount > 0 {
            parts.append("待确认 \(project.draftCount) 条 · \(DurationFormatter.compact(project.draftDuration))")
        } else {
            parts.append("待确认 0")
        }
        return parts.joined(separator: " · ")
    }

    private func bucketDetailText(_ bucket: ReviewTimeBucket) -> String {
        "确认 \(DurationFormatter.compact(bucket.confirmedDuration)) · 待确认 \(DurationFormatter.compact(bucket.draftDuration)) · 合计 \(DurationFormatter.compact(bucket.totalDuration)) · \(bucket.entryCount) 次"
    }

    private func bucketAccessibilityValue(_ bucket: ReviewTimeBucket) -> String {
        bucketDetailText(bucket)
    }

    private var periodRangeTitle: String {
        guard let summary else { return "—" }
        let start = summary.range.lowerBound
        let end = summary.range.upperBound.addingTimeInterval(-0.001)
        switch period {
        case .day:
            return start.formatted(.dateTime.year().month().day())
        case .week:
            return "\(start.formatted(.dateTime.month().day())) – \(end.formatted(.dateTime.month().day()))"
        case .month:
            return start.formatted(.dateTime.year().month(.wide))
        case .year:
            return start.formatted(.dateTime.year())
        }
    }

    private var chartUnit: Calendar.Component {
        switch period {
        case .day: .hour
        case .week, .month: .day
        case .year: .month
        }
    }

    private func chartMaximum(_ buckets: [ReviewTimeBucket]) -> ClosedRange<Double> {
        let maximum = buckets.map(\.totalDuration).max() ?? 0
        return 0...max(maximum / 3_600 * 1.15, 1)
    }

    private func bucketLabel(_ date: Date) -> String {
        switch period {
        case .day:
            return date.formatted(.dateTime.hour().minute())
        case .week, .month:
            return date.formatted(.dateTime.year().month().day())
        case .year:
            return date.formatted(.dateTime.year().month(.wide))
        }
    }

    private func shortBucketLabel(_ date: Date) -> String {
        switch period {
        case .day:
            return date.formatted(.dateTime.hour())
        case .week:
            return date.formatted(.dateTime.weekday(.narrow))
        case .month:
            return date.formatted(.dateTime.day())
        case .year:
            return date.formatted(.dateTime.month(.narrow))
        }
    }

    private func evidenceTimeText(_ entry: ReviewEvidenceEntry) -> String {
        "\(entry.startAt.formatted(.dateTime.month().day().hour().minute())) – \(entry.endAt.formatted(.dateTime.month().day().hour().minute()))"
    }

    private func weekdaySymbols() -> [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private func shortHours(_ value: TimeInterval) -> String {
        let hours = value / 3_600
        if hours < 1 {
            return "\(max(1, Int((value / 60).rounded())))m"
        }
        return String(format: "%.1fh", hours)
    }

    private func syncExpandedProject() {
        guard let summary else {
            expandedProjectId = nil
            return
        }
        if let expandedProjectId,
           let project = summary.projectTrends.first(where: { $0.projectId == expandedProjectId })
        {
            if selectedBucketStart == nil {
                selectedBucketStart = preferredBucketStart(in: project.buckets)
            }
            return
        }
        expandedProjectId = summary.projectTrends.first?.projectId
        evidenceProjectFilter = expandedProjectId
        if let first = summary.projectTrends.first {
            selectedBucketStart = preferredBucketStart(in: first.buckets)
        } else {
            selectedBucketStart = nil
        }
    }

    private func preferredBucketStart(in buckets: [ReviewTimeBucket]) -> Date? {
        preferredBucket(in: buckets)?.start
    }

    private func drillDown(to date: Date) {
        switch period {
        case .week, .month:
            anchorDate = date
            period = .day
        case .year:
            anchorDate = date
            period = .month
        case .day:
            break
        }
        selectedBucketStart = nil
    }
}

private struct IdentifiedUUID: Identifiable {
    let id: UUID
}

private struct ReviewCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    ReviewView()
        .modelContainer(previewModelContainer)
}
