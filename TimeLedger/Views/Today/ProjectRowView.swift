import SwiftUI

struct ProjectRowView: View {
    let project: Project
    let todayDuration: TimeInterval
    let quickRecordAction: () -> Void
    let adjustAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(.secondary.opacity(0.35), lineWidth: 1.5)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let emoji = project.emoji, !emoji.isEmpty {
                        Text(emoji)
                    }
                    Text(project.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                }

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            quickRecordButton
            .accessibilityLabel("快速记录 \(project.name)")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var subtitle: String {
        if todayDuration <= 0 {
            return project.categoryName
        }
        return DurationFormatter.compact(todayDuration, approximate: true)
    }

    private var quickRecordButton: some View {
        let tapGesture = TapGesture().onEnded {
            quickRecordAction()
        }
        let longPressGesture = LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            adjustAction()
        }

        return Image(systemName: "timer")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.accentColor))
            .contentShape(Circle())
            .gesture(longPressGesture.exclusively(before: tapGesture))
            .accessibilityAddTraits(.isButton)
    }
}
