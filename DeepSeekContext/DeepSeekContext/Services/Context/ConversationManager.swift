import Foundation

actor ConversationManager {
    static let shared = ConversationManager()
    private init() {}

    private var conversationDAO: ConversationDAO { ConversationDAO.shared }
    private var markDAO: ContextMarkDAO { ContextMarkDAO.shared }
    private var tagDAO: TagDAO { TagDAO.shared }
    private var skillDAO: SkillDAO { SkillDAO.shared }

    static let activeConversationSoftLimit = 50

    func createConversation(title: String?) async throws -> Conversation {
        let conversation = Conversation(id: UUID().uuidString, title: title)
        try await conversationDAO.insert(conversation)
        return conversation
    }

    /// Create a child conversation that inherits marks and counter from its parent.
    func createChildConversation(title: String?, parentId: String) async throws -> Conversation {
        guard let parent = try await conversationDAO.fetch(byId: parentId) else {
            throw DatabaseError.unexpectedNull
        }
        let child = Conversation(id: UUID().uuidString, title: title)
        try await conversationDAO.insert(child)
        try await conversationDAO.linkChild(childId: child.id, parentId: parent.id)
        try await conversationDAO.initializeCounterFromParent(childId: child.id, parentId: parent.id)
        try await inheritMarks(childId: child.id, parentId: parent.id)
        try await skillDAO.inheritProjectSkills(from: parent.id, to: child.id)
        return child
    }

    func archiveConversation(id: String) async throws {
        try await conversationDAO.archive(id: id)
    }

    func deleteConversation(id: String) async throws {
        try await conversationDAO.delete(id: id)
    }

    func activeConversationCount() async throws -> Int {
        try await conversationDAO.countActive()
    }

    func activeConversations() async throws -> [Conversation] {
        try await conversationDAO.fetchActive()
    }

    func isAtSoftLimit() async throws -> Bool {
        let count = try await activeConversationCount()
        return count >= Self.activeConversationSoftLimit
    }

    /// Copy active parent marks into the child conversation with new mark_ids.
    private func inheritMarks(childId: String, parentId: String) async throws {
        let parentMarks = try await markDAO.fetch(byConversationId: parentId, includeDeleted: false)
        guard !parentMarks.isEmpty else { return }

        let parentMax = try await markDAO.maxMarkId(for: parentId)
        let childMax = try await markDAO.maxMarkId(for: childId)
        var nextId = max(parentMax, childMax) + 1

        for parentMark in parentMarks.sorted(by: { $0.markId < $1.markId }) {
            let childIdemKey = "\(childId)_inherited_\(parentMark.id)"
            let childMark = ContextMark(
                id: 0,
                markId: nextId,
                conversationId: childId,
                lev: parentMark.lev,
                type: parentMark.type,
                content: parentMark.content,
                idemKey: childIdemKey,
                createdCounter: parentMark.createdCounter,
                lastRemindCounter: parentMark.lastRemindCounter,
                createdAt: Date(),
                deleted: false,
                deletedAt: nil
            )
            let saved = try await markDAO.upsert(childMark)
            let tags = try await tagDAO.fetchTags(for: parentMark.id)
            if !tags.isEmpty {
                try await tagDAO.setTags(for: saved.id, tags: tags)
            }
            nextId += 1
        }
    }
}
