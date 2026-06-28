import Foundation
import SwiftUI

@MainActor
final class ConversationListViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var errorMessage: String?
    @Published var showArchiveAlert: Bool = false

    private let manager = ConversationManager.shared

    func load() async {
        do {
            conversations = try await manager.activeConversations()
        } catch {
            errorMessage = "load error: \(error)"
        }
    }

    func createConversation(title: String?) async {
        do {
            if try await manager.isAtSoftLimit() {
                showArchiveAlert = true
                return
            }
            _ = try await manager.createConversation(title: title)
            await load()
        } catch {
            errorMessage = "create error: \(error)"
        }
    }

    func createChildConversation(title: String?, parentId: String) async {
        do {
            _ = try await manager.createChildConversation(title: title, parentId: parentId)
            await load()
        } catch {
            errorMessage = "child error: \(error)"
        }
    }

    func archive(_ conversation: Conversation) async {
        do {
            try await manager.archiveConversation(id: conversation.id)
            await load()
        } catch {
            errorMessage = "archive error: \(error)"
        }
    }

    func delete(_ conversation: Conversation) async {
        do {
            try await manager.deleteConversation(id: conversation.id)
            await load()
        } catch {
            errorMessage = "delete error: \(error)"
        }
    }
}
