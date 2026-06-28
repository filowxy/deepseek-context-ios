import Foundation

enum MarkType: String, CaseIterable {
    case userask
    case complex
}

struct ContextMark: Identifiable, Equatable {
    let id: Int64
    let markId: Int64
    let conversationId: String
    let lev: Int
    let type: MarkType
    let content: String
    let idemKey: String
    let createdCounter: Int64
    var lastRemindCounter: Int64?
    let createdAt: Date
    var deleted: Bool
    var deletedAt: Date?

    init(
        id: Int64,
        markId: Int64,
        conversationId: String,
        lev: Int,
        type: MarkType,
        content: String,
        idemKey: String,
        createdCounter: Int64,
        lastRemindCounter: Int64? = nil,
        createdAt: Date = Date(),
        deleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.markId = markId
        self.conversationId = conversationId
        self.lev = lev
        self.type = type
        self.content = content
        self.idemKey = idemKey
        self.createdCounter = createdCounter
        self.lastRemindCounter = lastRemindCounter
        self.createdAt = createdAt
        self.deleted = deleted
        self.deletedAt = deletedAt
    }
}
