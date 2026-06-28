import XCTest
@testable import DeepSeekContext

final class XMLTagParserTests: XCTestCase {

    func testParseMainMark() {
        let text = #"""
        <main>
        {"type": "userask", "lev": 2, "content": "洞穴系统必须兼容原版生物群系标签", "tags": ["洞穴"], "idem_key": "conv8_5_userask_1"}
        </main>
        """#
        let actions = XMLTagParser.parse(text)
        XCTAssertEqual(actions.count, 1)
        guard case .mark(let payload) = actions.first else {
            XCTFail("expected mark action")
            return
        }
        XCTAssertEqual(payload.type, .userask)
        XCTAssertEqual(payload.lev, 2)
        XCTAssertEqual(payload.content, "洞穴系统必须兼容原版生物群系标签")
        XCTAssertEqual(payload.tags, ["洞穴"])
        XCTAssertEqual(payload.idemKey, "conv8_5_userask_1")
    }

    func testParseDeleteAndRecover() {
        let text = #"""
        <de-main>{"id": 3}</de-main>
        <recover-mark>{"id": 5}</recover-mark>
        """#
        let actions = XMLTagParser.parse(text)
        XCTAssertEqual(actions.count, 2)
        guard case .delete(let d) = actions.first, case .recover(let r) = actions.last else {
            XCTFail("expected delete then recover")
            return
        }
        XCTAssertEqual(d.markId, 3)
        XCTAssertEqual(r.markId, 5)
    }

    func testParseRecallAndAll() {
        let text = #"""
        <recall-context>{"query": {"search": "TerraBlender", "scope": "all"}}</recall-context>
        <all>{"type": "context", "searchinfo": "recall-co3-tkkx3se"}</all>
        """#
        let actions = XMLTagParser.parse(text)
        XCTAssertEqual(actions.count, 2)
        guard case .recall(let recall) = actions.first, case .all(let all) = actions.last else {
            XCTFail("expected recall then all")
            return
        }
        XCTAssertEqual(recall.query, "TerraBlender")
        XCTAssertEqual(recall.scope, .all)
        XCTAssertEqual(all.searchId, "recall-co3-tkkx3se")
    }

    func testParseSearchOpenAndSkill() {
        let text = #"""
        <search>{"q": "Minecraft NeoForge cave generation", "depth": "detailed"}</search>
        <open>{"type": "url", "dis": "https://github.com/MinecraftForge/ForgeGradle"}</open>
        <call-skill>name:'审查输出'</call-skill>
        """#
        let actions = XMLTagParser.parse(text)
        XCTAssertEqual(actions.count, 3)
        guard case .search(let search) = actions[0],
              case .open(let open) = actions[1],
              case .callSkill(let skill) = actions[2] else {
            XCTFail("expected search, open, call-skill")
            return
        }
        XCTAssertEqual(search.query, "Minecraft NeoForge cave generation")
        XCTAssertEqual(search.depth, "detailed")
        XCTAssertEqual(open.url, "https://github.com/MinecraftForge/ForgeGradle")
        XCTAssertEqual(skill.name, "审查输出")
    }

    func testParseGlobalSuggest() {
        let text = #"<global-suggest>{"content": "高度上限 380 格", "reason": "核心约束"}</global-suggest>"#
        let actions = XMLTagParser.parse(text)
        XCTAssertEqual(actions.count, 1)
        guard case .globalSuggest(let payload) = actions.first else {
            XCTFail("expected global suggest")
            return
        }
        XCTAssertEqual(payload.content, "高度上限 380 格")
        XCTAssertEqual(payload.reason, "核心约束")
    }

    func testStripTags() {
        let text = #"""
        正常回复内容
        <main>{"type": "complex", "lev": 1, "content": "x", "idem_key": "c_1_complex_1"}</main>
        后续内容
        """#
        let clean = XMLTagParser.stripTags(text)
        XCTAssertFalse(clean.contains("<main>"))
        XCTAssertTrue(clean.contains("正常回复内容"))
        XCTAssertTrue(clean.contains("后续内容"))
    }

    func testInvalidMarkIsIgnored() {
        let text = #"<main>{"type": "unknown", "lev": 5, "content": "", "idem_key": "x"}</main>"#
        let actions = XMLTagParser.parse(text)
        XCTAssertTrue(actions.isEmpty)
    }
}
