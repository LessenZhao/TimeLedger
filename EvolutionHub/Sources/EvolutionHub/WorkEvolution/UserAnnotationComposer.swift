import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct UserAnnotationComposerContext: Identifiable {
    let target: AnnotationTarget
    let targetSummary: String
    let entryLabel: String

    var id: String {
        "\(target.kind.rawValue):\(target.targetId)"
    }
}

struct UserAnnotationComposer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkEvolutionHubStore

    let context: UserAnnotationComposerContext

    @State private var kind: AnnotationKind = .supplement
    @State private var annotationBody = ""
    @State private var happenedAt: Date?
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.entryLabel)
                        .font(.title2.bold())
                    Text(context.targetSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }

            LabeledContent("关联目标") {
                Text("\(targetKindLabel(context.target.kind)) / \(context.target.targetId)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Picker("内容类型", selection: $kind) {
                Text("补充").tag(AnnotationKind.supplement)
                Text("纠正").tag(AnnotationKind.correction)
                Text("后来认识").tag(AnnotationKind.reflection)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("内容").font(.headline)
                TextEditor(text: $annotationBody)
                    .font(.body)
                    .frame(minHeight: 150)
                    .padding(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25))
                    )
            }

            if kind == .reflection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("事情发生时间").font(.headline)
                    if happenedAt == nil {
                        Button {
                            happenedAt = Date()
                        } label: {
                            Label("选择发生时间", systemImage: "calendar.badge.plus")
                        }
                        Text("“后来认识”必须区分事情实际发生时间与今天的认识时间。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        DatePicker(
                            "实际发生",
                            selection: happenedAtBinding,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        Button("清除发生时间", role: .destructive) {
                            happenedAt = nil
                        }
                        .font(.caption)
                    }
                }
            }

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Text("认识时间会在保存时自动记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 580, minHeight: 430)
        .onChange(of: kind) { _, newValue in
            if newValue != .reflection {
                happenedAt = nil
            }
            saveError = nil
        }
    }

    private var trimmedBody: String {
        annotationBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedBody.isEmpty && (kind != .reflection || happenedAt != nil)
    }

    private var happenedAtBinding: Binding<Date> {
        Binding(
            get: { happenedAt ?? Date() },
            set: { happenedAt = $0 }
        )
    }

    private func save() {
        guard canSave else { return }
        do {
            try store.addAnnotation(
                target: context.target,
                kind: kind,
                body: trimmedBody,
                happenedAt: kind == .reflection ? happenedAt : nil
            )
            annotationBody = ""
            happenedAt = nil
            saveError = nil
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private func targetKindLabel(_ kind: AnnotationTargetKind) -> String {
    switch kind {
    case .day: return "日期"
    case .project: return "项目"
    case .projectDaySlice: return "项目日切片"
    case .evolutionNode: return "演化节点"
    case .sourceSession: return "来源会话"
    }
}
