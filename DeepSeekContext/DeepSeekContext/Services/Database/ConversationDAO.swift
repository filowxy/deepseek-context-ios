import Foundation
import SQLite3

actor ConversationDAO {
    static let shared = ConversationDAO()
    private init() {}

    private var db: DatabaseManager { DatabaseManager.shared }

    // MARK: - Conversations

    func insert(_ conversation: Conversation) async throws {
        let sql = """
            INSERT INTO conversations (id, title, created_at, updated_at, is_active)
            VALUES (?, ?, ?, ?, ?);
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: conversation.id)
        try db.bindOptionalText(stmt, index: 2, value: conversation.title)
        try db.bindText(stmt, index: 3, value: db.string(from: conversation.createdAt))
        try db.bindText(stmt, index: 4, value: db.string(from: conversation.updatedAt))
        try db.bindInt64(stmt, index: 5, value: conversation.isActive ? 1 : 0)
        _ = try db.step(stmt)

        try await ensureCounter(for: conversation.id)
    }

    func update(_ conversation: Conversation) async throws {
        let sql = """
            UPDATE conversations
            SET title = ?, updated_at = ?, is_active = ?
            WHERE id = ?;
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindOptionalText(stmt, index: 1, value: conversation.title)
        try db.bindText(stmt, index: 2, value: db.string(from: conversation.updatedAt))
        try db.bindInt64(stmt, index: 3, value: conversation.isActive ? 1 : 0)
        try db.bindText(stmt, index: 4, value: conversation.id)
        _ = try db.step(stmt)
    }

    func fetch(byId id: String) async throws -> Conversation? {
        let sql = "SELECT id, title, created_at, updated_at, is_active FROM conversations WHERE id = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: id)
        guard try db.step(stmt) else { return nil }
        return conversation(from: stmt)
    }

    func fetchActive() async throws -> [Conversation] {
        let sql = """
            SELECT id, title, created_at, updated_at, is_active
            FROM conversations
            WHERE is_active = 1
            ORDER BY updated_at DESC;
        """
        return try await fetchAll(sql: sql)
    }

    func fetchAll() async throws -> [Conversation] {
        let sql = """
            SELECT id, title, created_at, updated_at, is_active
            FROM conversations
            ORDER BY updated_at DESC;
        """
        return try await fetchAll(sql: sql)
    }

    func archive(id: String) async throws {
        guard let conversation = try await fetch(byId: id) else {
            throw DatabaseError.unexpectedNull
        }
        var updated = conversation
        updated.isActive = false
        updated.updatedAt = Date()
        try await update(updated)
    }

    func delete(id: String) async throws {
        let hasChildren = try await self.hasChildren(parentId: id)
        guard !hasChildren else {
            throw DatabaseError.execFailed("Cannot delete conversation with child conversations")
        }
        let sql = "DELETE FROM conversations WHERE id = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: id)
        _ = try db.step(stmt)
    }

    func countActive() async throws -> Int {
        let sql = """
            SELECT COUNT(*) FROM conversations
            WHERE is_active = 1
              AND id NOT IN (
                  SELECT parent_conversation_id FROM conversation_links WHERE parent_conversation_id IS NOT NULL
              );
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        guard try db.step(stmt) else { return 0 }
        return Int(db.columnInt64(stmt, index: 0))
    }

    // MARK: - Conversation Links

    func linkChild(childId: String, parentId: String) async throws {
        guard let _ = try await fetch(byId: childId),
              let _ = try await fetch(byId: parentId) else {
            throw DatabaseError.unexpectedNull
        }
        let sql = """
            INSERT INTO conversation_links (conversation_id, parent_conversation_id, linked_at)
            VALUES (?, ?, ?)
            ON CONFLICT(conversation_id) DO UPDATE SET parent_conversation_id = excluded.parent_conversation_id, linked_at = excluded.linked_at;
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: childId)
        try db.bindText(stmt, index: 2, value: parentId)
        try db.bindText(stmt, index: 3, value: db.string(from: Date()))
        _ = try db.step(stmt)
    }

    func parentId(of conversationId: String) async throws -> String? {
        let sql = "SELECT parent_conversation_id FROM conversation_links WHERE conversation_id = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: conversationId)
        guard try db.step(stmt) else { return nil }
        return db.columnOptionalText(stmt, index: 0)
    }

    func hasChildren(parentId: String) async throws -> Bool {
        let sql = "SELECT COUNT(*) FROM conversation_links WHERE parent_conversation_id = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: parentId)
        guard try db.step(stmt) else { return false }
        return db.columnInt64(stmt, index: 0) > 0
    }

    // MARK: - Counter

    func getCount(for conversationId: String) async throws -> Int64 {
        try await ensureCounter(for: conversationId)
        let sql = "SELECT count FROM conversation_counter WHERE conversation_id = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: conversationId)
        guard try db.step(stmt) else { return 0 }
        return db.columnInt64(stmt, index: 0)
    }

    func increment(for conversationId: String) async throws -> Int64 {
        try await ensureCounter(for: conversationId)
        let sql = """
            UPDATE conversation_counter SET count = count + 1 WHERE conversation_id = ?;
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: conversationId)
        _ = try db.step(stmt)
        return try await getCount(for: conversationId)
    }

    func setCount(for conversationId: String, count: Int64) async throws {
        try await ensureCounter(for: conversationId)
        let sql = "UPDATE conversation_counter SET count = ? WHERE conversation_id = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindInt64(stmt, index: 1, value: count)
        try db.bindText(stmt, index: 2, value: conversationId)
        _ = try db.step(stmt)
    }

    func initializeCounterFromParent(childId: String, parentId: String) async throws {
        let parentCount = try await getCount(for: parentId)
        try await setCount(for: childId, count: parentCount)
    }

    private func ensureCounter(for conversationId: String) async throws {
        let sql = "INSERT OR IGNORE INTO conversation_counter (conversation_id, count) VALUES (?, 0);"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: conversationId)
        _ = try db.step(stmt)
    }

    // MARK: - Helpers

    private func fetchAll(sql: String) async throws -> [Conversation] {
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var results: [Conversation] = []
        while try db.step(stmt) {
            results.append(conversation(from: stmt))
        }
        return results
    }

    private func conversation(from stmt: OpaquePointer) -> Conversation {
        let id = db.columnText(stmt, index: 0)
        let title = db.columnOptionalText(stmt, index: 1)
        let createdAt = db.date(from: db.columnText(stmt, index: 2)) ?? Date()
        let updatedAt = db.date(from: db.columnText(stmt, index: 3)) ?? Date()
        let isActive = db.columnBool(stmt, index: 4)
        return Conversation(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt, isActive: isActive)
    }
}
