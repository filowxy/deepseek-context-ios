import Foundation

enum ContextEngineError: Error {
    case invalidLevel
    case invalidType
    case emptyContent
}

actor ContextEngine {
    static let shared = ContextEngine()
    private init() {}

    private var markDAO: ContextMarkDAO { ContextMarkDAO.shared }
    private var conversationDAO: ConversationDAO { ConversationDAO.shared }
    private var tagDAO: TagDAO { TagDAO.shared }

    /// Create or update a context mark.
    /// - Parameters:
    ///   - type: mark type, must be userask or complex
    ///   - lev: importance level, must be 0...3
    ///   - content: non-empty content text
    ///   - tags: optional tags
    ///   - conversationId: owning conversation
    ///   - messageIndex: current round index for idem_key
    ///   - sequence: mark sequence within the round
    ///   - createdCounter: conversation counter when the mark was created
    func createMark(
        type: MarkType,
        lev: Int,
        content: String,
        tags: [String] = [],
        conversationId: String,
        messageIndex: Int,
        sequence: Int,
        createdCounter: Int64,
        lastRemindCounter: Int64? = nil
    ) async throws -> ContextMark {
        guard (0...3).contains(lev) else {
            throw ContextEngineError.invalidLevel
        }
        guard !content.isEmpty else {
            throw ContextEngineError.emptyContent
        }

        let idemKey = Self.idemKey(conversationId: conversationId, messageIndex: messageIndex, type: type, sequence: sequence)
        let existing = try await markDAO.fetch(byIdemKey: idemKey)

        let markId: Int64
        if let existing {
            markId = existing.markId
        } else {
            markId = try await nextMarkId(for: conversationId)
        }

        let mark = ContextMark(
            id: existing?.id ?? 0,
            markId: markId,
            conversationId: conversationId,
            lev: lev,
            type: type,
            content: content,
            idemKey: idemKey,
            createdCounter: createdCounter,
            lastRemindCounter: existing?.lastRemindCounter ?? lastRemindCounter,
            createdAt: Date(),
            deleted: false,
            deletedAt: nil
        )

        let saved = try await markDAO.upsert(mark)
        if !tags.isEmpty {
            try await tagDAO.setTags(for: saved.id, tags: tags)
        }
        return saved
    }

    func deleteMark(id: Int64) async throws {
        try await markDAO.softDelete(id: id)
    }

    func recoverMark(id: Int64) async throws {
        try await markDAO.recover(id: id)
    }

    /// Generate the idempotency key used by AI XML protocol.
    static func idemKey(conversationId: String, messageIndex: Int, type: MarkType, sequence: Int) -> String {
        "\(conversationId)_\(messageIndex)_\(type.rawValue)_\(sequence)"
    }

    private func nextMarkId(for conversationId: String) async throws -> Int64 {
        if let parentId = try await conversationDAO.parentId(of: conversationId) {
            return try await markDAO.nextMarkIdWithParent(for: conversationId, parentId: parentId)
        }
        return try await markDAO.nextMarkId(for: conversationId)
    }
}
