import Foundation
import SQLite3

actor GlobalContextDAO {
    static let shared = GlobalContextDAO()
    private init() {}

    private var db: DatabaseManager { DatabaseManager.shared }

    func insert(content: String) async throws -> GlobalContext {
        let sql = """
            INSERT INTO global_context (content, created_at, deleted)
            VALUES (?, ?, 0);
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        let now = Date()
        try db.bindText(stmt, index: 1, value: content)
        try db.bindText(stmt, index: 2, value: db.string(from: now))
        _ = try db.step(stmt)
        let id = try db.lastInsertedRowID()
        return GlobalContext(id: id, content: content, createdAt: now, deleted: false)
    }

    func fetchActive() async throws -> [GlobalContext] {
        let sql = """
            SELECT id, content, created_at, deleted
            FROM global_context
            WHERE deleted = 0
            ORDER BY created_at DESC;
        """
        return try await fetchAll(sql: sql)
    }

    func fetchAll() async throws -> [GlobalContext] {
        let sql = """
            SELECT id, content, created_at, deleted
            FROM global_context
            ORDER BY created_at DESC;
        """
        return try await fetchAll(sql: sql)
    }

    func softDelete(id: Int64) async throws {
        let sql = "UPDATE global_context SET deleted = 1 WHERE id = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindInt64(stmt, index: 1, value: id)
        _ = try db.step(stmt)
    }

    // MARK: - Suggestion Log

    func insertSuggestion(
        content: String,
        reason: String?,
        contentHash: String?,
        status: SuggestionStatus,
        parentId: Int64? = nil,
        rejectionFeedback: String? = nil
    ) async throws -> GlobalSuggestionLog {
        let sql = """
            INSERT INTO global_suggestion_log (
                parent_id, content, reason, content_hash, status, rejection_feedback, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        let now = Date()
        try db.bindOptionalInt64(stmt, index: 1, value: parentId)
        try db.bindText(stmt, index: 2, value: content)
        try db.bindOptionalText(stmt, index: 3, value: reason)
        try db.bindOptionalText(stmt, index: 4, value: contentHash)
        try db.bindText(stmt, index: 5, value: status.rawValue)
        try db.bindOptionalText(stmt, index: 6, value: rejectionFeedback)
        try db.bindText(stmt, index: 7, value: db.string(from: now))
        _ = try db.step(stmt)
        let id = try db.lastInsertedRowID()
        return GlobalSuggestionLog(
            id: id,
            parentId: parentId,
            content: content,
            reason: reason,
            contentHash: contentHash,
            status: status,
            rejectionFeedback: rejectionFeedback,
            createdAt: now
        )
    }

    func updateSuggestionStatus(id: Int64, status: SuggestionStatus, rejectionFeedback: String? = nil) async throws {
        let sql = """
            UPDATE global_suggestion_log
            SET status = ?, rejection_feedback = ?
            WHERE id = ?;
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: status.rawValue)
        try db.bindOptionalText(stmt, index: 2, value: rejectionFeedback)
        try db.bindInt64(stmt, index: 3, value: id)
        _ = try db.step(stmt)
    }

    func fetchSuggestions() async throws -> [GlobalSuggestionLog] {
        let sql = """
            SELECT id, parent_id, content, reason, content_hash, status, rejection_feedback, created_at
            FROM global_suggestion_log
            ORDER BY created_at DESC;
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var results: [GlobalSuggestionLog] = []
        while try db.step(stmt) {
            results.append(suggestion(from: stmt))
        }
        return results
    }

    // MARK: - Helpers

    private func fetchAll(sql: String) async throws -> [GlobalContext] {
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var results: [GlobalContext] = []
        while try db.step(stmt) {
            results.append(globalContext(from: stmt))
        }
        return results
    }

    private func globalContext(from stmt: OpaquePointer) -> GlobalContext {
        let id = db.columnInt64(stmt, index: 0)
        let content = db.columnText(stmt, index: 1)
        let createdAt = db.date(from: db.columnText(stmt, index: 2)) ?? Date()
        let deleted = db.columnBool(stmt, index: 3)
        return GlobalContext(id: id, content: content, createdAt: createdAt, deleted: deleted)
    }

    private func suggestion(from stmt: OpaquePointer) -> GlobalSuggestionLog {
        let id = db.columnInt64(stmt, index: 0)
        let parentId = db.columnInt64(stmt, index: 1)
        let content = db.columnText(stmt, index: 2)
        let reason = db.columnOptionalText(stmt, index: 3)
        let contentHash = db.columnOptionalText(stmt, index: 4)
        let status = SuggestionStatus(rawValue: db.columnText(stmt, index: 5)) ?? .accepted
        let rejectionFeedback = db.columnOptionalText(stmt, index: 6)
        let createdAt = db.date(from: db.columnText(stmt, index: 7)) ?? Date()
        return GlobalSuggestionLog(
            id: id,
            parentId: parentId >= 0 ? parentId : nil,
            content: content,
            reason: reason,
            contentHash: contentHash,
            status: status,
            rejectionFeedback: rejectionFeedback,
            createdAt: createdAt
        )
    }
}
