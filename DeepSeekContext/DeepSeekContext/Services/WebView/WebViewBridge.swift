import Foundation
import WebKit

/// Receives messages from the injected JavaScript and dispatches to native engines.
final class WebViewBridge: NSObject {
    weak var delegate: WebViewBridgeDelegate?

    private(set) var conversationId: String?
    private(set) var messageIndex: Int = 0
    private(set) var roundCounter: Int64 = 0

    private let contextEngine = ContextEngine.shared
    private let recallEngine = RecallEngine.shared
    private let toolExecutor: ToolExecutor

    init(toolExecutor: ToolExecutor = .shared) {
        self.toolExecutor = toolExecutor
    }

    /// Bind the bridge to a conversation and reset per-conversation state.
    func bindConversation(id: String) async {
        conversationId = id
        messageIndex = 0
        roundCounter = 0
    }

    /// Advance to the next message round and notify the web page.
    func startNewRound() {
        messageIndex += 1
        let systemText = "<system>当前对话轮次: \(messageIndex), 本轮标记序号从 1 开始</system>"
        delegate?.bridge(self, sendCommand: .injectSystem(text: systemText))
    }

    /// Handle a raw message dictionary from JavaScript.
    func handleMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        let payload = body["payload"] as? [String: Any] ?? [:]

