import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct DailyReviewHubView: View {
    @EnvironmentObject private var store: HubStore

    var body: some View {
        HSplitView {
            Form {
                Section("确定性摘要（无 AI）") {
                    LabeledContent("日期", value: store.dailyReviewDraft.date)
                    LabeledContent("时间记录", value: "\(store.entriesForSelectedDay.count) 条")
                    LabeledContent("思考卡片", value: "\(store.thoughtsForSelectedDay.count) 条")
                    LabeledContent("上下文事件", value: "\(store.eventsForSelectedDay.count) 条")
                    LabeledContent("已确认关联", value: "\(store.evidenceLinks.filter { $0.userState == .confirmed }.count) 条")
                    LabeledContent("建议关联", value: "\(store.suggestedLinksForDay.count) 条")
                    LabeledContent("收件箱", value: "\(store.inboxEvents.count) 条")
                    LabeledContent("Git 证据", value: "\(store.gitEvidence.count) 条")
                }
                Section("今日复盘（两分钟确认）") {
                    TextField("今日主要投入", text: $store.dailyReviewDraft.mainFocus, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("已验证产出", text: $store.dailyReviewDraft.verifiedOutputs, axis: .vertical)
                        .lineLimit(2...6)
                    TextField("重要讨论与决策 / 思考", text: $store.dailyReviewDraft.keyInsights, axis: .vertical)
                        .lineLimit(2...6)
                    TextField("一个主要偏差", text: $store.dailyReviewDraft.mainDeviation, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("一个明日调整", text: $store.dailyReviewDraft.nextAdjustment, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Button("重新生成确定性报告") {
                        let draft = DeterministicReviewBuilder.build(package: store.makeDailyPackage())
                        store.applyReviewDraft(draft)
                    }
                    Button("确认复盘") {
                        store.confirmReview()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(minWidth: 360)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("事实等级与证据")
                        .font(.headline)
                    if let draft = store.reviewDraft {
                        ForEach(draft.verifiedOutputs) { line in
                            factRow(line)
                        }
                        ForEach(draft.keyInsights) { line in
                            factRow(line)
                        }
                        Divider()
                        Text(draft.deterministicMarkdown)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("点击「重新生成确定性报告」或「同步今日上下文」")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 320)
        }
        .onAppear {
            store.refreshReviewDateKey()
        }
    }

    private func factRow(_ line: ReviewFactLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(line.level.rawValue)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Text(line.text)
                    .font(.caption)
            }
            if !line.evidenceIds.isEmpty {
                Text("证据: \(line.evidenceIds.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}
