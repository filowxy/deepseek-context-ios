import XCTest
@testable import DeepSeekContext

final class RecallEngineTests: XCTestCase {
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

    func testRecallCurrentScope() async throws {
        let conv1 = try await ConversationManager.shared.createConversation(title: "A")
        let conv2 = try await ConversationManager.shared.createConversation(title: "B")
        _ = try await ContextEngine.shared.createMark(
            type: .userask, lev: 0, content: "TerraBlender",
            tags: [], conversationId: conv1.id, messageIndex: 1, sequence: 1, createdCounter: 1
        )
        _ = try await ContextEngine.shared.createMark(
            type: .userask, lev: 0, content: "TerraBlender",
            tags: [], conversationId: conv2.id, messageIndex: 1, sequence: 1, createdCounter: 1
        )
        let result = try await RecallEngine.shared.recall(
            query: "TerraBlender", scope: .current, conversationId: conv1.id, limit: 10
        )
        XCTAssertEqual(result.items.count, 1)
        XCTAssertTrue(result.searchId.hasPrefix("recall-"))
    }

    func testRecallTruncation() async throws {
        let conv = try await ConversationManager.shared.createConversation(title: "Test")
        for i in 0..<10 {
            _ = try await ContextEngine.shared.createMark(
                type: .userask, lev: 0, content: "shared keyword \(i)",
                tags: [], conversationId: conv.id, messageIndex: i + 1, sequence: 1, createdCounter: Int64(i + 1)
            )
        }
        let result = try await RecallEngine.shared.recall(
            query: "shared", scope: .current, conversationId: conv.id, limit: 5
        )
        XCTAssertEqual(result.items.count, 5)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.total, 10)
    }

    func testTagMatchingAppendsResults() async throws {
        let conv = try await ConversationManager.shared.createConversation(title: "Test")
        _ = try await ContextEngine.shared.createMark(
            type: .userask, lev: 0, content: "Alpha content",
            tags: ["beta"], conversationId: conv.id, messageIndex: 1, sequence: 1, createdCounter: 1
        )
        let result = try await RecallEngine.shared.recall(
            query: "beta", scope: .current, conversationId: conv.id, limit: 10
        )
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.tags, ["beta"])
    }

    func testSearchIdCachesResult() async throws {
        let conv = try await ConversationManager.shared.createConversation(title: "Test")
        _ = try await ContextEngine.shared.createMark(
            type: .userask, lev: 0, content: "Cache me",
            tags: [], conversationId: conv.id, messageIndex: 1, sequence: 1, createdCounter: 1
        )
        let result = try await RecallEngine.shared.recall(
            query: "Cache", scope: .current, conversationId: conv.id, limit: 10
        )
        let cached = await RecallEngine.shared.result(bySearchId: result.searchId)
        XCTAssertEqual(cached?.items.count, result.items.count)
    }
}
