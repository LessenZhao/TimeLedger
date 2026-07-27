import EvolutionCore
import Foundation

public struct ChatStudyAssetRef: Identifiable, Sendable, Hashable {
    public var assetID: String
    public var segmentID: String
    public var topicID: String?
    public var conversationID: String?
    public var kind: ChatStudyAssetKind
    public var subtype: String
    public var uses: Set<ChatStudyAssetUse>
    public var title: String
    public var isHighlighted: Bool

    public var id: String { assetID }

    public init(
        assetID: String,
        segmentID: String,
        topicID: String?,
        conversationID: String?,
        kind: ChatStudyAssetKind,
        subtype: String,
        uses: Set<ChatStudyAssetUse>,
        title: String,
        isHighlighted: Bool
    ) {
        self.assetID = assetID
        self.segmentID = segmentID
        self.topicID = topicID
        self.conversationID = conversationID
        self.kind = kind
        self.subtype = subtype
        self.uses = uses
        self.title = title
        self.isHighlighted = isHighlighted
    }
}

public struct ChatConversationKindProjection: Identifiable, Sendable, Hashable {
    public var kind: ChatStudyAssetKind
    public var assets: [ChatStudyAssetRef]

    public var id: String { kind.rawValue }

    public init(kind: ChatStudyAssetKind, assets: [ChatStudyAssetRef]) {
        self.kind = kind
        self.assets = assets
    }
}

public enum ChatConversationProjectionMode: String, Sendable, Hashable, CaseIterable {
    case conversation
    case topic
    case kind
}

public enum ChatStudyAssetKindLabel {
    public static func title(for kind: ChatStudyAssetKind) -> String {
        switch kind {
        case .finishedWork: return "完整成品"
        case .expressionModule: return "表达模块"
        case .sourceMaterial: return "素材证据"
        case .methodStrategy: return "方法策略"
        case .viewpointKnowledge: return "观点知识"
        }
    }
}

public enum ChatStudyAssetUseLabel {
    public static func title(for use: ChatStudyAssetUse) -> String {
        switch use {
        case .memorize: return "待背诵"
        case .imitate: return "可仿写"
        case .quote: return "可引用"
        case .practice: return "待实践"
        case .review: return "重点复习"
        }
    }
}

public enum ChatStudyAssetPresentation {
    public static func refs(
        from document: ChatConversationLedgerDocument
    ) -> [ChatStudyAssetRef] {
        let segmentsByID = Dictionary(uniqueKeysWithValues: document.segments.map { ($0.id, $0) })
        return document.assets.map { asset in
            let segment = segmentsByID[asset.segmentId]
            return ChatStudyAssetRef(
                assetID: asset.id,
                segmentID: asset.segmentId,
                topicID: segment?.topicId,
                conversationID: segment?.conversationId,
                kind: asset.kind,
                subtype: asset.subtype,
                uses: asset.uses,
                title: asset.title,
                isHighlighted: asset.isHighlighted
            )
        }
    }

    public static func kindProjections(
        from document: ChatConversationLedgerDocument
    ) -> [ChatConversationKindProjection] {
        let refs = refs(from: document)
        return ChatStudyAssetKind.allCases.compactMap { kind in
            let assets = refs.filter { $0.kind == kind }
            guard !assets.isEmpty else { return nil }
            return ChatConversationKindProjection(kind: kind, assets: assets)
        }
    }
}
