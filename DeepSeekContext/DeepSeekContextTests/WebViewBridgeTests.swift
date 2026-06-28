import XCTest
@testable import DeepSeekContext

final class WebViewBridgeTests: XCTestCase {

    private var bridge: WebViewBridge!
    private var delegate: MockBridgeDelegate!

    override func setUp() {
        super.setUp()
        bridge = WebViewBridge()
        delegate = MockBridgeDelegate()
        bridge.delegate = delegate
    }

    override func tearDown() {
        bridge = nil
        delegate = nil
        super.tearDown()
    }

    func testSendStartedIncrementsMessageIndex() {
        XCTAssertEqual(bridge.messageIndex, 0)
        bridge.handleMessage(["type": "sendStarted", "payload": [:]])
        XCTAssertEqual(bridge.messageIndex, 1)
        XCTAssertEqual(delegate.commands.count, 1)
        guard case .injectSystem(let text) = delegate.commands.first else {
            XCTFail("expected inject system command")
            return
        }
        XCTAssertTrue(text.contains("当前对话轮次: 1"))
    }

    func testFinalReplyWithoutConversationReportsError() {
        let expectation = self.expectation(description: "error reported")
        delegate.onError = { _ in expectation.fulfill() }

        bridge.handleMessage([
            "type": "finalReply",
            "payload": ["text": "<main>{\"type\":\"userask\",\"lev\":0,\"content\":\"x\",\"idem_key\":\"c_1_userask_1\"}</main>"]
        ])

        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(delegate.errors.isEmpty)
    }

    func testBindConversation() async {
        await bridge.bindConversation(id: "conv-test")
        XCTAssertEqual(bridge.conversationId, "conv-test")
        XCTAssertEqual(bridge.messageIndex, 0)
        XCTAssertEqual(bridge.roundCounter, 0)
    }

    func testDomHealthMessageForwarded() {
        bridge.handleMessage([
            "type": "domHealth",
            "payload": ["healthy": false, "missingSelector": "textarea"]
        ])
        XCTAssertEqual(delegate.healthEvents.count, 1)
        XCTAssertFalse(delegate.healthEvents.first?.healthy ?? true)
        XCTAssertEqual(delegate.healthEvents.first?.selector, "textarea")
    }
}

private final class MockBridgeDelegate: WebViewBridgeDelegate {
    var commands: [OutgoingWebViewCommand] = []
    var errors: [String] = []
    var healthEvents: [(healthy: Bool, selector: String?)] = []
    var onError: ((String) -> Void)?

    func bridge(_ bridge: WebViewBridge, sendCommand command: OutgoingWebViewCommand) {
        commands.append(command)
    }

    func bridge(_ bridge: WebViewBridge, didReceiveCleanText text: String) {}
    func bridge(_ bridge: WebViewBridge, didReceiveAction action: XMLTagAction) {}

    func bridge(_ bridge: WebViewBridge, domHealthChanged healthy: Bool, missingSelector: String?) {
        healthEvents.append((healthy, missingSelector))
    }

    func bridge(_ bridge: WebViewBridge, didLog level: String, message: String) {}

    func bridge(_ bridge: WebViewBridge, didEncounterError error: String) {
        errors.append(error)
        onError?(error)
    }
}
