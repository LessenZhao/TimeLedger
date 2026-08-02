import PhotosUI
import SwiftUI
import UIKit

struct PhotoAttachmentEditor: View {
    @Binding var draft: ThoughtComposerDraft
    @Binding var isImporting: Bool

    let draftStore: ThoughtComposerDraftStore
    let existingMoments: [MediaMoment]
    let isDisabled: Bool
    let removeExisting: (MediaMoment) async throws -> Void

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showingSourcePicker = false
    @State private var showingPhotoLibrary = false
    @State private var showingCamera = false
    @State private var showingCameraFixture = false
    @State private var pendingCameraCapture: CameraCapture?
    @State private var cameraAccessResult: CameraAccessResult?
    @State private var errorMessage: String?

    private var existingIDs: Set<UUID> {
        Set(existingMoments.map(\.id))
    }

    private var visibleStagedAttachments: [ThoughtComposerDraftAttachment] {
        draft.attachments.filter { !existingIDs.contains($0.id) }
    }

    private var visibleAttachmentCount: Int {
        existingMoments.count + visibleStagedAttachments.count
    }

    private var remainingAttachmentCount: Int {
        max(0, ThoughtComposerDraftStore.maximumAttachmentCount - visibleAttachmentCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if visibleAttachmentCount > 0 {
                attachmentStrip
            }

            Button {
                showingSourcePicker = true
            } label: {
                Label("添加媒体", systemImage: "plus")
            }
            .disabled(remainingAttachmentCount == 0 || isDisabled || isImporting)
            .accessibilityIdentifier("entry.attachment.add")
        }
        .confirmationDialog(
            "添加媒体",
            isPresented: $showingSourcePicker,
            titleVisibility: .visible
        ) {
            Button("拍照或录像") {
                beginCameraFlow()
            }
            Button("从照片库选择照片或视频") {
                showingPhotoLibrary = true
            }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showingPhotoLibrary,
            selection: $selectedPhotoItems,
            maxSelectionCount: max(1, remainingAttachmentCount),
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await importMedia(newItems) }
        }
        .fullScreenCover(
            isPresented: $showingCamera,
            onDismiss: handleCameraDismissal
        ) {
            SystemCameraPicker { result in
                guard let result else {
                    showingCamera = false
                    return
                }
                switch result {
                case .success(let capture):
                    pendingCameraCapture = capture
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
                showingCamera = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(
            isPresented: $showingCameraFixture,
            onDismiss: handleCameraDismissal
        ) {
            CameraBoundaryFixtureView { capture in
                pendingCameraCapture = capture
                showingCameraFixture = false
            }
        }
        .alert("无法打开相机", isPresented: Binding(
            get: { cameraAccessResult != nil },
            set: { if !$0 { cameraAccessResult = nil } }
        )) {
            if cameraAccessResult?.offersSettings == true {
                Button("去设置", action: openSystemSettings)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(cameraAccessResult?.message ?? "")
        }
        .alert("照片处理失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(existingMoments) { moment in
                    thumbnail(
                        id: moment.id,
                        data: moment.thumbnailData,
                        kind: moment.kind,
                        hasIssue: moment.saveStatus != .saved
                    ) {
                        Task { await remove(moment) }
                    }
                }

                ForEach(visibleStagedAttachments) { attachment in
                    thumbnail(
                        id: attachment.id,
                        data: attachment.thumbnailData,
                        kind: attachment.kind,
                        hasIssue: false
                    ) {
                        Task { await remove(attachment) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func thumbnail(
        id: UUID,
        data: Data,
        kind: MediaKind,
        hasIssue: Bool,
        removeAction: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            TimelineThumbnailView(
                mediaID: id,
                thumbnailData: data,
                kind: kind,
                size: CGSize(width: 72, height: 58)
            )
            .overlay(alignment: .bottomLeading) {
                if hasIssue {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(5)
                }
            }

            Button(action: removeAction) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.65))
            }
            .offset(x: 5, y: -5)
            .accessibilityLabel("移除媒体")
        }
        .accessibilityIdentifier("entry.attachment.\(id.uuidString)")
    }

    private func importMedia(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer {
            selectedPhotoItems = []
            isImporting = false
        }

        do {
            for item in items.prefix(remainingAttachmentCount) {
                draft = try await PhotoLibraryMediaImportService.add(
                    item,
                    to: draftStore
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginCameraFlow() {
        guard remainingAttachmentCount > 0 else { return }
        if ProcessInfo.processInfo.arguments.contains("-ui-camera-fixture") {
            showingCameraFixture = true
            return
        }

        Task {
            let result = await CameraPermissionService().prepareForCamera()
            if result == .ready {
                showingCamera = true
            } else {
                cameraAccessResult = result
            }
        }
    }

    private func handleCameraDismissal() {
        guard let capture = pendingCameraCapture else { return }
        pendingCameraCapture = nil
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                draft = try await draftStore.addCapture(capture)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ attachment: ThoughtComposerDraftAttachment) async {
        isImporting = true
        defer { isImporting = false }
        do {
            draft = try await draftStore.removeAttachment(id: attachment.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ moment: MediaMoment) async {
        isImporting = true
        defer { isImporting = false }
        do {
            if draft.attachments.contains(where: { $0.id == moment.id }) {
                draft = try await draftStore.removeAttachment(id: moment.id)
            }
            try await removeExisting(moment)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
