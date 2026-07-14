import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var store: HubStore
    @State private var selectedEventId: String?
    @State private var selectedEntryId: String?

    var body: some View {
        HSplitView {
            List(selection: $selectedEventId) {
                if !store.suggestedLinksForDay.isEmpty {
                    Section("建议关联（\(store.suggestedLinksForDay.count)）") {
                        ForEach(store.suggestedLinksForDay) { link in
                            if let event = store.event(id: link.contextEventId) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(event.title).font(.subheadline.weight(.semibold))
                                        Text("置信度 \(String(format: "%.2f", link.confidence)) · \(link.method.rawValue)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("确认") { store.confirmSuggested(link) }
                                    Button("拒绝") {
                                        store.rejectLink(timeEntryId: link.timeEntryId, contextEventId: link.contextEventId)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("待确认上下文（\(store.inboxEvents.count)）") {
                    if store.inboxEvents.isEmpty {
                        Text("收件箱为空。导入 ContextEvent JSON，或当天事件已全部关联。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.inboxEvents) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(event.source.rawValue)
                                        .font(.caption2.weight(.bold))
                                    Text(event.title)
                                        .font(.subheadline.weight(.semibold))
                                }
                                Text("\(timeString(event.startedAt)) · \(event.summary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                if let raw = event.rawReference {
                                    Text(raw)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .textSelection(.enabled)
                                }
                            }
                            .tag(event.id)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .frame(minWidth: 320)

            VStack(alignment: .leading, spacing: 12) {
                Text("手动关联到时间记录")
                    .font(.headline)
                if let eventId = selectedEventId, let event = store.event(id: eventId) {
                    Text("选中：\(event.title)")
                        .font(.subheadline)
                    if let raw = event.rawReference {
                        Text("原始引用：\(raw)")
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    Picker("时间记录", selection: $selectedEntryId) {
                        Text("选择…").tag(String?.none)
                        ForEach(store.entriesForSelectedDay) { entry in
                            Text("\(timeString(entry.startAt)) \(entry.projectNameSnapshot)")
                                .tag(Optional(entry.id))
                        }
                    }
                    HStack {
                        Button("确认关联") {
                            guard let entryId = selectedEntryId else { return }
                            do {
                                try store.manuallyLink(timeEntryId: entryId, contextEventId: eventId)
                                selectedEventId = nil
                                selectedEntryId = nil
                            } catch {
                                store.lastMessage = error.localizedDescription
                            }
                        }
                        .disabled(selectedEntryId == nil)
                        Button("拒绝") {
                            store.rejectLink(
                                timeEntryId: selectedEntryId ?? "",
                                contextEventId: eventId
                            )
                            selectedEventId = nil
                        }
                        .disabled(selectedEventId == nil)
                    }
                    Spacer()
                } else {
                    Text("从左侧选择一条上下文")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding()
            .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
