import EvolutionCore
import EvolutionHubCore
import SwiftUI

private enum ConversationInspectionMode: String, CaseIterable, Identifiable {
    case day = "当天片段"
    case full = "完整对话"

    var id: Self { self }
}

struct SourceConversationInspector: View {
    @EnvironmentObject private var store: WorkEvolutionHubStore
    let dateKey: String?

    @State private var mode: ConversationInspectionMode = .day
    @State private var fullConversation: [PreparedMessage] = []
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let sessionID = store.selectedSourceSessionId {
                inspector(sessionID: sessionID)
            } else {
                ContentUnavailableView(
                    "选择来源会话",
                    systemImage: "text.bubble",
                    description: Text("选择一个来源会话查看当天片段或完整对话")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
        .task(id: store.selectedSourceSessionId) {
            guard let sessionID = store.selectedSourceSessionId else {
                fullConversation = []
                loadError = nil
                isLoading = false
                return
            }
            await loadCanonicalConversation(sessionID: sessionID)
        }
    }

    private func inspector(sessionID: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(session?.title ?? "来源会话")
                    .font(.headline)
                Text(sessionID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Picker("检查范围", selection: $mode) {
                    ForEach(ConversationInspectionMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(12)

            Divider()

            Group {
                switch mode {
                case .day:
                    dayMessages
                case .full:
                    fullMessages
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var dayMessages: some View {
        Group {
            if isLoading {
                ProgressView("读取当天原始正文…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView(
                    "无法读取当天原始正文",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
                .textSelection(.enabled)
            } else if dateKey != nil, let slice = selectedDaySlice {
                let references = slice.messageReferences.sorted(by: messageReferenceOrdering)
                if references.isEmpty {
                    ContentUnavailableView(
                        "当天没有消息片段",
                        systemImage: "text.bubble.fill",
                        description: Text("来源仍在覆盖清单中，可切换到完整对话核对。")
                    )
                } else {
                    messageScroll {
                        ForEach(references) { reference in
                            if let message = canonicalMessage(matching: reference) {
                                ConversationMessageCard(
                                    role: message.reference.role,
                                    createdAt: message.reference.createdAt,
                                    text: message.text,
                                    sourceFile: message.reference.sourceFile,
                                    sourceLine: message.reference.sourceLine
                                )
                            } else {
                                ConversationMessageCard(
                                    role: reference.role,
                                    createdAt: reference.createdAt,
                                    text: "无法在 canonical 完整会话中匹配这条当天消息。消息 ID：\(reference.id)",
                                    sourceFile: reference.sourceFile,
                                    sourceLine: reference.sourceLine,
                                    warning: true
                                )
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "所选日期没有这个来源片段",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(dateKey == nil ? "先选择日期。" : "可切换到完整对话继续核对。")
                )
            }
        }
    }

    private var fullMessages: some View {
        Group {
            if isLoading {
                ProgressView("读取完整会话…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView(
                    "无法读取完整会话",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
                .textSelection(.enabled)
            } else if fullConversation.isEmpty {
                ContentUnavailableView(
                    "完整会话没有消息",
                    systemImage: "bubble.left.and.exclamationmark.bubble.right"
                )
            } else {
                messageScroll {
                    ForEach(fullConversation.sorted(by: preparedMessageOrdering)) { message in
                        ConversationMessageCard(
                            role: message.reference.role,
                            createdAt: message.reference.createdAt,
                            text: message.text,
                            sourceFile: message.reference.sourceFile,
                            sourceLine: message.reference.sourceLine
                        )
                    }
                }
            }
        }
    }

    private var session: SourceSessionRecord? {
        guard let id = store.selectedSourceSessionId else { return nil }
        return store.snapshot.sourceSessions.first { $0.id == id }
    }

    private var selectedDaySlice: DailySessionSlice? {
        guard let dateKey, let sessionID = store.selectedSourceSessionId else { return nil }
        return store.snapshot.days
            .first { $0.date == dateKey }?
            .sourceSlices
            .first { $0.sessionId == sessionID }
    }

    @MainActor
    private func loadCanonicalConversation(sessionID: String) async {
        isLoading = true
        guard let sourceSession = store.snapshot.sourceSessions.first(where: { $0.id == sessionID }) else {
            fullConversation = []
            loadError = WorkEvolutionHubStoreError.sourceSessionNotFound(sessionID).localizedDescription
            isLoading = false
            return
        }

        let result = await Task.detached(priority: .userInitiated) {
            do {
                return ConversationLoadResult.success(
                    try ArchiveEvidenceReader().conversation(session: sourceSession)
                )
            } catch {
                return ConversationLoadResult.failure(
                    "\(error.localizedDescription)\n来源：\(sourceSession.canonicalEventsPath)"
                )
            }
        }.value

        guard store.selectedSourceSessionId == sessionID else { return }
        switch result {
        case .success(let messages):
            fullConversation = messages
            loadError = nil
        case .failure(let message):
            fullConversation = []
            loadError = message
        }
        isLoading = false
    }

    private func canonicalMessage(matching reference: MessageReference) -> PreparedMessage? {
        if let exact = fullConversation.first(where: { $0.reference.id == reference.id }) {
            return exact
        }

        if !reference.eventId.isEmpty {
            let eventMatches = fullConversation.filter {
                $0.reference.source == reference.source
                    && $0.reference.threadId == reference.threadId
                    && $0.reference.eventId == reference.eventId
            }
            if eventMatches.count == 1 { return eventMatches[0] }
        }

        if !reference.contentHash.isEmpty {
            let hashMatches = fullConversation.filter {
                $0.reference.source == reference.source
                    && $0.reference.threadId == reference.threadId
                    && $0.reference.contentHash == reference.contentHash
                    && $0.reference.createdAt == reference.createdAt
            }
            if hashMatches.count == 1 { return hashMatches[0] }
        }
        return nil
    }

    private func messageScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func messageReferenceOrdering(_ lhs: MessageReference, _ rhs: MessageReference) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        if lhs.sourceLine != rhs.sourceLine { return lhs.sourceLine < rhs.sourceLine }
        return lhs.id < rhs.id
    }

    private func preparedMessageOrdering(_ lhs: PreparedMessage, _ rhs: PreparedMessage) -> Bool {
        messageReferenceOrdering(lhs.reference, rhs.reference)
    }
}

private struct ConversationMessageCard: View {
    let role: ContextMessageRole
    let createdAt: Date
    let text: String
    let sourceFile: String
    let sourceLine: Int
    var warning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(roleLabel(role))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(roleColor(role).opacity(0.12), in: Capsule())
                Spacer()
                Text(EvolutionUIDate.timestamp(createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(text.isEmpty ? "（空消息）" : text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(warning ? Color.red : Color.primary)
                .textSelection(.enabled)
            Text(sourceLocation)
                .font(.caption2.monospaced())
                .foregroundStyle(sourceFile.isEmpty ? .red : .secondary)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(warning ? Color.red.opacity(0.5) : Color.secondary.opacity(0.12)))
    }

    private var sourceLocation: String {
        sourceFile.isEmpty ? "来源路径缺失（行 \(sourceLine)）" : "\(sourceFile):\(sourceLine)"
    }
}

private enum ConversationLoadResult: Sendable {
    case success([PreparedMessage])
    case failure(String)
}

private func roleLabel(_ role: ContextMessageRole) -> String {
    switch role {
    case .user: return "用户"
    case .assistant: return "AI"
    case .system: return "系统"
    case .other: return "其他"
    }
}

private func roleColor(_ role: ContextMessageRole) -> Color {
    switch role {
    case .user: return .blue
    case .assistant: return .green
    case .system: return .orange
    case .other: return .secondary
    }
}
