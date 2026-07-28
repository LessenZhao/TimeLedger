import Foundation

public struct ChatStudyAssetMaterializer: Sendable {
    public init() {}

    public func materialize(
        _ candidate: ChatConversationProposalAsset,
        task: ChatConversationProcessingTask,
        createdAt: String,
        existingAsset: ChatStudyAsset? = nil
    ) throws -> ChatStudyAssetVersion {
        if let replacesID = candidate.replacesAssetID {
            guard let existingAsset, existingAsset.id == replacesID else {
                throw ChatConversationLedgerError.missingAsset(replacesID)
            }
            if existingAsset.isUserLocked {
                throw ChatConversationLedgerError.lockedAsset(replacesID)
            }
        }

        let textSnapshot: String
        let sourceMessages: [ChatConversationMessageReference]
        let sourceSpans: [ChatConversationSourceSpan]

        switch candidate.preservation {
        case .verbatim:
            if candidate.draftText != nil {
                throw ChatConversationLedgerError.invalidAssetMaterialization(
                    "verbatim asset must not contain draftText"
                )
            }
            if !candidate.sourceSpans.isEmpty {
                (textSnapshot, sourceMessages, sourceSpans) = try materializeUserSelection(
                    candidate,
                    task: task
                )
            } else {
                (textSnapshot, sourceMessages, sourceSpans) = try materializeVerbatimBlocks(
                    candidate,
                    task: task
                )
            }
        case .distilled:
            guard let draftText = candidate.draftText, !draftText.isEmpty else {
                throw ChatConversationLedgerError.invalidAssetMaterialization(
                    "distilled asset requires non-empty draftText"
                )
            }
            textSnapshot = draftText
            if !candidate.sourceSpans.isEmpty {
                let selection = try materializeUserSelection(candidate, task: task)
                sourceMessages = selection.1
                sourceSpans = selection.2
            } else {
                let blocks = try resolveBlocks(candidate.sourceBlockIDs, task: task, requireAssistant: false)
                guard !blocks.isEmpty else {
                    throw ChatConversationLedgerError.invalidAssetMaterialization(
                        "asset source blocks must not be empty"
                    )
                }
                sourceMessages = uniqueMessages(from: blocks)
                sourceSpans = blocks.map { block in
                    ChatConversationSourceSpan(
                        message: block.message.reference,
                        contentHash: block.message.contentHash,
                        locationUTF16: block.block.locationUTF16,
                        lengthUTF16: block.block.lengthUTF16,
                        textHash: block.block.textHash
                    )
                }
            }
        }

        let versionIndex = (existingAsset?.versions.count ?? 0) + 1
        let assetID = existingAsset?.id ?? candidate.id
        let supersedes = existingAsset?.currentVersionId

        return ChatStudyAssetVersion(
            id: "\(assetID)-v\(versionIndex)",
            textSnapshot: textSnapshot,
            textHash: ContentHasher.hash(textSnapshot),
            preservation: candidate.preservation,
            origin: candidate.origin,
            sourceMessages: sourceMessages,
            sourceSpans: sourceSpans,
            supersedesVersionId: supersedes,
            createdAt: createdAt
        )
    }

    private func materializeVerbatimBlocks(
        _ candidate: ChatConversationProposalAsset,
        task: ChatConversationProcessingTask
    ) throws -> (String, [ChatConversationMessageReference], [ChatConversationSourceSpan]) {
        let blocks = try resolveBlocks(candidate.sourceBlockIDs, task: task, requireAssistant: true)
        guard !blocks.isEmpty else {
            throw ChatConversationLedgerError.invalidAssetMaterialization(
                "asset source blocks must not be empty"
            )
        }
        let messageIDs = Set(blocks.map { "\($0.message.conversationId)|\($0.message.messageId)" })
        guard messageIDs.count == 1 else {
            throw ChatConversationLedgerError.invalidAssetMaterialization(
                "verbatim blocks must come from one assistant message"
            )
        }
        guard blocks.allSatisfy({ $0.message.role == .assistant }) else {
            throw ChatConversationLedgerError.invalidAssetMaterialization(
                "verbatim blocks must come from assistant messages"
            )
        }
        let sorted = blocks.sorted { $0.block.locationUTF16 < $1.block.locationUTF16 }
        guard sorted.map(\.block.id) == blocks.map(\.block.id) else {
            throw ChatConversationLedgerError.invalidAssetMaterialization(
                "verbatim blocks must be in ascending UTF-16 order"
            )
        }
        for index in 1..<sorted.count {
            let previous = sorted[index - 1].block
            let current = sorted[index].block
            guard previous.locationUTF16 + previous.lengthUTF16 == current.locationUTF16 else {
                throw ChatConversationLedgerError.invalidAssetMaterialization(
                    "verbatim blocks must be contiguous"
                )
            }
        }
        let uniqueIDs = Set(blocks.map(\.block.id))
        guard uniqueIDs.count == blocks.count else {
            throw ChatConversationLedgerError.invalidAssetMaterialization(
                "verbatim blocks must not contain duplicates"
            )
        }

        // Slice the original message content by the contiguous UTF-16 span.
        // Do not re-join per-line block.text values: that path can drift from the
        // source if block boundaries or trailing newlines ever diverge.
        let message = sorted[0].message
        let start = sorted[0].block.locationUTF16
        let end = sorted[sorted.count - 1].block.locationUTF16
            + sorted[sorted.count - 1].block.lengthUTF16
        let ns = message.content as NSString
        guard start >= 0, end >= start, end <= ns.length else {
            throw ChatConversationLedgerError.invalidAssetMaterialization(
                "verbatim block range out of bounds"
            )
        }
        let textSnapshot = ns.substring(with: NSRange(location: start, length: end - start))
        // Guard: reconstructed text must match concatenation of selected block texts.
        let joinedBlocks = sorted.map(\.block.text).joined()
        guard textSnapshot == joinedBlocks else {
            throw ChatConversationLedgerError.invalidAssetMaterialization(
                "verbatim block texts do not match source message slice"
            )
        }

        let sourceMessages = uniqueMessages(from: blocks)
        let sourceSpans = blocks.map { block in
            ChatConversationSourceSpan(
                message: block.message.reference,
                contentHash: block.message.contentHash,
                locationUTF16: block.block.locationUTF16,
                lengthUTF16: block.block.lengthUTF16,
                textHash: block.block.textHash
            )
        }
        return (textSnapshot, sourceMessages, sourceSpans)
    }

