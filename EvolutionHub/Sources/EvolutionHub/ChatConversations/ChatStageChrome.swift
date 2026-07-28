import SwiftUI

/// Center-stage primary actions. Short fixed labels only.
enum ChatStageMode: String, CaseIterable, Identifiable {
    case read = "阅读"
    case edit = "编辑"
    case source = "原文"
    case excerpt = "摘录"

    var id: Self { self }

    static let displayOrder: [ChatStageMode] = [.read, .edit, .source, .excerpt]
}

/// Fixed stage chrome: 阅读 | 编辑 | 原文 | 摘录
struct ChatStageHeader: View {
    @Binding var mode: ChatStageMode
    var title: String? = nil
    var subtitle: String? = nil
    var enabledModes: Set<ChatStageMode> = Set(ChatStageMode.allCases)

    private var visibleModes: [ChatStageMode] {
        ChatStageMode.displayOrder.filter { enabledModes.contains($0) }
    }

    var body: some View {
        HStack(spacing: 12) {
            Picker("主操作", selection: modeBinding) {
                ForEach(visibleModes) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
