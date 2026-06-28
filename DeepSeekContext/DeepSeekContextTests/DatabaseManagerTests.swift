import XCTest
import SQLite3
@testable import DeepSeekContext

final class DatabaseManagerTests: XCTestCase {
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

    func testSchemaCreation() async throws {
        let db = DatabaseManager.shared
        let sql = """
            SELECT name FROM sqlite_master
            WHERE type = 'table'
              AND name IN (
                  'conversations',
                  'context_marks',
                  'mark_tags',
                  'conversation_links',
                  'conversation_counter',
                  'global_context',
                  'global_suggestion_log',
                  'context_marks_fts'
              );
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var names: Set<String> = []
        while try db.step(stmt) {
            names.insert(db.columnText(stmt, index: 0))
        }
        XCTAssertEqual(names.count, 8)
    }

    func testWALModeEnabled() async throws {
        let db = DatabaseManager.shared
        let stmt = try db.prepare("PRAGMA journal_mode;")
        defer { sqlite3_finalize(stmt) }
        XCTAssertTrue(try db.step(stmt))
        let mode = db.columnText(stmt, index: 0).lowercased()
        XCTAssertEqual(mode, "wal")
    }
}
