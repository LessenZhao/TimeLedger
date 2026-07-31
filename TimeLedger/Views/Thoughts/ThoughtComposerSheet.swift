import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ThoughtComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let focusTextOnAppear: Bool
    let targetEntry: TimeEntry?

    @State private var draft = ThoughtComposerDraft.empty
    @State private var thoughtBody = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isLoaded = false
    @State private var isImporting = false
    @State private var isSaving = false
    @State private var showingCamera = false
    @State private var showingCameraFixture = false
    @State private var pendingCameraCapture: CameraCapture?
    @State private var cameraAccessResult: CameraAccessResult?
    @State private var errorMessage: String?
    @State private var saveNotice: String?
    @State private var showingDiscardConfirmation = false
    @FocusState private var isTextFocused: Bool

    private let draftStore: ThoughtComposerDraftStore

    init(
        focusTextOnAppear: Bool = true,
        targetEntry: TimeEntry? = nil
    ) {
        self.focusTextOnAppear = focusTextOnAppear
        self.targetEntry = targetEntry
        self.draftStore = targetEntry.map {
            ComposerDraftStoreFactory.thoughtForEntry($0.id)
        } ?? ThoughtComposerDraftStore()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("思考") {
                    TextEditor(text: $thoughtBody)
                        .font(.body)
                        .frame(minHeight: 190)
                        .scrollContentBackground(.hidden)
                        .focused($isTextFocused)
                        .overlay(alignment: .topLeading) {
                            if thoughtBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("记下你的想法，也可以只添加照片…")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityIdentifier("thought.composer.text")
                }

                if let targetEntry {
                    Section {
                        LabeledContent(
                            "关联到",
                            value: "\(DateFormatterFactory.timeOnly.string(from: targetEntry.startAt))–\(DateFormatterFactory.timeOnly.string(from: targetEntry.endAt)) · \(targetEntry.projectNameSnapshot)"
                        )
                    }
                }

                Section {
                    if draft.attachments.isEmpty {
                        Text("还没有照片")
                            .foregroundStyle(.secondary)
                    } else {
                        attachmentStrip
                        Text("\(draft.attachments.count) 张附件")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("thought.composer.attachmentCount")
                    }

                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: max(1, remainingAttachmentCount),
                        matching: .images
                    ) {
                        Label("从照片库添加", systemImage: "photo.on.rectangle")
                    }
                    .disabled(remainingAttachmentCount == 0 || isBusy)
                    .accessibilityIdentifier("thought.composer.photoLibrary")

                    Button {
                        beginCameraFlow()
                    } label: {
                        Label("拍照", systemImage: "camera")
                    }
                    .disabled(remainingAttachmentCount == 0 || isBusy)
                    .accessibilityIdentifier("thought.composer.camera")
                } header: {
                    Text("照片")
                } footer: {
                    Text("最多 9 个附件。拍照或选图后会先保存为可恢复草稿。")
                }

                if draft.hasContent {
                    Section {
                        Button("丢弃这份草稿", role: .destructive) {
                            showingDiscardConfirmation = true
                        }
                        .disabled(isBusy)
                    }
                }
            }
            .navigationTitle("记录思考")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("保存", action: save)
                            .disabled(!draft.hasContent || isImporting)
                            .accessibilityIdentifier("thought.composer.save")
                    }
                }
            }
            .onAppear(perform: loadDraft)
            .onChange(of: thoughtBody) { _, newValue in
                guard isLoaded else { return }
                do {
                    draft = try draftStore.updateBody(newValue)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task { await importPhotos(newItems) }
            }
            .fullScreenCover(
                isPresented: $showingCamera,
                onDismiss: handleCameraDismissal
            ) {
                SystemCameraPicker(
                    mediaTypes: SystemCameraConfiguration.photoOnlyMediaTypes
                ) { result in
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
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("已保存", isPresented: Binding(
                get: { saveNotice != nil },
                set: { if !$0 { saveNotice = nil } }
            )) {
                Button("好") { dismiss() }
            } message: {
                Text(saveNotice ?? "")
            }
            .confirmationDialog(
                "丢弃这份草稿？",
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("丢弃", role: .destructive) {
                    Task { await discardDraft() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会删除尚未正式保存的文字和附件。")
            }
        }
    }

    private var isBusy: Bool {
        isImporting || isSaving
    }

    private var remainingAttachmentCount: Int {
        max(0, ThoughtComposerDraftStore.maximumAttachmentCount - draft.attachments.count)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(draft.attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let image = UIImage(data: attachment.thumbnailData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: attachment.kind == .photo ? "photo" : "video")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 112, height: 88)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            Task { await removeAttachment(attachment) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.65))
                        }
                        .offset(x: 5, y: -5)
                        .accessibilityLabel("移除附件")
                    }
                    .accessibilityIdentifier(
                        "thought.composer.attachment.\(attachment.id.uuidString)"
                    )
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func loadDraft() {
        do {
            let loaded = try draftStore.load()
            draft = loaded
            thoughtBody = loaded.body
            isLoaded = true
            if focusTextOnAppear {
                DispatchQueue.main.async {
                    isTextFocused = true
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer {
            selectedPhotoItems = []
            isImporting = false
        }

        do {
            for item in items.prefix(remainingAttachmentCount) {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ThoughtComposerDraftStoreError.invalidPhoto
                }
                guard let image = UIImage(data: data),
                      let thumbnailData = MediaThumbnailFactory.thumbnailData(for: image) else {
                    throw ThoughtComposerDraftStoreError.invalidPhoto
                }
                let fileExtension = item.supportedContentTypes
                    .first(where: { $0.conforms(to: .image) })?
                    .preferredFilenameExtension
                    ?? "jpg"
                draft = try await draftStore.addPhotoData(
                    data,
                    thumbnailData: thumbnailData,
                    fileExtension: fileExtension
                )
                thoughtBody = draft.body
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
                thoughtBody = draft.body
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeAttachment(_ attachment: ThoughtComposerDraftAttachment) async {
        do {
            draft = try await draftStore.removeAttachment(id: attachment.id)
            thoughtBody = draft.body
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard draft.hasContent else { return }
        isSaving = true
        isTextFocused = false

        Task {
            do {
                let preference = try mediaStoragePreference()
                let result = try await ThoughtComposerCommitService(
                    modelContext: modelContext,
                    draftStore: draftStore
                ).commit(
                    draft,
                    preference: preference,
                    targetEntry: targetEntry
                )
                if result.mediaIssues.isEmpty {
                    dismiss()
                } else {
                    saveNotice = "思考已保存，但有 \(result.mediaIssues.count) 个附件未完全保存，原件已保留，可在时间线重试。"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func discardDraft() async {
        do {
            try await draftStore.discard()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mediaStoragePreference() throws -> MediaStoragePreference {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        if let settings = try modelContext.fetch(descriptor).first {
            return MediaStoragePreference(rawValue: settings.mediaStoragePreference)
                ?? .photosLibrary
        }
        let settings = AppSettings()
        modelContext.insert(settings)
        try modelContext.save()
        return settings.mediaStorage
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private extension AppSettings {
    var mediaStorage: MediaStoragePreference {
        MediaStoragePreference(rawValue: mediaStoragePreference) ?? .photosLibrary
    }
}
