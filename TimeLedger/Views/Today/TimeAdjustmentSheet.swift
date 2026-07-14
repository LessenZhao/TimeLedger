import SwiftUI

struct TimeAdjustmentSheet: View {
    let project: Project
    let cursorAt: Date
    let defaultEndAt: Date
    let saveAction: (Date, Date, String) -> Void
    let skipAction: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var note: String
    @State private var validationMessage: String?

    init(
        project: Project,
        cursorAt: Date,
        defaultEndAt: Date,
        note: String = "",
        saveAction: @escaping (Date, Date, String) -> Void,
        skipAction: @escaping (Date) -> Void
    ) {
        self.project = project
        self.cursorAt = cursorAt
        self.defaultEndAt = defaultEndAt
        self.saveAction = saveAction
        self.skipAction = skipAction
        let cappedEnd = min(defaultEndAt, Date())
        let initialStart = min(cursorAt, cappedEnd)
        _startAt = State(initialValue: initialStart)
        _endAt = State(initialValue: max(cappedEnd, initialStart.addingTimeInterval(60)))
        _note = State(initialValue: note)
    }

    private var nowBound: Date { Date() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("项目", value: project.name)
                    LabeledContent("未记录", value: DurationFormatter.compact(max(0, endAt.timeIntervalSince(startAt))))
                }

                Section {
                    DatePicker(
                        "开始",
                        selection: $startAt,
                        in: cursorAt...nowBound,
                        displayedComponents: [.hourAndMinute]
                    )
                    DatePicker(
                        "结束",
                        selection: $endAt,
                        in: startAt...nowBound,
                        displayedComponents: [.hourAndMinute]
                    )
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    Text("开始不早于未记录起点，结束不晚于当前时间。")
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("跳过这段时间", role: .destructive) {
                        let skipTo = min(max(endAt, cursorAt.addingTimeInterval(60)), nowBound)
                        skipAction(skipTo)
                        dismiss()
                    }
                }
            }
            .navigationTitle("调整时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        save()
                    }
                }
            }
            .onChange(of: startAt) { _, newStart in
                if endAt <= newStart {
                    endAt = min(newStart.addingTimeInterval(60), nowBound)
                }
                if endAt > nowBound {
                    endAt = nowBound
                }
            }
            .onChange(of: endAt) { _, newEnd in
                if newEnd > nowBound {
                    endAt = nowBound
                }
            }
        }
    }

    private func save() {
        let now = Date()
        guard endAt > startAt else {
            validationMessage = "结束时间必须晚于开始时间。"
            return
        }
        guard startAt >= cursorAt else {
            validationMessage = "开始时间不能早于未记录起点。"
            return
        }
        guard endAt <= now else {
            validationMessage = "结束时间不能晚于当前时间。"
            return
        }

        saveAction(startAt, endAt, note.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

#Preview {
    let project = Project(name: "写材料", categoryName: "工作")
    TimeAdjustmentSheet(
        project: project,
        cursorAt: Date(timeIntervalSinceNow: -1_800),
        defaultEndAt: Date(),
        saveAction: { _, _, _ in },
        skipAction: { _ in }
    )
}
