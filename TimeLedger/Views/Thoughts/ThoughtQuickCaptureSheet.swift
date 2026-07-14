import SwiftUI
import SwiftData

struct ThoughtQuickCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var thoughtBody: String = ""
    @State private var errorMessage: String?
    @State private var linkingResult: LinkingResult?
    @FocusState private var isFocused: Bool

    private let draftStore = ThoughtDraftStore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("记下你的想法…", text: $thoughtBody, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($isFocused)
                } header: {
                    Text("思考")
                } footer: {
                    if let result = linkingResult {
                        Label(result.message, systemImage: result.icon)
                            .foregroundStyle(result.color)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("快速想法")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存", action: save)
                        .disabled(thoughtBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                thoughtBody = draftStore.load(.quickCapture)
                isFocused = true
            }
            .onChange(of: thoughtBody) { _, newValue in
                draftStore.save(newValue, for: .quickCapture)
            }
        }
    }

    private func save() {
        let trimmed = thoughtBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let now = Date()
            let thought = try ThoughtLinkingService(modelContext: modelContext).quickCaptureThought(body: trimmed, now: now)
            draftStore.clear(.quickCapture)
            linkingResult = checkLinkStatus(thought: thought)

            if linkingResult != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    dismiss()
                }
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func checkLinkStatus(thought: ThoughtNote) -> LinkingResult {
        if let entryId = thought.linkedEntryId {
            let entries = (try? modelContext.fetch(FetchDescriptor<TimeEntry>())) ?? []
            if let entry = entries.first(where: { $0.id == entryId }) {
                let timeRange = "\(DateFormatterFactory.timeOnly.string(from: entry.startAt)) - \(DateFormatterFactory.timeOnly.string(from: entry.endAt))"
                return LinkingResult(message: "已关联到：\(timeRange)｜\(entry.projectNameSnapshot)", icon: "checkmark.circle.fill", color: .green)
            }
        }
        return LinkingResult(message: "已保存，等待匹配到时间段", icon: "clock", color: .secondary)
    }
}

private struct LinkingResult {
    let message: String
    let icon: String
    let color: Color
}
