import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var counts: [String: Int64] = [:]
    @Published var errorMessage: String?

    private let conversationDAO = ConversationDAO.shared

    func load() async {
        do {
            conversations = try await conversationDAO.fetchAll()
            counts = [:]
            for conversation in conversations {
                counts[conversation.id] = try await conversationDAO.getCount(for: conversation.id)
            }
        } catch {
            errorMessage = "load error: \(error)"
        }
    }

    func updateCount(for conversationId: String, count: Int64) async {
        do {
            try await conversationDAO.setCount(for: conversationId, count: count)
            counts[conversationId] = count
        } catch {
            errorMessage = "update error: \(error)"
        }
    }
}
