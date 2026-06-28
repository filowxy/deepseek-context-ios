import Foundation

actor SkillManager {
    static let shared = SkillManager()
    private init() {}

    private var skillDAO: SkillDAO { SkillDAO.shared }

    /// Maximum skills injected in a single `<skill-load>` block.
    static let injectionLimit = 10

    /// Load global skills plus project skills for the conversation, sorted for injection.
    func loadSkills(for conversationId: String) async throws -> [Skill] {
        let global = try await skillDAO.fetchGlobal()
        let project = try await skillDAO.fetchProject(for: conversationId)
        return sortForInjection(global + project)
    }

    /// Find a skill by name, preferring project scope for the current conversation.
    func findSkill(name: String, conversationId: String) async throws -> Skill? {
        if let project = try await skillDAO.fetch(byName: name, scope: .project, conversationId: conversationId) {
            return project
        }
        return try await skillDAO.fetch(byName: name, scope: .global)
    }

    /// Update the last-used timestamp for a skill.
    func recordUsage(id: Int64) async throws {
        guard let skill = try await skillDAO.fetch(byId: id) else { return }
        var updated = skill
        updated.lastUsedAt = Date()
        try await skillDAO.update(updated)
    }

    /// Format the skill list as an injected `<skill-load>` XML block.
    func formatSkillLoad(skills: [Skill]) -> String {
        let limited = Array(sortForInjection(skills).prefix(Self.injectionLimit))
        guard !limited.isEmpty else { return "" }
        let lines = limited.enumerated().map { index, skill in
            "count:'\(index + 1)',name:'\(skill.name)',when-to-use:'\(skill.whentouse)'"
        }
        return "<skill-load>\n" + lines.joined(separator: "\n") + "\n</skill-load>"
    }

    // MARK: - Sorting

    /// Sort skills: recently used first, then recently updated, then alphabetically.
    private func sortForInjection(_ skills: [Skill]) -> [Skill] {
        skills.sorted { lhs, rhs in
            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case (let l?, let r?):
                if l != r { return l > r }
            case (let l?, nil):
                return true
            case (nil, let r?):
                return false
            default:
                break
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.name < rhs.name
        }
    }
}
