import XCTest
@testable import DeepSeekContext

final class SkillManagerTests: XCTestCase {
    private var dbPath: String = ""

    override func setUp() async throws {
        try await super.setUp()
        dbPath = makeTestDatabasePath()
        await DatabaseManager.shared.close()
        try await DatabaseManager.shared.open(databasePath: dbPath)
    }

    override func tearDown() async throws {
        await DatabaseManager.shared.close()
        cleanupTestDatabase(path: dbPath)
        try await super.tearDown()
    }

    func testLoadSkillsIncludesGlobalAndProject() async throws {
        let conversation = Conversation(id: "conv1", title: "Test")
        try await ConversationDAO.shared.insert(conversation)

        let global = Skill(id: 0, name: "Global", whentouse: "g", description: "G", scope: .global)
        let project = Skill(id: 0, name: "Project", whentouse: "p", description: "P", scope: .project, conversationId: "conv1")
        _ = try await SkillDAO.shared.insert(global)
        _ = try await SkillDAO.shared.insert(project)

        let skills = try await SkillManager.shared.loadSkills(for: "conv1")
        XCTAssertEqual(skills.count, 2)
    }

    func testSortByLastUsed() async throws {
        let global = Skill(id: 0, name: "Global", whentouse: "g", description: "G", scope: .global)
        let saved = try await SkillDAO.shared.insert(global)
        try await SkillManager.shared.recordUsage(id: saved.id)

        let project = Skill(id: 0, name: "Project", whentouse: "p", description: "P", scope: .project, conversationId: "conv1")
        _ = try await SkillDAO.shared.insert(project)

        let skills = try await SkillManager.shared.loadSkills(for: "conv1")
        XCTAssertEqual(skills.first?.name, "Global")
    }

    func testFormatSkillLoadLimitsAndSorts() async throws {
        let conversation = Conversation(id: "conv1", title: "Test")
        try await ConversationDAO.shared.insert(conversation)

        for i in 1...12 {
            let skill = Skill(id: 0, name: "Skill\(i)", whentouse: "w", description: "D", scope: .global)
            _ = try await SkillDAO.shared.insert(skill)
        }

        let skills = try await SkillManager.shared.loadSkills(for: "conv1")
        let xml = await SkillManager.shared.formatSkillLoad(skills: skills)
        let lines = xml.split(separator: "\n").filter { $0.hasPrefix("count:") }
        XCTAssertEqual(lines.count, 10)
    }

    func testFindSkillPrefersProject() async throws {
        let conversation = Conversation(id: "conv1", title: "Test")
        try await ConversationDAO.shared.insert(conversation)

        let global = Skill(id: 0, name: "Dup", whentouse: "g", description: "Global", scope: .global)
        let project = Skill(id: 0, name: "Dup", whentouse: "p", description: "Project", scope: .project, conversationId: "conv1")
        _ = try await SkillDAO.shared.insert(global)
        _ = try await SkillDAO.shared.insert(project)

        let found = try await SkillManager.shared.findSkill(name: "Dup", conversationId: "conv1")
        XCTAssertEqual(found?.description, "Project")
    }
}
