import XCTest
@testable import DeepSeekContext

final class SearchDAOTests: XCTestCase {
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

    private func insertMark(conversationId: String, content: String, idemKey: String, tags: [String] = []) async throws -> Int64 {
        try await ConversationDAO.shared.insert(Conversation(id: conversationId, title: "Test"))
        let mark = ContextMark(
            id: 0,
            markId: 1,
            conversationId: conversationId,
            lev: 0,
            type: .userask,
            content: content,
            idemKey: idemKey,
            createdCounter: 1
        )
        let inserted = try await ContextMarkDAO.shared.upsert(mark)
        if !tags.isEmpty {
            try await TagDAO.shared.setTags(for: inserted.id, tags: tags)
        }
        return inserted.id
    }

    func testFullTextSearch() async throws {
        _ = try await insertMark(conversationId: "conv1", content: "TerraBlender cave generation", idemKey: "conv1_1_userask_1")
        _ = try await insertMark(conversationId: "conv2", content: "ForgeGradle build setup", idemKey: "conv2_1_userask_1")
        let results = try await SearchDAO.shared.searchFullText(query: "TerraBlender", limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.content, "TerraBlender cave generation")
    }

    func testFullTextSearchExcludesDeleted() async throws {
        let id = try await insertMark(conversationId: "conv1", content: "TerraBlender cave generation", idemKey: "conv1_1_userask_1")
        try await ContextMarkDAO.shared.softDelete(id: id)
        let results = try await SearchDAO.shared.searchFullText(query: "TerraBlender", limit: 10)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchByTag() async throws {
        _ = try await insertMark(conversationId: "conv1", content: "Some text", idemKey: "conv1_1_userask_1", tags: ["cave"])
        _ = try await insertMark(conversationId: "conv2", content: "Other text", idemKey: "conv2_1_userask_1", tags: ["cave"])
        let results = try await SearchDAO.shared.searchByTag(tag: "cave", limit: 10)
        XCTAssertEqual(results.count, 2)
    }

    func testSearchByTagExcludesDeleted() async throws {
        let id = try await insertMark(conversationId: "conv1", content: "Some text", idemKey: "conv1_1_userask_1", tags: ["cave"])
        try await ContextMarkDAO.shared.softDelete(id: id)
        let results = try await SearchDAO.shared.searchByTag(tag: "cave", limit: 10)
        XCTAssertEqual(results.count, 0)
    }

    func testFullTextScopeConversationIds() async throws {
        _ = try await insertMark(conversationId: "conv1", content: "TerraBlender", idemKey: "conv1_1_userask_1")
        _ = try await insertMark(conversationId: "conv2", content: "TerraBlender", idemKey: "conv2_1_userask_1")
        let results = try await SearchDAO.shared.searchFullText(query: "TerraBlender", limit: 10, scopeConversationIds: ["conv1"])
        XCTAssertEqual(results.count, 1)
    }
}
