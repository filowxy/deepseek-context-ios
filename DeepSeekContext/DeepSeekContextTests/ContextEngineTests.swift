import XCTest
@testable import DeepSeekContext

final class ContextEngineTests: XCTestCase {
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

    func testCreateMark() async throws {
        let conversation = try await ConversationManager.shared.createConversation(title: "Test")
        let mark = try await ContextEngine.shared.createMark(
            type: .userask,
            lev: 1,
            content: "Important requirement",
            tags: ["cave"],
            conversationId: conversation.id,
            messageIndex: 5,
            sequence: 1,
            createdCounter: 5
        )
        XCTAssertEqual(mark.markId, 1)
        XCTAssertEqual(mark.idemKey, "\(conversation.id)_5_userask_1")
        let tags = try await TagDAO.shared.fetchTags(for: mark.id)
        XCTAssertEqual(tags, ["cave"])
    }

    func testInvalidLevelRejected() async throws {
        let conversation = try await ConversationManager.shared.createConversation(title: "Test")
        do {
            _ = try await ContextEngine.shared.createMark(
                type: .complex,
                lev: 5,
                content: "Bad",
                conversationId: conversation.id,
                messageIndex: 1,
                sequence: 1,
                createdCounter: 1
            )
            XCTFail("Expected invalid level error")
        } catch ContextEngineError.invalidLevel {
            // Expected
        }
    }

    func testEmptyContentRejected() async throws {
        let conversation = try await ConversationManager.shared.createConversation(title: "Test")
        do {
            _ = try await ContextEngine.shared.createMark(
                type: .complex,
                lev: 1,
                content: "",
                conversationId: conversation.id,
                messageIndex: 1,
                sequence: 1,
                createdCounter: 1
            )
            XCTFail("Expected empty content error")
        } catch ContextEngineError.emptyContent {
            // Expected
        }
    }

    func testUpsertByIdemKeyUpdatesContent() async throws {
        let conversation = try await ConversationManager.shared.createConversation(title: "Test")
        _ = try await ContextEngine.shared.createMark(
            type: .complex,
            lev: 1,
            content: "Original",
            conversationId: conversation.id,
            messageIndex: 2,
            sequence: 1,
            createdCounter: 2
        )
        let updated = try await ContextEngine.shared.createMark(
            type: .complex,
            lev: 2,
            content: "Updated",
            conversationId: conversation.id,
            messageIndex: 2,
            sequence: 1,
            createdCounter: 2
        )
        XCTAssertEqual(updated.content, "Updated")
        XCTAssertEqual(updated.lev, 1) // lev should stay from original per document
    }

    func testDeleteAndRecoverMark() async throws {
        let conversation = try await ConversationManager.shared.createConversation(title: "Test")
        let mark = try await ContextEngine.shared.createMark(
            type: .userask,
            lev: 0,
            content: "To delete",
            conversationId: conversation.id,
            messageIndex: 1,
            sequence: 1,
            createdCounter: 1
        )
        try await ContextEngine.shared.deleteMark(id: mark.id)
        let deleted = try await ContextMarkDAO.shared.fetch(byId: mark.id)
        XCTAssertTrue(deleted?.deleted ?? false)
        try await ContextEngine.shared.recoverMark(id: mark.id)
        let recovered = try await ContextMarkDAO.shared.fetch(byId: mark.id)
        XCTAssertFalse(recovered?.deleted ?? true)
    }
}
