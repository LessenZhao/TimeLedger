import Foundation

public struct ChatConversationSourceBlockBuilder: Sendable {
    public init() {}

    public func blocks(
        conversationId: String,
        message: ChatConversationMessage
    ) -> [ChatConversationTaskSourceBlock] {
        let source = message.content as NSString
        guard source.length > 0 else { return [] }

        var result: [ChatConversationTaskSourceBlock] = []
        var cursor = 0
        var index = 0

        while cursor < source.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            source.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: cursor, length: 0)
            )
            let range = NSRange(location: lineStart, length: lineEnd - lineStart)
            let text = source.substring(with: range)
            result.append(ChatConversationTaskSourceBlock(
                id: "\(conversationId):\(message.id):line-\(index)",
                locationUTF16: range.location,
                lengthUTF16: range.length,
                text: text,
                textHash: ContentHasher.hash(text)
            ))
            cursor = lineEnd
            index += 1
        }

        return result
    }
}
