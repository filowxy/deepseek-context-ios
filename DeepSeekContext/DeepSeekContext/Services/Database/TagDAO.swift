import Foundation
import SQLite3

actor TagDAO {
    static let shared = TagDAO()
    private init() {}

    private var db: DatabaseManager { DatabaseManager.shared }

    func setTags(for markId: Int64, tags: [String]) async throws {
        let deleteSQL = "DELETE FROM mark_tags WHERE mark_id = ?;"
        let deleteStmt = try db.prepare(deleteSQL)
        defer { sqlite3_finalize(deleteStmt) }
        try db.bindInt64(deleteStmt, index: 1, value: markId)
        _ = try db.step(deleteStmt)

        let insertSQL = "INSERT INTO mark_tags (mark_id, tag) VALUES (?, ?);"
        for tag in tags {
            let stmt = try db.prepare(insertSQL)
            defer { sqlite3_finalize(stmt) }
            try db.bindInt64(stmt, index: 1, value: markId)
            try db.bindText(stmt, index: 2, value: tag)
            _ = try db.step(stmt)
        }
    }

    func fetchTags(for markId: Int64) async throws -> [String] {
        let sql = "SELECT tag FROM mark_tags WHERE mark_id = ? ORDER BY tag;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindInt64(stmt, index: 1, value: markId)
        var results: [String] = []
        while try db.step(stmt) {
            results.append(db.columnText(stmt, index: 0))
        }
        return results
    }

    func fetchMarkIds(byTag tag: String) async throws -> [Int64] {
        let sql = "SELECT mark_id FROM mark_tags WHERE tag = ? ORDER BY mark_id;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: tag)
        var results: [Int64] = []
        while try db.step(stmt) {
            results.append(db.columnInt64(stmt, index: 0))
        }
        return results
    }
}
