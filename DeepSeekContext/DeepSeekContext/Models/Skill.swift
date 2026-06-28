import Foundation

enum SkillScope: String, CaseIterable {
    case global
    case project
}

struct Skill: Identifiable, Equatable {
    let id: Int64
    let name: String
    let whentouse: String
    let description: String
    let scope: SkillScope
    let conversationId: String?
    var lastUsedAt: Date?
    var updatedAt: Date

    init(
        id: Int64,
        name: String,
        whentouse: String,
        description: String,
        scope: SkillScope,
        conversationId: String? = nil,
        lastUsedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.whentouse = whentouse
        self.description = description
        self.scope = scope
        self.conversationId = conversationId
        self.lastUsedAt = lastUsedAt
        self.updatedAt = updatedAt
    }
}
