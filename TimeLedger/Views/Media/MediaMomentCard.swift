import SwiftData
import SwiftUI

struct MediaMomentCard: View {
    @Environment(\.modelContext) private var modelContext

    let moment: MediaMoment
    let linkedEntry: TimeEntry?

    @State private var showingViewer = false
    @State private var showingManualLink = false
    @State private var showingDeleteAlert = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showingViewer = true
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Label(
                                moment.kind == .photo ? "照片" : "视频",
                                systemImage: moment.kind == .photo ? "photo" : "video"
                            )
                            .font(.body.weight(.semibold))
                            Spacer()
                            Text(DateFormatterFactory.timeOnly.string(from: moment.capturedAt))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(linkedEntry?.projectNameSnapshot ?? "未关联时间项目")
                            .font(.footnote)
                            .foregroundStyle(linkedEntry == nil ? Color.orange : Color.secondary)
                        if moment.kind == .video {
                            Text(DurationFormatter.compact(moment.durationSeconds))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        statusLine
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 16) {
                if moment.linkedEntryId == nil {
                    Button("手动关联") { showingManualLink = true }
                } else {
                    Button("取消关联", role: .destructive) { unlink() }
                }

                if moment.saveStatus == .partial || moment.saveStatus == .failed {
                    Button("重试") {
                        Task {
                            await MediaMomentService(modelContext: modelContext).retry(moment)
                        }
                    }
                    Button("改存 App") {
                        Task {
                            await MediaMomentService(modelContext: modelContext).saveToAppInstead(moment)
                        }
                    }
                }

                Spacer()
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
            }
            .font(.caption)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .fullScreenCover(isPresented: $showingViewer) {
            MediaViewer(moment: moment)
        }
        .sheet(isPresented: $showingManualLink) {
            MediaManualLinkView(moment: moment)
        }
        .alert("删除这条媒体记录？", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task {
                    await MediaMomentService(modelContext: modelContext).deleteRecord(moment)
                }
            }
        } message: {
            Text("只删除 TimeLedger 中的 App 文件、缩略图和记录，绝不会删除系统相册原件。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await MediaMomentService(modelContext: modelContext)
                .refreshOriginalAvailability(moment)
        }
    }

    private var thumbnail: some View {
        TimelineThumbnailView(
            mediaID: moment.id,
            thumbnailData: moment.thumbnailData,
            kind: moment.kind,
            size: CGSize(width: 92, height: 72)
        )
        .overlay(alignment: .center) {
            if moment.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if moment.availability == .unavailable {
            Label("原件不可用", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
        } else if moment.saveStatus == .partial {
            Label("部分保存，原件已保留", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .font(.caption)
        } else if moment.saveStatus == .failed {
            Label("保存失败，原件待重试", systemImage: "xmark.circle")
                .foregroundStyle(.red)
                .font(.caption)
        } else if moment.saveStatus == .pending {
            Label("正在保存", systemImage: "clock")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func unlink() {
        do {
            try MediaLinkingService(modelContext: modelContext).unlink(moment)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
