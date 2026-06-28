import XCTest
@testable import DeepSeekContext

final class ReminderEngineTests: XCTestCase {
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

    private func makeMark(lev: Int, lastRemind: Int64? = nil) async throws -> ContextMark {
        let conversation = try await ConversationManager.shared.createConversation(title: "Test")
        return try await ContextEngine.shared.createMark(
            type: .complex,
            lev: lev,
            content: "Remember this",
            conversationId: conversation.id,
            messageIndex: 1,
            sequence: 1,
            createdCounter: 1,
            lastRemindCounter: lastRemind
        )
    }

    func testFirstReminderAtCounterFive() async throws {
        let mark = try await makeMark(lev: 0)
        XCTAssertTrue(ReminderEngine.shared.shouldRemind(mark: mark, currentCount: 5))
        XCTAssertFalse(ReminderEngine.shared.shouldRemind(mark: mark, currentCount: 4))
    }

    func testLevelZeroCycle() async throws {
        let mark = try await makeMark(lev: 0, lastRemind: 5)
        XCTAssertFalse(ReminderEngine.shared.shouldRemind(mark: mark, currentCount: 14))
        XCTAssertTrue(ReminderEngine.shared.shouldRemind(mark: mark, currentCount: 15))
    }

    func testLevelOneCycle() async throws {
        let mark = try await makeMark(lev: 1, lastRemind: 5)
        XCTAssertFalse(ReminderEngine.shared.shouldRemind(mark: mark, currentCount: 24))
        XCTAssertTrue(ReminderEngine.shared.shouldRemind(mark: mark, currentCount: 25))
    }

    func testLevelTwoCycle() async throws {
        let mark = try await makeMark(lev: 2, lastRemind: 5)
        XCTAssertFalse(ReminderEngine.shared.shouldRemind(mark: mark, currentCount: 34))
        XCTAssertTrue(ReminderEngine.shared.shouldRemind(mark: mark, currentCount: 35))
    }

    func testLevelThreeCycle() async throws {
        let mark = try await makeMark(lev: 3, lastRemind: 5)
        XCTAssertFalse(ReminderEngine.shared.shouldRemind(mark: mark, currentCount: 54))
        XCTAssertTrue(ReminderEngine.shared.shouldRemind(mark: mark, currentCount: 55))
    }

    func testMarkRemindedUpdatesCounter() async throws {
        let conversation = try await ConversationManager.shared.createConversation(title: "Test")
        let mark = try await ContextEngine.shared.createMark(
            type: .complex,
            lev: 0,
            content: "Remember",
            conversationId: conversation.id,
            messageIndex: 1,
            sequence: 1,
            createdCounter: 1
        )
        try await ReminderEngine.shared.markReminded(id: mark.id, at: 5)
        let updated = try await ContextMarkDAO.shared.fetch(byId: mark.id)
        XCTAssertEqual(updated?.lastRemindCounter, 5)
    }
}
