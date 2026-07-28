import EvolutionCore
@testable import EvolutionHubCore
import Foundation
import XCTest

final class ChatConversationUserMarksTests: XCTestCase {
    @MainActor
    func testToggleConversationAndTurnStarsPersistAcrossStoreInstances() throws {
        let fixture = try ChatConversationHubFixture()
        try fixture.writeConversation(
            id: "conv-star",
            updatedAt: "2026-07-20T10:00:00Z",
            messages: [fixture.message(id: "u1", content: "Question about selection")]
        )
        try fixture.writeManifest(ids: ["conv-star"])

        let store = ChatConversationHubStore(layout: fixture.layout)
        try store.refresh(archiveRoot: fixture.archiveRoot)

        store.toggleConversationStar(conversationID: "conv-star")
        let turnID = "conv-star:u1"
        store.toggleTurnStar(turnID: turnID)

        XCTAssertTrue(store.isConversationStarred("conv-star"))
        XCTAssertTrue(store.isTurnStarred(turnID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.layout.chatConversationUserMarksFileURL.path))

        let reloaded = ChatConversationHubStore(layout: fixture.layout)
        try reloaded.refresh(archiveRoot: fixture.archiveRoot)
        XCTAssertTrue(reloaded.isConversationStarred("conv-star"))
        XCTAssertTrue(reloaded.isTurnStarred(turnID))

        reloaded.toggleConversationStar(conversationID: "conv-star")
        XCTAssertFalse(reloaded.isConversationStarred("conv-star"))
    }

    @MainActor
    func testDayGroupingPutsStarredConversationsFirstWithinSameDay() throws {
        let fixture = try ChatConversationHubFixture()
        try fixture.writeConversation(
            id: "a-late",
            updatedAt: "2026-07-20T10:00:00Z",
            messages: [fixture.message(id: "a1", content: "Later same day")]
        )
        try fixture.writeConversation(
            id: "b-early-starred",
            updatedAt: "2026-07-20T01:00:00Z",
            messages: [fixture.message(id: "b1", content: "Earlier but starred")]
        )
        try fixture.writeConversation(
            id: "c-other-day",
            updatedAt: "2026-07-19T04:00:00Z",
            messages: [fixture.message(id: "c1", content: "Yesterday")]
        )
        try fixture.writeManifest(ids: ["a-late", "b-early-starred", "c-other-day"])

        let store = ChatConversationHubStore(layout: fixture.layout)
        try store.refresh(archiveRoot: fixture.archiveRoot)
        store.toggleConversationStar(conversationID: "b-early-starred")

        let groups = store.visibleConversationDayGroups
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].conversations.map(\.conversationId), ["b-early-starred", "a-late"])
        XCTAssertEqual(groups[1].conversations.map(\.conversationId), ["c-other-day"])
        XCTAssertGreaterThan(groups[0].dayStart, groups[1].dayStart)
    }

    @MainActor
    func testShowsOnlyStarredFilterHidesUnstarredConversations() throws {
        let fixture = try ChatConversationHubFixture()
        try fixture.writeConversation(
            id: "starred",
            updatedAt: "2026-07-20T10:00:00Z",
            messages: [fixture.message(id: "s1", content: "Star me")]
        )
        try fixture.writeConversation(
            id: "plain",
            updatedAt: "2026-07-20T11:00:00Z",
            messages: [fixture.message(id: "p1", content: "No star")]
        )
        try fixture.writeManifest(ids: ["starred", "plain"])

        let store = ChatConversationHubStore(layout: fixture.layout)
        try store.refresh(archiveRoot: fixture.archiveRoot)
        store.toggleConversationStar(conversationID: "starred")
        store.showsOnlyStarredConversations = true

        XCTAssertEqual(store.visibleConversations.map(\.conversationId), ["starred"])
    }

    func testTurnCatalogPreviewStripsMarkdownAndTruncates() {
        let long = String(repeating: "备考重点 ", count: 20)
        let content = """
        ## 标题

        **\(long)**

        ```swift
        let x = 1
        ```
        """
        let preview = ChatConversationTurnPresentation.preview(from: content, limit: 24)
        XCTAssertFalse(preview.contains("**"))
        XCTAssertFalse(preview.contains("```"))
        XCTAssertTrue(preview.hasSuffix("…"))
        XCTAssertLessThanOrEqual(preview.count, 24)
    }

    func testSourceTurnCatalogFieldsUseUserAndAssistantPreviews() {
        let conversation = ChatConversationArchiveSummary(
            conversationId: "c1",
            title: "t",
            sourceURL: nil,
            createdAt: "2026-07-20T10:00:00Z",
            updatedAt: "2026-07-20T10:00:00Z",
            messages: [
                ChatConversationMessage(id: "u1", role: .user, createdAt: "2026-07-20T10:00:00Z", content: "湖南省直遴选大作文怎么准备？"),
                ChatConversationMessage(id: "a1", role: .assistant, createdAt: "2026-07-20T10:01:00Z", content: "先给结论：稳定命题公式，不是年度热点。"),
            ],
            status: .pending,
            processedMessageCount: 0,
            pendingMessageCount: 2,
            pendingMessageIDs: ["u1", "a1"],
            issue: nil
        )
        let presentation = ChatConversationEvidencePresentation(conversations: [conversation])
        let turns = presentation.turns(for: conversation.messages.map {
            ChatConversationMessageReference(conversationId: "c1", messageId: $0.id)
        })
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].catalogTitle, "湖南省直遴选大作文怎么准备？")
        XCTAssertTrue(turns[0].catalogSubtitle.contains("稳定命题公式"))
    }
}
