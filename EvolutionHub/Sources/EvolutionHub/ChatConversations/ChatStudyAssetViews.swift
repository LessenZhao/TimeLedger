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


// MARK: - Catalog tree rows (L1 group / L2 segment / L3 asset)

/// L1 — session / topic / kind container.
struct CatalogTreeGroupHeader: View {
    let title: String
    let subtitle: String
    let isExpanded: Bool
    var icon: String = "folder.fill"
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12)

                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlAccentColor).opacity(isExpanded ? 0.10 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isExpanded)
    }
}

/// L2 — numbered segment directory row.
struct CatalogTreeSegmentRow: View {
    let index: Int
    let title: String
    let meta: String
    var isFocused: Bool = false
    var showsSummary: Bool = false
    var summary: String = ""
    var isExpanded: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                // Tree elbow into the group
                ZStack {
                    if isExpanded || isFocused {
                        // keep rail alignment
                    }
                    Text("\(index)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isFocused ? Color.white : Color.secondary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(isFocused ? Color.accentColor : Color.secondary.opacity(0.16))
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? "未命名片段" : title)
                        .font(.system(size: 12.5, weight: isFocused ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(meta)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        if isExpanded {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if showsSummary, isFocused, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isFocused ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isFocused ? Color.accentColor : Color.clear)
                    .frame(width: 3, height: 20)
                    .padding(.leading, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// L3 — quiet asset leaf under a segment.
struct CatalogTreeAssetRow: View {
    let title: String
    let kind: ChatStudyAssetKind
    var uses: Set<ChatStudyAssetUse> = []
    var isHighlighted: Bool = false
    var isSelected: Bool = false
    var isIncluded: Bool? = nil
    /// Leading inset for the whole leaf row (tree depth).
    var indent: CGFloat = 44
    let action: () -> Void
    var onToggleInclude: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: action) {
                HStack(alignment: .center, spacing: 8) {
                    // Vertical rail + leaf tick
                    ZStack(alignment: .center) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.22))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                        Circle()
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.secondary.opacity(0.45),
                                lineWidth: 1.2
                            )
                            .background(Circle().fill(isSelected ? Color.accentColor : Color.clear))
                            .frame(width: 7, height: 7)
                    }
                    .frame(width: 12, height: 28)

                    Text(title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 6)

                    // Trailing meta — monochrome, not a badge pile
                    Text(trailingMeta)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                .padding(.trailing, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let isIncluded {
                Button {
                    onToggleInclude?()
                } label: {
                    Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isIncluded ? Color.accentColor : Color.secondary.opacity(0.7))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(isIncluded ? "取消纳入" : "纳入本次确认")
            }
        }
        .padding(.leading, indent)
        .padding(.trailing, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.30) : Color.clear, lineWidth: 1)
        )
    }

    private var trailingMeta: String {
        var parts: [String] = [shortKind]
        if let useLabel { parts.append(useLabel) }
        if isHighlighted { parts.append("重点") }
        return parts.joined(separator: " · ")
    }

    private var shortKind: String {
        switch kind {
        case .finishedWork: return "范文"
        case .expressionModule: return "表达"
        case .sourceMaterial: return "素材"
        case .methodStrategy: return "方法"
        case .viewpointKnowledge: return "观点"
        }
    }

    private var useLabel: String? {
        let priority: [ChatStudyAssetUse] = [.memorize, .review, .imitate, .quote, .practice]
        guard let first = priority.first(where: { uses.contains($0) }) else { return nil }
        switch first {
        case .memorize: return "背诵"
        case .review: return "复习"
        case .imitate: return "仿写"
        case .quote: return "引用"
        case .practice: return "实践"
        }
    }
}

/// Wraps L2+L3 under a group with a shared left tree gutter.
struct CatalogTreeBranch<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            content()
        }
        .padding(.leading, 4)
        .padding(.top, 2)
        .padding(.bottom, 6)
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
    /// Parallel reading notes on the current formal body (not asset.note).
    var readingNotes: [ReadingNote] = []
    var allowsReadingNotes: Bool = false
    /// Formal reader identity; candidates intentionally leave this empty.
    var formalAssetID: String? = nil
    var formalVersionID: String? = nil
    var onReadingHighlight: ((ObsidianReaderSelection) -> Void)? = nil
    var onReadingSaveNote: ((ObsidianReaderSelection, String) -> Void)? = nil
    var onReadingUpdateNote: ((ReadingNote, String) -> Void)? = nil
    var onReadingDeleteNote: ((ReadingNote) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if draftTextBinding == nil, !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AnnotatableMarkdownReader(
                    source: bodyText,
                    notes: allowsReadingNotes ? readingNotes : [],
                    allowsNotes: allowsReadingNotes,
                    bodyFontSize: 16,
                    assetId: formalAssetID,
                    versionId: formalVersionID,
                    onHighlight: { selection in onReadingHighlight?(selection) },
                    onSaveNote: { selection, body in onReadingSaveNote?(selection, body) },
                    onUpdateNote: { note, body in onReadingUpdateNote?(note, body) },
                    onDeleteNote: { note in onReadingDeleteNote?(note) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let note, !note.isEmpty {
                    Divider()
                    assetNote(note)
                }
            } else {
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
                        } else {
                            Text(emptyBodyPlaceholder ?? "暂无正文")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 24)
                        }
                    }
                    .padding(20)
                }
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

    private func assetNote(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("备注")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
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
