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
        _startAt = State(initialValue: cursorAt)
        _endAt = State(initialValue: defaultEndAt)
        _note = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("项目", value: project.name)
                    LabeledContent("未记录", value: DurationFormatter.compact(max(0, endAt.timeIntervalSince(startAt))))
                }

                Section {
                    DatePicker("开始", selection: $startAt, displayedComponents: [.hourAndMinute])
                    DatePicker("结束", selection: $endAt, displayedComponents: [.hourAndMinute])
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("跳过这段时间", role: .destructive) {
                        skipAction(endAt)
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
        }
    }

    private func save() {
        guard endAt > startAt else {
            validationMessage = "结束时间必须晚于开始时间。"
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
