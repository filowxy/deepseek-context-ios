import XCTest
@testable import DeepSeekContext

final class ConversationDAOTests: XCTestCase {
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

    func testInsertAndFetch() async throws {
        let conversation = Conversation(id: "conv1", title: "Test")
        try await ConversationDAO.shared.insert(conversation)
        let fetched = try await ConversationDAO.shared.fetch(byId: "conv1")
        XCTAssertEqual(fetched?.id, "conv1")
        XCTAssertEqual(fetched?.title, "Test")
        XCTAssertTrue(fetched?.isActive ?? false)
    }

    func testUpdate() async throws {
        let conversation = Conversation(id: "conv1", title: "Old")
        try await ConversationDAO.shared.insert(conversation)
        var updated = conversation
        updated.title = "New"
        try await ConversationDAO.shared.update(updated)
        let fetched = try await ConversationDAO.shared.fetch(byId: "conv1")
        XCTAssertEqual(fetched?.title, "New")
    }

    func testArchive() async throws {
        let conversation = Conversation(id: "conv1", title: "Test")
        try await ConversationDAO.shared.insert(conversation)
        try await ConversationDAO.shared.archive(id: "conv1")
        let active = try await ConversationDAO.shared.fetchActive()
        XCTAssertTrue(active.isEmpty)
        let all = try await ConversationDAO.shared.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertFalse(all.first?.isActive ?? true)
    }

    func testDeleteWithChildrenFails() async throws {
        let parent = Conversation(id: "parent", title: "Parent")
        let child = Conversation(id: "child", title: "Child")
        try await ConversationDAO.shared.insert(parent)
        try await ConversationDAO.shared.insert(child)
        try await ConversationDAO.shared.linkChild(childId: "child", parentId: "parent")
        do {
            try await ConversationDAO.shared.delete(id: "parent")
            XCTFail("Expected delete to fail")
        } catch {
            // Expected
        }
    }

    func testCountActiveExcludesParents() async throws {
        let parent = Conversation(id: "parent", title: "Parent")
        let child = Conversation(id: "child", title: "Child")
        let standalone = Conversation(id: "standalone", title: "Standalone")
        try await ConversationDAO.shared.insert(parent)
        try await ConversationDAO.shared.insert(child)
        try await ConversationDAO.shared.insert(standalone)
        try await ConversationDAO.shared.linkChild(childId: "child", parentId: "parent")
        let count = try await ConversationDAO.shared.countActive()
        XCTAssertEqual(count, 1)
    }

    func testCounterIncrementAndInheritance() async throws {
        let parent = Conversation(id: "parent", title: "Parent")
        let child = Conversation(id: "child", title: "Child")
        try await ConversationDAO.shared.insert(parent)
        try await ConversationDAO.shared.insert(child)
        let first = try await ConversationDAO.shared.increment(for: "parent")
        XCTAssertEqual(first, 1)
        let second = try await ConversationDAO.shared.increment(for: "parent")
        XCTAssertEqual(second, 2)
        try await ConversationDAO.shared.initializeCounterFromParent(childId: "child", parentId: "parent")
        let childCount = try await ConversationDAO.shared.getCount(for: "child")
        XCTAssertEqual(childCount, 2)
    }

    func testManualCountCorrection() async throws {
        let conversation = Conversation(id: "conv1", title: "Test")
        try await ConversationDAO.shared.insert(conversation)
        try await ConversationDAO.shared.setCount(for: "conv1", count: 42)
        let count = try await ConversationDAO.shared.getCount(for: "conv1")
        XCTAssertEqual(count, 42)
    }
}
