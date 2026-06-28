import XCTest
@testable import DeepSeekContext

final class SkillDAOTests: XCTestCase {
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

    func testInsertAndFetchGlobal() async throws {
        let skill = Skill(id: 0, name: "Review", whentouse: "审查输出", description: "Check code", scope: .global)
        let saved = try await SkillDAO.shared.insert(skill)
        XCTAssertTrue(saved.id > 0)

        let fetched = try await SkillDAO.shared.fetch(byId: saved.id)
        XCTAssertEqual(fetched?.name, "Review")
        XCTAssertEqual(fetched?.scope, .global)
    }

    func testFetchProjectForConversation() async throws {
        let conversation = Conversation(id: "conv1", title: "Test")
        try await ConversationDAO.shared.insert(conversation)

        let skill = Skill(id: 0, name: "Plan", whentouse: "制定计划", description: "Plan work", scope: .project, conversationId: "conv1")
        try await SkillDAO.shared.insert(skill)

        let project = try await SkillDAO.shared.fetchProject(for: "conv1")
        XCTAssertEqual(project.count, 1)
        XCTAssertEqual(project.first?.name, "Plan")

        let global = try await SkillDAO.shared.fetchGlobal()
        XCTAssertTrue(global.isEmpty)
    }

    func testUpdate() async throws {
        let skill = Skill(id: 0, name: "Old", whentouse: "x", description: "y", scope: .global)
        let saved = try await SkillDAO.shared.insert(skill)
        let updated = Skill(
            id: saved.id,
            name: "New",
            whentouse: saved.whentouse,
            description: saved.description,
            scope: saved.scope,
            conversationId: saved.conversationId,
            lastUsedAt: saved.lastUsedAt,
            updatedAt: Date()
        )
        try await SkillDAO.shared.update(updated)

        let fetched = try await SkillDAO.shared.fetch(byId: saved.id)
        XCTAssertEqual(fetched?.name, "New")
    }

    func testInheritProjectSkills() async throws {
        let parent = Conversation(id: "parent", title: "Parent")
        let child = Conversation(id: "child", title: "Child")
        try await ConversationDAO.shared.insert(parent)
        try await ConversationDAO.shared.insert(child)

        let skill = Skill(id: 0, name: "Inherited", whentouse: "x", description: "y", scope: .project, conversationId: "parent")
        try await SkillDAO.shared.insert(skill)

        try await SkillDAO.shared.inheritProjectSkills(from: "parent", to: "child")
        let childSkills = try await SkillDAO.shared.fetchProject(for: "child")
        XCTAssertEqual(childSkills.count, 1)
        XCTAssertEqual(childSkills.first?.name, "Inherited")
        XCTAssertEqual(childSkills.first?.conversationId, "child")
    }

    func testDelete() async throws {
        let skill = Skill(id: 0, name: "Delete", whentouse: "x", description: "y", scope: .global)
        let saved = try await SkillDAO.shared.insert(skill)
        try await SkillDAO.shared.delete(id: saved.id)
        let fetched = try await SkillDAO.shared.fetch(byId: saved.id)
        XCTAssertNil(fetched)
    }
}
