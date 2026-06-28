import XCTest
@testable import DeepSeekContext

final class ContextMarkDAOTests: XCTestCase {
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

    private func makeConversation(id: String) async throws {
        try await ConversationDAO.shared.insert(Conversation(id: id, title: "Test"))
    }

    private func sampleMark(conversationId: String, markId: Int64, idemKey: String) -> ContextMark {
        ContextMark(
            id: 0,
            markId: markId,
            conversationId: conversationId,
            lev: 1,
            type: .complex,
            content: "Sample content",
            idemKey: idemKey,
            createdCounter: 1
        )
    }

    func testInsertAndFetch() async throws {
        try await makeConversation(id: "conv1")
        let mark = sampleMark(conversationId: "conv1", markId: 1, idemKey: "conv1_1_complex_1")
        let inserted = try await ContextMarkDAO.shared.upsert(mark)
        XCTAssertGreaterThan(inserted.id, 0)
        let fetched = try await ContextMarkDAO.shared.fetch(byId: inserted.id)
        XCTAssertEqual(fetched?.content, "Sample content")
    }

    func testUpsertUpdatesContentAndRecovers() async throws {
        try await makeConversation(id: "conv1")
        let mark = sampleMark(conversationId: "conv1", markId: 1, idemKey: "conv1_1_complex_1")
        let inserted = try await ContextMarkDAO.shared.upsert(mark)
        try await ContextMarkDAO.shared.softDelete(id: inserted.id)
        let updated = ContextMark(
            id: 0,
            markId: 1,
            conversationId: "conv1",
            lev: 2,
            type: .complex,
            content: "Updated content",
            idemKey: "conv1_1_complex_1",
            createdCounter: 1
        )
        let upserted = try await ContextMarkDAO.shared.upsert(updated)
        XCTAssertEqual(upserted.content, "Updated content")
        XCTAssertFalse(upserted.deleted)
    }

    func testSoftDeleteAndRecover() async throws {
        try await makeConversation(id: "conv1")
        let mark = sampleMark(conversationId: "conv1", markId: 1, idemKey: "conv1_1_complex_1")
        let inserted = try await ContextMarkDAO.shared.upsert(mark)
        try await ContextMarkDAO.shared.softDelete(id: inserted.id)
        let deleted = try await ContextMarkDAO.shared.fetch(byId: inserted.id)
        XCTAssertTrue(deleted?.deleted ?? false)
        try await ContextMarkDAO.shared.recover(id: inserted.id)
        let recovered = try await ContextMarkDAO.shared.fetch(byId: inserted.id)
        XCTAssertFalse(recovered?.deleted ?? true)
    }

    func testNextMarkIdIncrements() async throws {
        try await makeConversation(id: "conv1")
        let first = try await ContextMarkDAO.shared.nextMarkId(for: "conv1")
        XCTAssertEqual(first, 1)
        let mark = sampleMark(conversationId: "conv1", markId: first, idemKey: "conv1_1_complex_1")
        _ = try await ContextMarkDAO.shared.upsert(mark)
        let second = try await ContextMarkDAO.shared.nextMarkId(for: "conv1")
        XCTAssertEqual(second, 2)
    }

    func testNextMarkIdWithParentInherits() async throws {
        try await makeConversation(id: "parent")
        try await makeConversation(id: "child")
        let parentMark = sampleMark(conversationId: "parent", markId: 1, idemKey: "parent_1_complex_1")
        _ = try await ContextMarkDAO.shared.upsert(parentMark)
        let next = try await ContextMarkDAO.shared.nextMarkIdWithParent(for: "child", parentId: "parent")
        XCTAssertEqual(next, 2)
    }

    func testFetchByConversationExcludesDeleted() async throws {
        try await makeConversation(id: "conv1")
        let mark1 = sampleMark(conversationId: "conv1", markId: 1, idemKey: "conv1_1_complex_1")
        let mark2 = sampleMark(conversationId: "conv1", markId: 2, idemKey: "conv1_1_complex_2")
        let inserted1 = try await ContextMarkDAO.shared.upsert(mark1)
        _ = try await ContextMarkDAO.shared.upsert(mark2)
        try await ContextMarkDAO.shared.softDelete(id: inserted1.id)
        let marks = try await ContextMarkDAO.shared.fetch(byConversationId: "conv1")
        XCTAssertEqual(marks.count, 1)
    }
}
