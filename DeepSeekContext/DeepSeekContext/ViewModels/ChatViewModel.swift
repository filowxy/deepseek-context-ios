import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var conversation: Conversation
    @Published var errorMessage: String?
    @Published var showGlobalContextPrompt: Bool = false
    @Published var globalContextContent: String = ""
    @Published var pendingGlobalSuggestion: XMLTagAction.GlobalSuggestPayload?

    let coordinator: WebViewCoordinator

    private let conversationManager = ConversationManager.shared
    private let globalContextDAO = GlobalContextDAO.shared

    init(conversation: Conversation, coordinator: WebViewCoordinator = WebViewCoordinator()) {
        self.conversation = conversation
        self.coordinator = coordinator
        self.coordinator.bridge.delegate = self
    }

    func onAppear() async {
        await coordinator.bridge.bindConversation(id: conversation.id)
        await loadGlobalContext()
    }

    func injectSkill(_ skill: Skill) {
        guard !skill.description.isEmpty else { return }
        coordinator.sendCommand(.injectSystem(text: "<system>\(skill.description)</system>"))
    }

    func acceptGlobalContext() {
        coordinator.sendCommand(.injectSystem(text: "<system>\(globalContextContent)</system>"))
        showGlobalContextPrompt = false
    }

    func rejectGlobalContext() {
        showGlobalContextPrompt = false
    }

    private func loadGlobalContext() async {
        do {
            let active = try await globalContextDAO.fetchActive()
            if let first = active.first {
                globalContextContent = first.content
                showGlobalContextPrompt = true
            }
        } catch {
            errorMessage = "global context load error: \(error)"
        }
    }
}

extension ChatViewModel: WebViewBridgeDelegate {
    func bridge(_ bridge: WebViewBridge, sendCommand command: OutgoingWebViewCommand) {
        coordinator.sendCommand(command)
    }

    func bridge(_ bridge: WebViewBridge, didReceiveCleanText text: String) {
        // ponytail: display cleaned AI text in native UI when split-view mode lands.
    }

    func bridge(_ bridge: WebViewBridge, didReceiveAction action: XMLTagAction) {
        if case .globalSuggest(let payload) = action {
            pendingGlobalSuggestion = payload
        }
    }

    func acceptGlobalSuggestion() {
        guard let suggestion = pendingGlobalSuggestion else { return }
        Task {
            do {
                _ = try await globalContextDAO.insertSuggestion(
                    content: suggestion.content,
                    reason: suggestion.reason,
                    contentHash: nil,
                    status: .accepted
                )
                coordinator.sendCommand(.injectSystem(text: "<system>\(suggestion.content)</system>"))
                pendingGlobalSuggestion = nil
            } catch {
                errorMessage = "suggestion log error: \(error)"
            }
        }
    }

    func rejectGlobalSuggestion(feedback: String? = nil) {
        guard let suggestion = pendingGlobalSuggestion else { return }
        Task {
            do {
                _ = try await globalContextDAO.insertSuggestion(
                    content: suggestion.content,
                    reason: suggestion.reason,
                    contentHash: nil,
                    status: .rejected,
                    rejectionFeedback: feedback
                )
                pendingGlobalSuggestion = nil
            } catch {
                errorMessage = "suggestion log error: \(error)"
            }
        }
    }

    func bridge(_ bridge: WebViewBridge, domHealthChanged healthy: Bool, missingSelector: String?) {
        if !healthy {
            errorMessage = "WebView health check failed: \(missingSelector ?? "unknown")"
        }
    }

    func bridge(_ bridge: WebViewBridge, didLog level: String, message: String) {
        // ponytail: wire to unified logger in Phase 9.
    }

    func bridge(_ bridge: WebViewBridge, didEncounterError error: String) {
        errorMessage = error
    }
}
