import SwiftData
import SwiftUI

struct TimeEntryNoteCard: View {
    let record: TimelineRecord
    let onEdit: () -> Void

    @State private var selectedMedia: MediaMoment?

    init(
        record: TimelineRecord,
        onEdit: @escaping () -> Void = {}
    ) {
        self.record = record
        self.onEdit = onEdit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: TimelineCardActionMetrics.spacing) {
                Text(timeRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                TimelineKindBadge(
                    title: "备注",
                    tint: Color.blue.opacity(0.14),
                    foreground: Color.blue.opacity(0.9)
                )
                VisibleEditButton(
                    accessibilityLabel: "编辑",
                    accessibilityIdentifier: "timeline.note.edit",
                    action: onEdit
                )
            }

            if let entry = record.linkedEntry {
                Text(entry.projectNameSnapshot)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if record.hasText {
                TimelineExpandableText(text: record.noteText, style: .note)
            }

            if !record.mediaMoments.isEmpty {
                TimelineMediaGrid(moments: record.mediaMoments) { moment in
                    selectedMedia = moment
                }
            }

            if record.relatedThoughtCount > 0 {
                Text("关联思考 \(record.relatedThoughtCount) 条")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("timeline.note.relatedThoughts")
            }
        }
        .padding(16)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.card.note")
        .fullScreenCover(item: $selectedMedia) { moment in
            MediaViewer(moment: moment)
        }
    }

    private var timeRangeText: String {
        guard let end = record.displayEndAt else {
            return DateFormatterFactory.dateTime.string(from: record.capturedAt)
        }
        let start = DateFormatterFactory.timeOnly.string(from: record.capturedAt)
        let endText = DateFormatterFactory.timeOnly.string(from: end)
        return "\(start) – \(endText)"
    }
}
