import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct ChatStudyAssetMetaBadges: View {
    let kind: ChatStudyAssetKind
    let subtype: String
    let uses: Set<ChatStudyAssetUse>
    var preservation: ChatStudyAssetPreservation? = nil
    var origin: ChatStudyAssetOrigin? = nil
    var isHighlighted: Bool = false
    var compact: Bool = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                badgeRow
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    badgeRow
                }
            }
        }
    }

    @ViewBuilder
    private var badgeRow: some View {
        badge(ChatStudyAssetKindLabel.title(for: kind), emphasized: true)
        if !subtype.isEmpty, subtype != ChatStudyAssetKindLabel.title(for: kind) {
            badge(subtype)
        }
        if let preservation {
            badge(preservation == .verbatim ? "原文" : "提炼")
        }
        if let origin {
            badge(originLabel(origin))
        }
        ForEach(uses.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { use in
            badge(ChatStudyAssetUseLabel.title(for: use))
        }
        if isHighlighted {
            badge("重点", tint: .orange)
        }
    }

    private func badge(_ text: String, emphasized: Bool = false, tint: Color? = nil) -> some View {
        Text(text)
            .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 3)
            .foregroundStyle(tint ?? (emphasized ? Color.accentColor : Color.primary.opacity(0.8)))
            .background(
                Capsule().fill((tint ?? Color.secondary).opacity(tint == nil ? 0.12 : 0.16))
            )
    }

    private func originLabel(_ origin: ChatStudyAssetOrigin) -> String {
        switch origin {
        case .skill: return "AI识别"
        case .userSelection: return "人工摘录"
        case .userEdited: return "用户修改"
        }
    }
}

struct ChatStudyAssetCatalogRow: View {
    let title: String
    let kind: ChatStudyAssetKind
    let subtype: String
    let uses: Set<ChatStudyAssetUse>
    var isHighlighted: Bool = false
    var isSelected: Bool = false
    var isIncluded: Bool? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                ChatStudyAssetMetaBadges(
                    kind: kind,
                    subtype: subtype,
                    uses: uses,
                    isHighlighted: isHighlighted,
                    compact: true
                )
            }
            Spacer(minLength: 0)
            if let isIncluded {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isIncluded ? Color.accentColor : Color.secondary)
                    .imageScale(.medium)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ChatStudyAssetReaderPane: View {
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
    var sourceView: ChatConversationSourceView? = nil
    var onEditCandidate: (() -> Void)? = nil
    var onShowVersions: (() -> Void)? = nil
    var onEditVersion: (() -> Void)? = nil
    var draftTextBinding: Binding<String>? = nil
    var emptyBodyPlaceholder: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let draftTextBinding, preservation == .distilled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("候选正文（可编辑）")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextEditor(text: draftTextBinding)
                                .font(.system(size: 15))
                                .frame(minHeight: 280)
                        }
                    } else if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(emptyBodyPlaceholder ?? "暂无正文")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 24)
                    } else {
                        MarkdownBodyView(text: bodyText, bodyFontSize: 15)
                    }

                    if let note, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("备注")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(note)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            ChatStudyAssetMetaBadges(
                kind: kind,
                subtype: subtype,
                uses: uses,
                preservation: preservation,
                origin: origin,
                isHighlighted: isHighlighted
            )

            if let sourceStatus {
                Text(sourceStatusLabel(sourceStatus))
                    .font(.caption)
                    .foregroundStyle(sourceStatus == .current ? Color.secondary : Color.orange)
            }

            HStack(spacing: 12) {
                if let isIncluded {
                    Toggle("纳入本次确认", isOn: isIncluded)
                        .toggleStyle(.switch)
                }
                Spacer(minLength: 0)
                if let sourceView {
                    sourceView
                }
                if let onEditCandidate {
                    Button("编辑候选", action: onEditCandidate)
                }
                if let onShowVersions {
                    Button("历史版本", action: onShowVersions)
                }
                if let onEditVersion {
                    Button("创建修改版", action: onEditVersion)
                }
            }
            .controlSize(.regular)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .windowBackgroundColor))
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
