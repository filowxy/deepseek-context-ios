import Foundation
import SQLite3

actor SkillDAO {
    static let shared = SkillDAO()
    private init() {}

    private var db: DatabaseManager { DatabaseManager.shared }

    func insert(_ skill: Skill) async throws -> Skill {
        let sql = """
            INSERT INTO skills (name, whentouse, description, scope, conversation_id, last_used_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(skill: skill, stmt: stmt)
        _ = try db.step(stmt)
        let id = try db.lastInsertedRowID()
        return Skill(
            id: id,
            name: skill.name,
            whentouse: skill.whentouse,
            description: skill.description,
            scope: skill.scope,
            conversationId: skill.conversationId,
            lastUsedAt: skill.lastUsedAt,
            updatedAt: skill.updatedAt
        )
    }

    func update(_ skill: Skill) async throws {
        let sql = """
            UPDATE skills
            SET name = ?, whentouse = ?, description = ?, scope = ?, conversation_id = ?,
                last_used_at = ?, updated_at = ?
            WHERE id = ?;
        """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(skill: skill, stmt: stmt)
        try db.bindInt64(stmt, index: 8, value: skill.id)
        _ = try db.step(stmt)
    }

    func delete(id: Int64) async throws {
        let sql = "DELETE FROM skills WHERE id = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindInt64(stmt, index: 1, value: id)
        _ = try db.step(stmt)
    }

    func fetch(byId id: Int64) async throws -> Skill? {
        let sql = baseSelect + " WHERE id = ?;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindInt64(stmt, index: 1, value: id)
        guard try db.step(stmt) else { return nil }
        return skill(from: stmt)
    }

    func fetch(byName name: String, scope: SkillScope, conversationId: String? = nil) async throws -> Skill? {
        let sql: String
        let stmt: OpaquePointer
        if scope == .global {
            sql = baseSelect + " WHERE name = ? AND scope = 'global';"
            stmt = try db.prepare(sql)
            try db.bindText(stmt, index: 1, value: name)
        } else {
            sql = baseSelect + " WHERE name = ? AND scope = 'project' AND conversation_id = ?;"
            stmt = try db.prepare(sql)
            try db.bindText(stmt, index: 1, value: name)
            try db.bindText(stmt, index: 2, value: conversationId ?? "")
        }
        defer { sqlite3_finalize(stmt) }
        guard try db.step(stmt) else { return nil }
        return skill(from: stmt)
    }

    func fetchGlobal() async throws -> [Skill] {
        let sql = baseSelect + " WHERE scope = 'global' ORDER BY name;"
        return try await fetchAll(sql: sql)
    }

    func fetchProject(for conversationId: String) async throws -> [Skill] {
        let sql = baseSelect + " WHERE scope = 'project' AND conversation_id = ? ORDER BY name;"
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.bindText(stmt, index: 1, value: conversationId)
        var results: [Skill] = []
        while try db.step(stmt) {
            results.append(skill(from: stmt))
        }
        return results
    }

    func inheritProjectSkills(from parentId: String, to childId: String) async throws {
        let parentSkills = try await fetchProject(for: parentId)
        guard !parentSkills.isEmpty else { return }
        for skill in parentSkills {
            let inherited = Skill(
                id: 0,
                name: skill.name,
                whentouse: skill.whentouse,
                description: skill.description,
                scope: .project,
                conversationId: childId,
                lastUsedAt: nil,
                updatedAt: Date()
            )
            _ = try await insert(inherited)
        }
    }

    // MARK: - Helpers

    private var baseSelect: String {
        "SELECT id, name, whentouse, description, scope, conversation_id, last_used_at, updated_at FROM skills"
    }

    private func bind(skill: Skill, stmt: OpaquePointer) throws {
        try db.bindText(stmt, index: 1, value: skill.name)
        try db.bindText(stmt, index: 2, value: skill.whentouse)
        try db.bindText(stmt, index: 3, value: skill.description)
        try db.bindText(stmt, index: 4, value: skill.scope.rawValue)
        try db.bindOptionalText(stmt, index: 5, value: skill.conversationId)
        try db.bindOptionalText(stmt, index: 6, value: skill.lastUsedAt.map { db.string(from: $0) })
        try db.bindText(stmt, index: 7, value: db.string(from: skill.updatedAt))
    }

    private func skill(from stmt: OpaquePointer) -> Skill {
        let id = db.columnInt64(stmt, index: 0)
        let name = db.columnText(stmt, index: 1)
        let whentouse = db.columnText(stmt, index: 2)
        let description = db.columnText(stmt, index: 3)
        let scope = SkillScope(rawValue: db.columnText(stmt, index: 4)) ?? .global
        let conversationId = db.columnOptionalText(stmt, index: 5)
        let lastUsedAt = db.columnOptionalText(stmt, index: 6).flatMap { db.date(from: $0) }
        let updatedAt = db.date(from: db.columnText(stmt, index: 7)) ?? Date()
        return Skill(
            id: id,
            name: name,
            whentouse: whentouse,
            description: description,
            scope: scope,
            conversationId: conversationId,
            lastUsedAt: lastUsedAt,
            updatedAt: updatedAt
        )
    }

    private func fetchAll(sql: String) async throws -> [Skill] {
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var results: [Skill] = []
        while try db.step(stmt) {
            results.append(skill(from: stmt))
        }
        return results
    }
}
