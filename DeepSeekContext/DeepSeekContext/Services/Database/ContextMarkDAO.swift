import Foundation
import SQLite3

actor ContextMarkDAO {
    static let shared = ContextMarkDAO()
    private init() {}

    private var db: DatabaseManager { DatabaseManager.shared }

    func upsert(_ mark: ContextMark) async throws -> ContextMark {
        let existing = try await fetch(byIdemKey: mark.idemKey)
        if let existing {
            return try await update(existing: existing, with: mark)
        }
        return try await insert(mark)
    }

    private func insert(_ mark: ContextMark) throws -> ContextMark {
        let sql = """
            INSERT INTO context_marks (
                mark_id, conversation_id, lev, type, content, idem_key,
                created_counter, last_remind_counter, created_at, deleted, deleted_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(mark: mark, stmt: stmt)
        _ = try db.step(stmt)
        let id = try db.lastInsertedRowID()
        return ContextMark(
            id: id,
            markId: mark.markId,
            conversationId: mark.conversationId,
            lev: mark.lev,
            type: mark.type,
            content: mark.content,
            idemKey: mark.idemKey,
            createdCounter: mark.createdCounter,
            lastRemindCounter: mark.lastRemindCounter,
            createdAt: mark.createdAt,
            deleted: mark.deleted,
            deletedAt: mark.deletedAt
        )
    }

    private func update(existing: ContextMark, with mark: ContextMark) throws -> ContextMark {
        let sql = """
            UPDATE context_marks
            SET content = ?, idem_key = ?, deleted = 0, deleted_at = NULL,
                last_remind_counter = ?, created_at = ?
            WHERE id = ?;
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: mark.content)
        try db.bindText(stmt, index: 2, value: mark.idemKey)
        try db.bindOptionalInt64(stmt, index: 3, value: mark.lastRemindCounter)
        try db.bindText(stmt, index: 4, value: db.string(from: mark.createdAt))
        try db.bindInt64(stmt, index: 5, value: existing.id)
        _ = try db.step(stmt)
        return ContextMark(
            id: existing.id,
            markId: existing.markId,
            conversationId: existing.conversationId,
            lev: existing.lev,
            type: existing.type,
            content: mark.content,
            idemKey: mark.idemKey,
            createdCounter: existing.createdCounter,
            lastRemindCounter: mark.lastRemindCounter,
            createdAt: mark.createdAt,
            deleted: false,
            deletedAt: nil
        )
    }

    func fetch(byId id: Int64) async throws -> ContextMark? {
        let sql = baseSelect + " WHERE id = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindInt64(stmt, index: 1, value: id)
        guard try db.step(stmt) else { return nil }
        return mark(from: stmt)
    }

    func fetch(byIdemKey idemKey: String) async throws -> ContextMark? {
        let sql = baseSelect + " WHERE idem_key = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: idemKey)
        guard try db.step(stmt) else { return nil }
        return mark(from: stmt)
    }

    func fetch(byConversationId conversationId: String, includeDeleted: Bool = false) async throws -> [ContextMark] {
        let sql = includeDeleted
            ? baseSelect + " WHERE conversation_id = ? ORDER BY created_at DESC;"
            : baseSelect + " WHERE conversation_id = ? AND deleted = 0 ORDER BY created_at DESC;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: conversationId)
        var results: [ContextMark] = []
        while try db.step(stmt) {
            results.append(mark(from: stmt))
        }
        return results
    }

    func softDelete(id: Int64) async throws {
        let sql = """
            UPDATE context_marks
            SET deleted = 1, deleted_at = ?
            WHERE id = ?;
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: db.string(from: Date()))
        try db.bindInt64(stmt, index: 2, value: id)
        _ = try db.step(stmt)
    }

    func recover(id: Int64) async throws {
        let sql = """
            UPDATE context_marks
            SET deleted = 0, deleted_at = NULL
            WHERE id = ?;
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindInt64(stmt, index: 1, value: id)
        _ = try db.step(stmt)
    }

    func updateLastRemindCounter(id: Int64, counter: Int64) async throws {
        let sql = "UPDATE context_marks SET last_remind_counter = ? WHERE id = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindInt64(stmt, index: 1, value: counter)
        try db.bindInt64(stmt, index: 2, value: id)
        _ = try db.step(stmt)
    }

    func nextMarkId(for conversationId: String) async throws -> Int64 {
        let sql = "SELECT COALESCE(MAX(mark_id), 0) + 1 FROM context_marks WHERE conversation_id = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: conversationId)
        guard try db.step(stmt) else { return 1 }
        return db.columnInt64(stmt, index: 0)
    }

    func nextMarkIdWithParent(for conversationId: String, parentId: String) async throws -> Int64 {
        let parentMax = try await maxMarkId(for: parentId)
        let selfMax = try await maxMarkId(for: conversationId)
        return max(parentMax, selfMax) + 1
    }

    func maxMarkId(for conversationId: String) async throws -> Int64 {
        let sql = "SELECT COALESCE(MAX(mark_id), 0) FROM context_marks WHERE conversation_id = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: conversationId)
        guard try db.step(stmt) else { return 0 }
        return db.columnInt64(stmt, index: 0)
    }

    // MARK: - Helpers

    private var baseSelect: String {
        """
        SELECT id, mark_id, conversation_id, lev, type, content, idem_key,
               created_counter, last_remind_counter, created_at, deleted, deleted_at
        FROM context_marks
        """
    }

    private func bind(mark: ContextMark, stmt: OpaquePointer) throws {
        try db.bindInt64(stmt, index: 1, value: mark.markId)
        try db.bindText(stmt, index: 2, value: mark.conversationId)
        try db.bindInt64(stmt, index: 3, value: Int64(mark.lev))
        try db.bindText(stmt, index: 4, value: mark.type.rawValue)
        try db.bindText(stmt, index: 5, value: mark.content)
        try db.bindText(stmt, index: 6, value: mark.idemKey)
        try db.bindInt64(stmt, index: 7, value: mark.createdCounter)
        try db.bindOptionalInt64(stmt, index: 8, value: mark.lastRemindCounter)
        try db.bindText(stmt, index: 9, value: db.string(from: mark.createdAt))
        try db.bindInt64(stmt, index: 10, value: mark.deleted ? 1 : 0)
        try db.bindOptionalText(stmt, index: 11, value: mark.deletedAt.map { db.string(from: $0) })
    }

    private func mark(from stmt: OpaquePointer) -> ContextMark {
        let id = db.columnInt64(stmt, index: 0)
        let markId = db.columnInt64(stmt, index: 1)
        let conversationId = db.columnText(stmt, index: 2)
        let lev = Int(db.columnInt64(stmt, index: 3))
        let type = MarkType(rawValue: db.columnText(stmt, index: 4)) ?? .complex
        let content = db.columnText(stmt, index: 5)
        let idemKey = db.columnText(stmt, index: 6)
        let createdCounter = db.columnInt64(stmt, index: 7)
        let lastRemindCounter = db.columnInt64(stmt, index: 8)
        let createdAt = db.date(from: db.columnText(stmt, index: 9)) ?? Date()
        let deleted = db.columnBool(stmt, index: 10)
        let deletedAt = db.columnOptionalText(stmt, index: 11).flatMap { db.date(from: $0) }
        return ContextMark(
            id: id,
            markId: markId,
            conversationId: conversationId,
            lev: lev,
            type: type,
            content: content,
            idemKey: idemKey,
            createdCounter: createdCounter,
            lastRemindCounter: lastRemindCounter >= 0 ? lastRemindCounter : nil,
            createdAt: createdAt,
            deleted: deleted,
            deletedAt: deletedAt
        )
    }
}
