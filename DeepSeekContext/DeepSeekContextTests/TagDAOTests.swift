import XCTest
@testable import DeepSeekContext

final class TagDAOTests: XCTestCase {
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

    private func insertMark(conversationId: String, idemKey: String) async throws -> Int64 {
        try await ConversationDAO.shared.insert(Conversation(id: conversationId, title: "Test"))
        let mark = ContextMark(
            id: 0,
            markId: 1,
            conversationId: conversationId,
            lev: 0,
            type: .userask,
            content: "Tagged",
            idemKey: idemKey,
            createdCounter: 1
        )
        return try await ContextMarkDAO.shared.upsert(mark).id
    }

    func testSetAndFetchTags() async throws {
        let markId = try await insertMark(conversationId: "conv1", idemKey: "conv1_1_userask_1")
        try await TagDAO.shared.setTags(for: markId, tags: ["cave", "terrain"])
        let tags = try await TagDAO.shared.fetchTags(for: markId)
        XCTAssertEqual(tags.sorted(), ["cave", "terrain"])
    }

    func testSetTagsReplacesExisting() async throws {
        let markId = try await insertMark(conversationId: "conv1", idemKey: "conv1_1_userask_1")
        try await TagDAO.shared.setTags(for: markId, tags: ["old"])
        try await TagDAO.shared.setTags(for: markId, tags: ["new"])
        let tags = try await TagDAO.shared.fetchTags(for: markId)
        XCTAssertEqual(tags, ["new"])
    }

    func testFetchMarkIdsByTag() async throws {
        let mark1 = try await insertMark(conversationId: "conv1", idemKey: "conv1_1_userask_1")
        let mark2 = try await insertMark(conversationId: "conv2", idemKey: "conv2_1_userask_1")
        try await TagDAO.shared.setTags(for: mark1, tags: ["shared"])
        try await TagDAO.shared.setTags(for: mark2, tags: ["shared"])
        let ids = try await TagDAO.shared.fetchMarkIds(byTag: "shared")
        XCTAssertEqual(ids.sorted(), [mark1, mark2].sorted())
    }
}
