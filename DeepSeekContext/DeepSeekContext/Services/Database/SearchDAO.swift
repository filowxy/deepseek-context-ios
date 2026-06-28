import Foundation
import SQLite3

actor SearchDAO {
    static let shared = SearchDAO()
    private init() {}

    private var db: DatabaseManager { DatabaseManager.shared }

    /// Search active marks using FTS5 BM25 ranking.
    /// - Parameters:
    ///   - query: raw query string; escapes special FTS5 characters internally
    ///   - limit: maximum results
    ///   - scopeConversationIds: when provided, restricts to these conversations
    func searchFullText(
        query: String,
        limit: Int,
        scopeConversationIds: [String]? = nil
    ) async throws -> [RecallResult.Item] {
        let escaped = fts5Escape(query)
        var sql = """
            SELECT cm.id, cm.mark_id, cm.lev, cm.content, cm.created_at
            FROM context_marks_fts fts
            JOIN context_marks cm ON cm.id = fts.rowid
            WHERE fts MATCH ? AND cm.deleted = 0
        """
        if let scopeConversationIds, !scopeConversationIds.isEmpty {
            let placeholders = scopeConversationIds.map { _ in "?" }.joined(separator: ",")
            sql += " AND cm.conversation_id IN (\(placeholders))"
        }
        sql += " ORDER BY bm25(context_marks_fts) LIMIT ?;"

        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var index: Int32 = 1
        try db.bindText(stmt, index: Int(index), value: escaped)
        index += 1
        if let scopeConversationIds {
            for id in scopeConversationIds {
                try db.bindText(stmt, index: Int(index), value: id)
                index += 1
            }
        }
        try db.bindInt64(stmt, index: Int(index), value: Int64(limit))

        var results: [RecallResult.Item] = []
        while try db.step(stmt) {
            results.append(item(from: stmt))
        }
        return results
    }

    /// Find active marks by exact tag match.
    func searchByTag(
        tag: String,
        limit: Int,
        scopeConversationIds: [String]? = nil
    ) async throws -> [RecallResult.Item] {
        var sql = """
            SELECT cm.id, cm.mark_id, cm.lev, cm.content, cm.created_at
            FROM context_marks cm
            JOIN mark_tags mt ON mt.mark_id = cm.id
            WHERE mt.tag = ? AND cm.deleted = 0
        """
        if let scopeConversationIds, !scopeConversationIds.isEmpty {
            let placeholders = scopeConversationIds.map { _ in "?" }.joined(separator: ",")
            sql += " AND cm.conversation_id IN (\(placeholders))"
        }
        sql += " ORDER BY cm.created_at DESC LIMIT ?;"

        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var index: Int32 = 1
        try db.bindText(stmt, index: Int(index), value: tag)
        index += 1
        if let scopeConversationIds {
            for id in scopeConversationIds {
                try db.bindText(stmt, index: Int(index), value: id)
                index += 1
            }
        }
        try db.bindInt64(stmt, index: Int(index), value: Int64(limit))

        var results: [RecallResult.Item] = []
        while try db.step(stmt) {
            results.append(item(from: stmt))
        }
        return results
    }

    // MARK: - Helpers

    private func item(from stmt: OpaquePointer) -> RecallResult.Item {
        let id = db.columnInt64(stmt, index: 0)
        let markId = db.columnInt64(stmt, index: 1)
        let lev = Int(db.columnInt64(stmt, index: 2))
        let content = db.columnText(stmt, index: 3)
        let createdAt = db.date(from: db.columnText(stmt, index: 4)) ?? Date()
        // ponytail: tags are fetched separately by RecallEngine to avoid N+1 in hot path
        return RecallResult.Item(markId: markId, lev: lev, content: content, tags: [], createdAt: createdAt)
    }

    /// Escape characters that have special meaning in FTS5 query syntax.
    private func fts5Escape(_ query: String) -> String {
        // Wrap the entire query in double quotes to treat it as a single phrase token.
        // Internal double quotes are doubled per FTS5 rules.
        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"" + escaped + "\""
    }
}
