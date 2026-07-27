import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct ChatStudyAssetCard: View {
    let title: String
    let kind: ChatStudyAssetKind
    let subtype: String
    let uses: Set<ChatStudyAssetUse>
    let preservation: ChatStudyAssetPreservation
    let origin: ChatStudyAssetOrigin
    let bodyText: String
    var isHighlighted: Bool = false
    var note: String? = nil
    var sourceStatus: ChatConversationSourceStatus? = nil
    var isIncluded: Binding<Bool>? = nil
    var onOpenSource: (() -> Void)? = nil
    var onShowVersions: (() -> Void)? = nil
    var onEditVersion: (() -> Void)? = nil
    var draftTextBinding: Binding<String>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                if let isIncluded {
                    Toggle("纳入本次确认", isOn: isIncluded)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Text("纳入本次确认")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                badge(ChatStudyAssetKindLabel.title(for: kind))
                badge(subtype)
                badge(preservation == .verbatim ? "原文" : "提炼")
                badge(originLabel)
                ForEach(uses.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { use in
                    badge(ChatStudyAssetUseLabel.title(for: use))
                }
                if isHighlighted {
                    badge("重点")
                }
            }

            if let sourceStatus {
                Text(sourceStatusLabel(sourceStatus))
                    .font(.caption)
                    .foregroundStyle(sourceStatus == .current ? Color.secondary : Color.orange)
            }

            if let draftTextBinding, preservation == .distilled {
                TextEditor(text: draftTextBinding)
                    .font(.body)
                    .frame(minHeight: 80)
            } else {
                Text(bodyText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let note, !note.isEmpty {
                Text("备注：\(note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if let onOpenSource {
                    Button("查看原文上下文", action: onOpenSource)
                        .buttonStyle(.borderless)
                }
                if let onShowVersions {
                    Button("查看历史版本", action: onShowVersions)
                        .buttonStyle(.borderless)
                }
                if let onEditVersion {
                    Button("创建修改版", action: onEditVersion)
                        .buttonStyle(.borderless)
                }
            }
            .font(.caption)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var originLabel: String {
        switch origin {
        case .skill: return "AI识别"
        case .userSelection: return "人工摘录"
        case .userEdited: return "用户修改"
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    private func sourceStatusLabel(_ status: ChatConversationSourceStatus) -> String {
        switch status {
        case .current:
            return "来源：原文已校验"
        case .changed:
            return "来源：归档内容已变化，仍显示已确认快照"
        case .unavailable:
            return "来源：归档不可用，仍显示已确认快照"
        case .legacyUnscoped:
            return "旧版材料只能定位到整条消息，不能证明逐字摘录范围"
        }
    }
}
