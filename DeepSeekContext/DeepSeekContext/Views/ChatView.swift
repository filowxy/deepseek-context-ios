import SwiftUI
import WebKit

/// SwiftUI wrapper for the DeepSeek WebView coordinator.
struct ChatView: UIViewRepresentable {
    let coordinator: WebViewCoordinator

    func makeUIView(context: Context) -> WKWebView {
        coordinator.loadDeepSeek()
        return coordinator.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
