import XCTest
@testable import DeepSeekContext

final class GlobalContextDAOTests: XCTestCase {
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

    func testInsertAndFetchActive() async throws {
        let context = try await GlobalContextDAO.shared.insert(content: "World height limit 380")
        let active = try await GlobalContextDAO.shared.fetchActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.content, "World height limit 380")
        XCTAssertEqual(active.first?.id, context.id)
    }

    func testSoftDelete() async throws {
        let context = try await GlobalContextDAO.shared.insert(content: "Temporary note")
        try await GlobalContextDAO.shared.softDelete(id: context.id)
        let active = try await GlobalContextDAO.shared.fetchActive()
        XCTAssertTrue(active.isEmpty)
        let all = try await GlobalContextDAO.shared.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all.first?.deleted ?? false)
    }

    func testSuggestionLogStatusFlow() async throws {
        let suggestion = try await GlobalContextDAO.shared.insertSuggestion(
            content: "Suggested rule",
            reason: "Important",
            status: .accepted
        )
        XCTAssertEqual(suggestion.status, .accepted)
        try await GlobalContextDAO.shared.updateSuggestionStatus(id: suggestion.id, status: .rejected, rejectionFeedback: "Not now")
        let all = try await GlobalContextDAO.shared.fetchSuggestions()
        XCTAssertEqual(all.first?.status, .rejected)
        XCTAssertEqual(all.first?.rejectionFeedback, "Not now")
    }

    func testSuggestionLogParentId() async throws {
        let parent = try await GlobalContextDAO.shared.insertSuggestion(content: "Parent", status: .accepted)
        let child = try await GlobalContextDAO.shared.insertSuggestion(content: "Child", status: .rejected, parentId: parent.id)
        XCTAssertEqual(child.parentId, parent.id)
    }
}
