import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct TodayMirrorPane: View {
    @EnvironmentObject private var mirror: MirrorSessionController
    @State private var tab = 0
    @State private var errorText: String?
    @State private var editing: MirrorTimeEntry?

    var body: some View {
        Group {
            if !mirror.canBookkeep {
                locked
            } else {
                VStack(spacing: 0) {
                    header
                    Picker("", selection: $tab) {
                        Text("项目").tag(0)
                        Text("草稿").tag(1)
                        Text("已确认").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    content
                }
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private var locked: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("今天 · 未连接")
                .font(.title2)
            Text("请先在「连接 iPhone」导入手机 SyncEnvelope，建立镜像后再记账。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            Text("今天")
                .font(.title2.weight(.semibold))
            Spacer()
            Text("未记录 \(compact(mirror.unclassifiedDuration))")
                .font(.title3.monospacedDigit().weight(.medium))
            DatePicker("", selection: $mirror.selectedDay, displayedComponents: .date)
                .labelsHidden()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case 0:
            projectList
        case 1:
            entryList(mirror.engine.drafts(on: mirror.selectedDay), draft: true)
        default:
            entryList(mirror.engine.confirmed(on: mirror.selectedDay), draft: false)
        }
    }

    private var projectList: some View {
        List {
            ForEach(mirror.engine.projects) { project in
                HStack {
                    VStack(alignment: .leading) {
                        Text(project.name).font(.headline)
                        Text(project.categoryName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打标") {
                        do { try mirror.quickRecord(projectId: project.id) }
                        catch { errorText = error.localizedDescription }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func entryList(_ entries: [MirrorTimeEntry], draft: Bool) -> some View {
        List {
            if entries.isEmpty {
                Text(draft ? "暂无草稿" : "暂无已确认")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.projectNameSnapshot).font(.headline)
                        Spacer()
                        Text("\(time(entry.startAt))–\(time(entry.endAt))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if !entry.note.isEmpty {
                        Text(entry.note).font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack {
                        if draft {
                            Button("编辑") { editing = entry }
                            Button("确认") {
                                do { try mirror.confirmEntry(id: entry.id) }
                                catch { errorText = error.localizedDescription }
                            }
                            Button("删除", role: .destructive) {
                                do { try mirror.deleteDraft(id: entry.id) }
                                catch { errorText = error.localizedDescription }
                            }
                        } else {
                            Button("取消确认") {
                                do { try mirror.unconfirmEntry(id: entry.id) }
                                catch { errorText = error.localizedDescription }
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
        }
        .sheet(item: $editing) { entry in
            DraftEditSheet(entry: entry) { start, end, note in
                do {
                    try mirror.updateDraftEntry(id: entry.id, startAt: start, endAt: end, note: note)
                    editing = nil
                } catch {
                    errorText = error.localizedDescription
                }
            } onCancel: {
                editing = nil
            }
        }
    }

    private func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func compact(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let h = m / 60
        let mm = m % 60
        if h > 0 { return "\(h)h\(mm)m" }
        return "\(mm)m"
    }
}

private struct DraftEditSheet: View {
    let entry: MirrorTimeEntry
    var onSave: (Date, Date, String) -> Void
    var onCancel: () -> Void

    @State private var startAt: Date
    @State private var endAt: Date
    @State private var note: String

    init(entry: MirrorTimeEntry, onSave: @escaping (Date, Date, String) -> Void, onCancel: @escaping () -> Void) {
        self.entry = entry
        self.onSave = onSave
        self.onCancel = onCancel
        _startAt = State(initialValue: entry.startAt)
        _endAt = State(initialValue: entry.endAt)
        _note = State(initialValue: entry.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑草稿 · \(entry.projectNameSnapshot)")
                .font(.headline)
            DatePicker("开始", selection: $startAt)
            DatePicker("结束", selection: $endAt)
            TextField("备注", text: $note, axis: .vertical)
                .lineLimit(2...4)
            HStack {
                Button("取消", action: onCancel)
                Spacer()
                Button("保存") { onSave(startAt, endAt, note) }
                    .buttonStyle(.borderedProminent)
                    .disabled(endAt <= startAt)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }
}