        switch type {
        case "finalReply":
            if let text = payload["text"] as? String {
                handleFinalReply(text)
            }
        case "sendStarted":
            startNewRound()
        case "domHealth":
            let healthy = payload["healthy"] as? Bool ?? false
            let selector = payload["missingSelector"] as? String
            delegate?.bridge(self, domHealthChanged: healthy, missingSelector: selector)
        case "log":
            let level = payload["level"] as? String ?? "info"
            let message = payload["message"] as? String ?? ""
            delegate?.bridge(self, didLog: level, message: message)
        case "error":
            let message = body["payload"] as? String ?? body.description
            delegate?.bridge(self, didEncounterError: message)
        default:
            break
        }
    }

    /// Parse XML tags in the AI final reply and execute corresponding native actions.
    func handleFinalReply(_ text: String) {
        let actions = XMLTagParser.parse(text)
        let cleanText = XMLTagParser.stripTags(text)

        guard !actions.isEmpty else { return }

        Task {
            let immediate = actions.filter { !isToolAction($0) && !isDelegateAction($0) }
            let tools = actions.filter(isToolAction)
            let delegateActions = actions.filter(isDelegateAction)

            for action in immediate {
                await executeImmediate(action)
            }

            if !tools.isEmpty {
                let (results, skipped) = await toolExecutor.executeBatch(tools)
                injectToolResults(results, skipped: skipped)
            }

            for action in delegateActions {
                delegate?.bridge(self, didReceiveAction: action)
            }

            roundCounter += 1
            if !cleanText.isEmpty {
                delegate?.bridge(self, didReceiveCleanText: cleanText)
            }
        }
    }

    // MARK: - Immediate actions

    private func executeImmediate(_ action: XMLTagAction) async {
        guard let conversationId else {
            delegate?.bridge(self, didEncounterError: "no active conversation")
            return
        }

        switch action {
        case .mark(let payload):
            let parts = payload.idemKey.split(separator: "_")
            guard parts.count >= 4,
                  let messageIdx = Int(parts[1]),
                  let sequence = Int(parts[3]) else {
                delegate?.bridge(self, didEncounterError: "invalid idem_key \(payload.idemKey)")
                return
            }
            do {
                _ = try await contextEngine.createMark(
                    type: payload.type,
                    lev: payload.lev,
                    content: payload.content,
                    tags: payload.tags,
                    conversationId: conversationId,
                    messageIndex: messageIdx,
                    sequence: sequence,
                    createdCounter: roundCounter
                )
            } catch {
                delegate?.bridge(self, didEncounterError: "mark error: \(error)")
            }

        case .delete(let payload):
            do {
                try await contextEngine.deleteMark(id: payload.markId)
            } catch {
                delegate?.bridge(self, didEncounterError: "delete error: \(error)")
            }

        case .recover(let payload):
            do {
                try await contextEngine.recoverMark(id: payload.markId)
            } catch {
                delegate?.bridge(self, didEncounterError: "recover error: \(error)")
            }

        case .recall(let payload):
            do {
                let result = try await recallEngine.recall(
                    query: payload.query,
                    scope: payload.scope,
                    conversationId: conversationId
                )
                let json = encodeRecallResult(result)
                delegate?.bridge(self, sendCommand: .injectSystem(text: "<recall-result>\(json)</recall-result>"))
            } catch {
                delegate?.bridge(self, didEncounterError: "recall error: \(error)")
            }

        case .all(let payload):
            if let result = recallEngine.result(bySearchId: payload.searchId) {
                let json = encodeRecallResult(result)
                delegate?.bridge(self, sendCommand: .injectSystem(text: "<recall-result>\(json)</recall-result>"))
            } else {
                delegate?.bridge(self, didEncounterError: "invalid searchinfo \(payload.searchId)")
            }

        default:
            break
        }
    }

    // MARK: - Tool results

    private func injectToolResults(_ results: [ToolResult], skipped: [String]) {
        for result in results {
            let text: String
            switch result {
            case .search(let searchResult):
                text = format(searchResult: searchResult)
            case .browse(let browseResult):
                text = format(browseResult: browseResult)
            case .failed(let message):
                text = "<tool-error>\(message)</tool-error>"
            }
            delegate?.bridge(self, sendCommand: .injectSystem(text: text))
        }

        if !skipped.isEmpty {
            let notice = "以下工具调用因超时未执行: \(skipped.joined(separator: ", "))"
            delegate?.bridge(self, sendCommand: .injectSystem(text: "<system>\(notice)</system>"))
        }
    }

    private func format(searchResult: SearchResult) -> String {
        let items = searchResult.results.map { "- [\($0.title)](\($0.url))\n\($0.snippet)" }.joined(separator: "\n\n")
        return "<search-result>\n查询: \(searchResult.query)\n找到约 \(searchResult.totalEstimated) 条结果\n\n\(items)\n</search-result>"
    }

    private func format(browseResult: BrowseResult) -> String {
        let titleLine = browseResult.title.map { "标题: \($0)\n" } ?? ""
        return "<browse-result>\n\(titleLine)\(browseResult.content)\n</browse-result>"
    }

    // MARK: - Helpers

    private func isToolAction(_ action: XMLTagAction) -> Bool {
        switch action {
        case .search, .open: return true
        default: return false
        }
    }

    private func isDelegateAction(_ action: XMLTagAction) -> Bool {
        switch action {
        case .callSkill, .globalSuggest: return true
        default: return false
        }
    }

    private func encodeRecallResult(_ result: RecallResult) -> String {
        let formatter = ISO8601DateFormatter()
        let items = result.items.map { item in
            [
                "mark_id": item.markId,
                "lev": item.lev,
                "content": item.content,
                "tags": item.tags,
                "created_at": formatter.string(from: item.createdAt)
            ] as [String: Any]
        }
        let dict: [String: Any] = [
            "items": items,
            "total": result.total,
            "truncated": result.truncated,
            "search_id": result.searchId,
            "message": result.message
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

// MARK: - Delegate

protocol WebViewBridgeDelegate: AnyObject {
    func bridge(_ bridge: WebViewBridge, sendCommand command: OutgoingWebViewCommand)
    func bridge(_ bridge: WebViewBridge, didReceiveCleanText text: String)
    func bridge(_ bridge: WebViewBridge, didReceiveAction action: XMLTagAction)
    func bridge(_ bridge: WebViewBridge, domHealthChanged healthy: Bool, missingSelector: String?)
    func bridge(_ bridge: WebViewBridge, didLog level: String, message: String)
    func bridge(_ bridge: WebViewBridge, didEncounterError error: String)
}