    private func materializeUserSelection(
        _ candidate: ChatConversationProposalAsset,
        task: ChatConversationProcessingTask
    ) throws -> (String, [ChatConversationMessageReference], [ChatConversationSourceSpan]) {
        guard !candidate.sourceSpans.isEmpty else {
            throw ChatConversationLedgerError.invalidAssetMaterialization(
                "user selection requires sourceSpans"
            )
        }
        var texts: [String] = []
        var messages: [ChatConversationMessageReference] = []
        var spans: [ChatConversationSourceSpan] = []
        var resolved: [(message: ChatConversationTaskMessage, span: ChatConversationSourceSpan, text: String)] = []
        for span in candidate.sourceSpans {
            guard let message = task.inputMessages.first(where: {
                $0.conversationId == span.message.conversationId &&
                $0.messageId == span.message.messageId
            }) else {
                throw ChatConversationLedgerError.invalidAssetMaterialization(
                    "source message missing for selection"
                )
            }
            guard message.contentHash == span.contentHash else {
                throw ChatConversationLedgerError.invalidAssetMaterialization(
                    "source contentHash mismatch"
                )
            }
            let ns = message.content as NSString
            guard span.locationUTF16 >= 0,
                  span.lengthUTF16 > 0,
                  span.locationUTF16 + span.lengthUTF16 <= ns.length else {
                throw ChatConversationLedgerError.invalidAssetMaterialization(
                    "source span out of bounds"
                )
            }
            let text = ns.substring(with: NSRange(location: span.locationUTF16, length: span.lengthUTF16))
            guard ContentHasher.hash(text) == span.textHash else {
                throw ChatConversationLedgerError.invalidAssetMaterialization(
                    "source span textHash mismatch"
                )
            }
            resolved.append((message, span, text))
            texts.append(text)
            if !messages.contains(span.message) {
                messages.append(span.message)
            }
            spans.append(span)
        }

        // Contiguous spans on one message → exact source slice (keeps newlines/lists).
        if let first = resolved.first,
           resolved.allSatisfy({
               $0.message.conversationId == first.message.conversationId &&
               $0.message.messageId == first.message.messageId
           }) {
            let ordered = resolved.sorted { $0.span.locationUTF16 < $1.span.locationUTF16 }
            var contiguous = true
            for index in 1..<ordered.count {
                let previous = ordered[index - 1].span
                let current = ordered[index].span
                if previous.locationUTF16 + previous.lengthUTF16 != current.locationUTF16 {
                    contiguous = false
                    break
                }
            }
            if contiguous {
                let start = ordered[0].span.locationUTF16
                let end = ordered[ordered.count - 1].span.locationUTF16
                    + ordered[ordered.count - 1].span.lengthUTF16
                let ns = first.message.content as NSString
                let sliced = ns.substring(with: NSRange(location: start, length: end - start))
                return (sliced, messages, spans)
            }
        }

        // Non-contiguous multi-span: keep each exact slice and separate with a blank
        // line so list/paragraph boundaries are not glued into one run-on line.
        return (texts.joined(separator: "\n\n"), messages, spans)
    }

    private struct ResolvedBlock {
        var message: ChatConversationTaskMessage
        var block: ChatConversationTaskSourceBlock
    }

    private func resolveBlocks(
        _ blockIDs: [String],
        task: ChatConversationProcessingTask,
        requireAssistant: Bool
    ) throws -> [ResolvedBlock] {
        var index: [String: ResolvedBlock] = [:]
        for message in task.inputMessages where !message.contextOnly {
            if requireAssistant && message.role != .assistant { continue }
            for block in message.sourceBlocks {
                index[block.id] = ResolvedBlock(message: message, block: block)
            }
        }
        return try blockIDs.map { id in
            guard let resolved = index[id] else {
                throw ChatConversationLedgerError.invalidAssetMaterialization(
                    "source block not found: \(id)"
                )
            }
            return resolved
        }
    }

    private func uniqueMessages(from blocks: [ResolvedBlock]) -> [ChatConversationMessageReference] {
        var seen = Set<ChatConversationMessageReference>()
        var result: [ChatConversationMessageReference] = []
        for block in blocks {
            let reference = block.message.reference
            if seen.insert(reference).inserted {
                result.append(reference)
            }
        }
        return result
    }
}
