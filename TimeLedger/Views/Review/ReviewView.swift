import Charts
import SwiftData
import SwiftUI

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeEntry.startAt) private var refreshEntries: [TimeEntry]
    @Query(sort: \ActionCompletion.dayStart) private var refreshCompletions: [ActionCompletion]
    @Query(sort: \Project.updatedAt) private var refreshProjects: [Project]

    @State private var period: ReviewPeriod = .day
    @State private var anchorDate = Date()
    @State private var selectedActionId: UUID?
    @State private var expandedActionIds: Set<UUID> = []
    @State private var showFullProjectRanking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                periodPicker
                periodNavigation
                Divider()

                if let summary {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            overviewSection(summary)
                            actionFootprintSection(summary)
                            timeTrendSection(summary)
                            projectStructureSection(summary)
                            evidenceSection(summary)
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
        }
        .onChange(of: period) {
            selectedActionId = nil
        }
    }

    private var summary: ReviewSummary? {
        _ = refreshEntries.count
        _ = refreshCompletions.count
        _ = refreshProjects.count
        return try? ReviewSummaryService(modelContext: modelContext).summary(
            period: period,
            anchorDate: anchorDate
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

    private func overviewSection(_ summary: ReviewSummary) -> some View {
        ReviewCard(title: "本期概览") {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("已确认总时长")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(DurationFormatter.compact(summary.confirmedDuration))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .accessibilityIdentifier("review.total.confirmed")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("较上一可比周期")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(comparisonText(summary.comparison))
                        .font(.headline)
                        .foregroundStyle(comparisonColor(summary.comparison.delta))
                        .accessibilityIdentifier("review.comparison")
                }
            }

            Divider()

            HStack {
                Label("待确认", systemImage: "clock.badge.questionmark")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(summary.pendingCount) 条 · \(DurationFormatter.compact(summary.pendingDuration))")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .accessibilityIdentifier("review.pending")
            }
        }
    }

    @ViewBuilder
    private func actionFootprintSection(_ summary: ReviewSummary) -> some View {
        ReviewCard(title: "事项足迹") {
            if summary.actionFootprints.isEmpty {
                emptyText("本期没有完成事项")
            } else {
                switch period {
                case .day:
                    dailyActions(summary.actionFootprints)
                case .week:
                    weeklyActionMatrix(summary)
                case .month:
                    monthlyActionCalendar(summary)
                case .year:
                    yearlyActionHeatmap(summary)
                }
            }
        }
    }

    private func dailyActions(_ actions: [ReviewActionFootprint]) -> some View {
        VStack(spacing: 0) {
            ForEach(actions) { action in
                actionSummaryHeader(action)
                Text("具体日期：\(action.completionDates.map(shortDate).joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }
        }
    }

    private func weeklyActionMatrix(_ summary: ReviewSummary) -> some View {
        let days = ReviewPeriod.week.bucketRanges(in: summary.range, calendar: .current)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Text("事项")
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(days, id: \.lowerBound) { day in
                    Text(day.lowerBound, format: .dateTime.weekday(.narrow))
                        .font(.caption2)
                        .frame(width: 22)
                }
            }
            ForEach(summary.actionFootprints) { action in
                Button {
                    toggleDates(action.id)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(action.displayTitle)
                                .font(.subheadline)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(days, id: \.lowerBound) { day in
                                footprintCell(
                                    completed: action.completionDates.contains(day.lowerBound),
                                    accessibilityText: "\(shortDate(day.lowerBound))\(action.completionDates.contains(day.lowerBound) ? "已完成" : "未完成")"
                                )
                            }
                        }
                        actionStats(action)
                        if expandedActionIds.contains(action.id) {
                            explicitDates(action)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.action.\(action.id.uuidString)")
            }
        }
    }

    private func monthlyActionCalendar(_ summary: ReviewSummary) -> some View {
        let selected = selectedActionId.flatMap { id in
            summary.actionFootprints.first { $0.id == id }
        } ?? summary.actionFootprints.first

        return VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(summary.actionFootprints) { action in
                        Button(action.displayTitle) {
                            selectedActionId = action.id
                        }
                        .buttonStyle(.bordered)
                        .tint(selected?.id == action.id ? .accentColor : .secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("review.action.select.\(action.id.uuidString)")
                    }
                }
            }

            if let selected {
                monthGrid(action: selected, range: summary.range)
                actionStats(selected)
                explicitDates(selected)
            }
        }
    }

    private func monthGrid(
        action: ReviewActionFootprint,
        range: Range<Date>
    ) -> some View {
        let days = ReviewPeriod.month.bucketRanges(in: range, calendar: .current)
        let weekday = Calendar.current.component(.weekday, from: range.lowerBound)
        let leading = (weekday - Calendar.current.firstWeekday + 7) % 7

        return VStack(spacing: 5) {
            HStack(spacing: 5) {
                ForEach(Calendar.current.veryShortWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7),
                spacing: 5
            ) {
                ForEach(0..<leading, id: \.self) { _ in
                    Color.clear.frame(height: 30)
                }
                ForEach(days, id: \.lowerBound) { day in
                    let completed = action.completionDates.contains(day.lowerBound)
                    Text(day.lowerBound, format: .dateTime.day())
                        .font(.caption.weight(completed ? .bold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(completed ? Color.accentColor : Color.secondary.opacity(0.12))
                        )
                        .foregroundStyle(completed ? Color.white : Color.primary)
                        .accessibilityLabel("\(shortDate(day.lowerBound))\(completed ? "已完成" : "未完成")")
                }
            }
        }
        .accessibilityIdentifier("review.action.month.grid")
    }

    private func yearlyActionHeatmap(_ summary: ReviewSummary) -> some View {
        let months = ReviewPeriod.year.bucketRanges(in: summary.range, calendar: .current)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 3) {
                Text("事项")
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(months, id: \.lowerBound) { month in
                    Text(month.lowerBound, format: .dateTime.month(.narrow))
                        .font(.system(size: 8))
                        .frame(width: 13)
                }
            }

            ForEach(summary.actionFootprints) { action in
                Button {
                    toggleDates(action.id)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 3) {
                            Text(action.displayTitle)
                                .font(.caption)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(months, id: \.lowerBound) { month in
                                let count = action.completionDates.count {
                                    month.contains($0)
                                }
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(heatColor(count: count))
                                    .frame(width: 13, height: 18)
                                    .accessibilityLabel(
                                        "\(month.lowerBound.formatted(.dateTime.month(.wide)))完成 \(count) 天"
                                    )
                            }
                        }
                        actionStats(action)
                        if expandedActionIds.contains(action.id) {
                            explicitDates(action)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.action.\(action.id.uuidString)")
            }
        }
    }

    private func timeTrendSection(_ summary: ReviewSummary) -> some View {
        ReviewCard(title: "时间趋势") {
            Chart(summary.timeBuckets) { bucket in
                BarMark(
                    x: .value("时间", bucket.start, unit: chartUnit),
                    y: .value("已确认小时", bucket.confirmedDuration / 3_600)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(3)
                .accessibilityLabel(bucketLabel(bucket.start))
                .accessibilityValue(DurationFormatter.compact(bucket.confirmedDuration))
            }
            .chartYScale(domain: chartMaximum(summary.timeBuckets))
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 190)
            .accessibilityLabel("已确认时间柱状图")
            .accessibilityHint(chartDrillHint)
            .accessibilityIdentifier("review.time.chart")
            .chartOverlay { proxy in
                if period != .day {
                    GeometryReader { geometry in
                        if let plotFrame = proxy.plotFrame {
                            let frame = geometry[plotFrame]
                            HStack(spacing: 0) {
                                ForEach(Array(summary.timeBuckets.enumerated()), id: \.element.id) { index, bucket in
                                    Button {
                                        drillDown(to: bucket.start)
                                    } label: {
                                        Color.clear
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel("打开\(bucketLabel(bucket.start))")
                                    .accessibilityValue(DurationFormatter.compact(bucket.confirmedDuration))
                                    .accessibilityIdentifier("review.time.bucket.\(index)")
                                }
                            }
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                        }
                    }
                }
            }

            if summary.timeBuckets.allSatisfy({ $0.confirmedDuration == 0 }) {
                emptyText("本期暂无已确认时间")
            } else {
                VStack(spacing: 5) {
                    ForEach(summary.timeBuckets.filter { $0.confirmedDuration > 0 }) { bucket in
                        HStack {
                            Text(bucketLabel(bucket.start))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(DurationFormatter.compact(bucket.confirmedDuration))
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func projectStructureSection(_ summary: ReviewSummary) -> some View {
        let topFive = Array(summary.projectRanking.prefix(5))
        let otherDuration = summary.projectRanking.dropFirst(5).reduce(0) {
            $0 + $1.confirmedDuration
        }
        let maximum = max(summary.projectRanking.first?.confirmedDuration ?? 0, 1)

        return ReviewCard(title: "项目结构") {
            if summary.projectRanking.isEmpty {
                emptyText("本期暂无已确认项目")
            } else {
                ForEach(topFive) { project in
                    projectBar(
                        name: project.displayName,
                        duration: project.confirmedDuration,
                        maximum: maximum
                    )
                }
                if otherDuration > 0 {
                    projectBar(name: "其他", duration: otherDuration, maximum: maximum)
                }

                DisclosureGroup("完整排名", isExpanded: $showFullProjectRanking) {
                    VStack(spacing: 6) {
                        ForEach(Array(summary.projectRanking.enumerated()), id: \.element.id) { index, project in
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(index + 1). \(project.displayName)")
                                    .lineLimit(2)
                                Spacer()
                                Text(DurationFormatter.compact(project.confirmedDuration))
                                    .monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("review.projects.full")
            }
        }
    }

    private func evidenceSection(_ summary: ReviewSummary) -> some View {
        ReviewCard(title: "证据明细") {
            if summary.evidenceEntries.isEmpty {
                emptyText("本期暂无已确认记录")
            } else {
                ForEach(summary.evidenceEntries) { entry in
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
                        Text(evidenceTimeText(entry))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("review.evidence.\(entry.id.uuidString)")
                }
            }
        }
    }

    private func actionSummaryHeader(_ action: ReviewActionFootprint) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(action.displayTitle)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Spacer()
            Text("\(action.completedDayCount) 天")
                .font(.caption.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("review.action.\(action.id.uuidString)")
    }

    private func actionStats(_ action: ReviewActionFootprint) -> some View {
        Text("完成 \(action.completedDayCount) 天 · 当前连续 \(action.currentStreak) 天 · 最长连续 \(action.longestStreak) 天")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func explicitDates(_ action: ReviewActionFootprint) -> some View {
        Text("具体日期：\(action.completionDates.map(shortDate).joined(separator: "、"))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("review.action.dates.\(action.id.uuidString)")
    }

    private func footprintCell(
        completed: Bool,
        accessibilityText: String
    ) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(completed ? Color.accentColor : Color.secondary.opacity(0.12))
            .frame(width: 22, height: 22)
            .overlay {
                if completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityLabel(accessibilityText)
    }

    private func projectBar(
        name: String,
        duration: TimeInterval,
        maximum: TimeInterval
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer()
                Text(DurationFormatter.compact(duration))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * duration / maximum)
                    }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func emptyText(_ value: String) -> some View {
        Text(value)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var chartDrillHint: String {
        switch period {
        case .week, .month: "点击柱子进入对应日"
        case .year: "点击柱子进入对应月"
        case .day: "按小时显示"
        }
    }

    private func chartMaximum(_ buckets: [ReviewTimeBucket]) -> ClosedRange<Double> {
        let maximum = buckets.map(\.confirmedDuration).max() ?? 0
        return 0...max(maximum / 3_600 * 1.15, 1)
    }

    private func bucketLabel(_ date: Date) -> String {
        switch period {
        case .day:
            return date.formatted(.dateTime.hour())
        case .week, .month:
            return date.formatted(.dateTime.month().day())
        case .year:
            return date.formatted(.dateTime.month(.wide))
        }
    }

    private func comparisonText(_ comparison: ReviewComparison) -> String {
        if comparison.currentDuration == 0 && comparison.previousDuration == 0 {
            return "持平 · 0分钟"
        }
        let prefix = comparison.delta > 0 ? "增加" : comparison.delta < 0 ? "减少" : "持平"
        let duration = DurationFormatter.compact(abs(comparison.delta))
        if let percentage = comparison.percentageChange {
            let percentageText = abs(percentage).formatted(
                .percent.precision(.fractionLength(0))
            )
            return "\(prefix) \(duration) · \(percentageText)"
        }
        return comparison.delta > 0 ? "\(prefix) \(duration) · 上期为 0" : "\(prefix) \(duration)"
    }

    private func comparisonColor(_ delta: TimeInterval) -> Color {
        if delta > 0 { return .blue }
        if delta < 0 { return .orange }
        return .secondary
    }

    private func heatColor(count: Int) -> Color {
        switch count {
        case 0: Color.secondary.opacity(0.12)
        case 1...2: Color.accentColor.opacity(0.35)
        case 3...7: Color.accentColor.opacity(0.65)
        default: Color.accentColor
        }
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day())
    }

    private func evidenceTimeText(_ entry: ReviewEvidenceEntry) -> String {
        "\(entry.startAt.formatted(.dateTime.month().day().hour().minute())) – \(entry.endAt.formatted(.dateTime.month().day().hour().minute()))"
    }

    private func toggleDates(_ actionId: UUID) {
        if expandedActionIds.contains(actionId) {
            expandedActionIds.remove(actionId)
        } else {
            expandedActionIds.insert(actionId)
        }
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
    }
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
