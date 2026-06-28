import XCTest
@testable import DeepSeekContext

final class ConversationManagerTests: XCTestCase {
    private var dbPath: String = ""

    override func setUp() async throws {
        try await super.setUp()
        dbPath = makeTestDatabasePath()
        await DatabaseManager.shared.close()
        try await DatabaseManager.shared.open(databasePath: dbPath)
    }

    override func tearDown() async throws {
        await DatabaseManager.shared.close()
        cleanupTestDatabase(path: dbPath)
        try await super.tearDown()
    }

    func testCreateConversation() async throws {
        let conversation = try await ConversationManager.shared.createConversation(title: "New")
        XCTAssertEqual(conversation.title, "New")
        let fetched = try await ConversationDAO.shared.fetch(byId: conversation.id)
        XCTAssertNotNil(fetched)
    }

    func testSoftLimit() async throws {
        for i in 0..<50 {
            _ = try await ConversationManager.shared.createConversation(title: "Conv \(i)")
        }
        let atLimit = try await ConversationManager.shared.isAtSoftLimit()
        XCTAssertTrue(atLimit)
    }

    func testArchiveAndDeleteConversation() async throws {
        let conversation = try await ConversationManager.shared.createConversation(title: "To archive")
        try await ConversationManager.shared.archiveConversation(id: conversation.id)
        let active = try await ConversationManager.shared.activeConversationCount()
        XCTAssertEqual(active, 0)
        try await ConversationManager.shared.deleteConversation(id: conversation.id)
        let fetched = try await ConversationDAO.shared.fetch(byId: conversation.id)
        XCTAssertNil(fetched)
    }

    func testDeleteConversationWithChildFails() async throws {
        let parent = try await ConversationManager.shared.createConversation(title: "Parent")
        let child = try await ConversationManager.shared.createChildConversation(title: "Child", parentId: parent.id)
        XCTAssertNotEqual(parent.id, child.id)
        do {
            try await ConversationManager.shared.deleteConversation(id: parent.id)
            XCTFail("Expected delete to fail")
        } catch {
            // Expected
        }
    }

    func testChildInheritsMarksAndCounter() async throws {
        let parent = try await ConversationManager.shared.createConversation(title: "Parent")
        _ = try await ContextEngine.shared.createMark(
            type: .complex, lev: 2, content: "Inherited rule",
            tags: ["rule"], conversationId: parent.id, messageIndex: 1, sequence: 1, createdCounter: 3
        )
        try await ConversationDAO.shared.increment(for: parent.id)
        try await ConversationDAO.shared.increment(for: parent.id)

        let child = try await ConversationManager.shared.createChildConversation(title: "Child", parentId: parent.id)
        let childMarks = try await ContextMarkDAO.shared.fetch(byConversationId: child.id)
        XCTAssertEqual(childMarks.count, 1)
        XCTAssertEqual(childMarks.first?.content, "Inherited rule")
        let childTags = try await TagDAO.shared.fetchTags(for: childMarks.first?.id ?? 0)
        XCTAssertEqual(childTags, ["rule"])
        let childCount = try await ConversationDAO.shared.getCount(for: child.id)
        XCTAssertEqual(childCount, 2)
    }

    func testParentCanBeArchivedWithChild() async throws {
        let parent = try await ConversationManager.shared.createConversation(title: "Parent")
        _ = try await ConversationManager.shared.createChildConversation(title: "Child", parentId: parent.id)
        try await ConversationManager.shared.archiveConversation(id: parent.id)
        let archived = try await ConversationDAO.shared.fetch(byId: parent.id)
        XCTAssertFalse(archived?.isActive ?? true)
    }
}
