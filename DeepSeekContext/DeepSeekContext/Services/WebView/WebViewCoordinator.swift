import Foundation
import WebKit
import SwiftUI

/// Coordinates a WKWebView instance with the native context bridge.
final class WebViewCoordinator: NSObject {
    static let messageHandlerName = "deepSeekContext"
    static let deepSeekURL = URL(string: "https://chat.deepseek.com")!

    let webView: WKWebView
    let bridge: WebViewBridge

    override init() {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        config.userContentController = userContentController

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences

        self.webView = WKWebView(frame: .zero, configuration: config)
        self.bridge = WebViewBridge()
        super.init()

        self.bridge.delegate = self
        userContentController.add(self, name: Self.messageHandlerName)
        injectBridgeScript()
    }

    /// Load the DeepSeek chat page.
    func loadDeepSeek() {
        let request = URLRequest(url: Self.deepSeekURL)
        webView.load(request)
    }

    /// Send a native command to the injected JavaScript layer.
    func sendCommand(_ command: OutgoingWebViewCommand) {
        let js: String
        switch command {
        case .setInput(let text):
            js = "window.DeepSeekContextNative.setInput(\"\(escapedJS(text))\");"
        case .appendInput(let text):
            js = "window.DeepSeekContextNative.appendInput(\"\(escapedJS(text))\");"
        case .injectSystem(let text):
            js = "window.DeepSeekContextNative.injectSystem(\"\(escapedJS(text))\");"
        case .getInput:
            js = "window.DeepSeekContextNative.getInput();"
        case .getOutput:
            js = "window.DeepSeekContextNative.getOutput();"
        }
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func injectBridgeScript() {
        let script = WKUserScript(
            source: InjectionScript.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        webView.configuration.userContentController.addUserScript(script)
    }

    private func escapedJS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

// MARK: - WKScriptMessageHandler

extension WebViewCoordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName,
              let body = message.body as? [String: Any] else {
            return
        }
        bridge.handleMessage(body)
    }
}

// MARK: - WebViewBridgeDelegate

extension WebViewCoordinator: WebViewBridgeDelegate {
    func bridge(_ bridge: WebViewBridge, sendCommand command: OutgoingWebViewCommand) {
        sendCommand(command)
    }

    func bridge(_ bridge: WebViewBridge, didReceiveCleanText text: String) {
        // ponytail: surface to UI layer when SwiftUI views land in Phase 7.
    }

    func bridge(_ bridge: WebViewBridge, didReceiveAction action: XMLTagAction) {
        // ponytail: tool/skill actions are queued for Phase 5/6 handlers.
    }

    func bridge(_ bridge: WebViewBridge, domHealthChanged healthy: Bool, missingSelector: String?) {
        // ponytail: degrade to pure mode when health fails repeatedly (Phase 9).
    }

    func bridge(_ bridge: WebViewBridge, didLog level: String, message: String) {
        // ponytail: wire to unified logger in Phase 9.
    }

    func bridge(_ bridge: WebViewBridge, didEncounterError error: String) {
        // ponytail: surface as a non-fatal web bridge error in Phase 9.
    }
}
