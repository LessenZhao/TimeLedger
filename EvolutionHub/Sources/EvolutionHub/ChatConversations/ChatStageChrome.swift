import SwiftUI

/// Center-stage primary actions. Short fixed labels only.
enum ChatStageMode: String, CaseIterable, Identifiable {
    case read = "阅读"
    case edit = "编辑"
    case source = "原文"

    var id: Self { self }

    static let displayOrder: [ChatStageMode] = [.read, .edit, .source]
}

/// One-row stage column header. No meta labels like「主操作」.
struct ChatStageHeader<Trailing: View>: View {
    @Binding var mode: ChatStageMode
    var title: String? = nil
    var subtitle: String? = nil
    var enabledModes: Set<ChatStageMode> = Set(ChatStageMode.allCases)
    @ViewBuilder var trailing: () -> Trailing

    init(
        mode: Binding<ChatStageMode>,
        title: String? = nil,
        subtitle: String? = nil,
        enabledModes: Set<ChatStageMode> = Set(ChatStageMode.allCases),
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self._mode = mode
        self.title = title
        self.subtitle = subtitle
        self.enabledModes = enabledModes
        self.trailing = trailing
    }

    private var visibleModes: [ChatStageMode] {
        ChatStageMode.displayOrder.filter { enabledModes.contains($0) }
    }

    var body: some View {
        HStack(spacing: 8) {
            if visibleModes.count > 1 {
                Picker("模式", selection: modeBinding) {
                    ForEach(visibleModes) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: CGFloat(max(120, visibleModes.count * 56)))
                .controlSize(.small)
            }

            if let title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: ChatChromeMetrics.headerHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { clampMode() }
        .onChange(of: enabledModes) { _, _ in clampMode() }
    }

    private var modeBinding: Binding<ChatStageMode> {
        Binding(
            get: { mode },
            set: { newValue in
                mode = enabledModes.contains(newValue) ? newValue : (visibleModes.first ?? .read)
            }
        )
    }

    private func clampMode() {
        if !enabledModes.contains(mode) {
            mode = visibleModes.first ?? .read
        }
    }
}
