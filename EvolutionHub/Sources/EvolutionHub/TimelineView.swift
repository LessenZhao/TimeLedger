import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: HubStore

    var body: some View {
        List {
            Section("时间记录（\(store.entriesForSelectedDay.count)）") {
                if store.entriesForSelectedDay.isEmpty {
                    Text("暂无当天时间记录。请导入 TimeLedger JSON。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.entriesForSelectedDay) { entry in
                        EntryRow(entry: entry)
                    }
                }
            }
            Section("思考卡片（\(store.thoughtsForSelectedDay.count)）") {
                if store.thoughtsForSelectedDay.isEmpty {
                    Text("暂无当天思考")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.thoughtsForSelectedDay) { thought in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(timeString(thought.capturedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(thought.body)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct EntryRow: View {
    @EnvironmentObject private var store: HubStore
    let entry: ImportedTimeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.projectNameSnapshot)
                    .font(.headline)
                Text(entry.status)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(entry.status == "confirmed" ? Color.primary.opacity(0.12) : Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
                Text("\(timeString(entry.startAt))–\(timeString(entry.endAt))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            let links = store.confirmedLinks(for: entry.id)
            if links.isEmpty {
                Text("无已确认上下文")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(links) { link in
                    if let event = store.event(id: link.contextEventId) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(event.source.rawValue.uppercased())
                                    .font(.caption2.weight(.semibold))
                                Text(event.title)
                                    .font(.caption)
                            }
                            if let raw = event.rawReference, !raw.isEmpty {
                                Text("来源：\(raw)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            if !event.summary.isEmpty {
                                Text(event.summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
