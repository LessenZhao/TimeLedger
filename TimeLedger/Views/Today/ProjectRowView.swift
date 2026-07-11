import SwiftUI

struct ProjectRowView: View {
    let project: Project
    let todayDuration: TimeInterval
    let quickRecordAction: () -> Void
    let adjustAction: () -> Void

    private var projectColor: Color {
        Color(hex: project.colorHex)
    }

    var body: some View {
        HStack(spacing: 10) {
            swatch

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(TLTheme.projectNameFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(TLTheme.metaFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            quickRecordButton
                .accessibilityLabel("快速记录 \(project.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, TLTheme.rowVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: TLTheme.cardRadius)
                .fill(TLTheme.cardBackground)
        )
    }

    private var swatch: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(projectColor.opacity(0.16))
            .frame(width: TLTheme.swatchSize, height: TLTheme.swatchSize)
            .overlay {
                if let emoji = project.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 13))
                } else {
                    Circle()
                        .fill(projectColor)
                        .frame(width: 8, height: 8)
                }
            }
    }

    private var subtitle: String {
        let durationText: String
        if todayDuration <= 0 {
            durationText = "—"
        } else {
            durationText = DurationFormatter.compact(todayDuration, approximate: true)
        }
        return "\(project.categoryName) · \(durationText)"
    }

    private var quickRecordButton: some View {
        let tapGesture = TapGesture().onEnded {
            quickRecordAction()
        }
        let longPressGesture = LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            adjustAction()
        }

        return Text("+")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: TLTheme.actionButtonSize, height: TLTheme.actionButtonSize)
            .background(Circle().fill(Color.accentColor))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .gesture(longPressGesture.exclusively(before: tapGesture))
            .accessibilityAddTraits(.isButton)
    }
}
