import Foundation
import SwiftUI

@MainActor
final class ContextManagementViewModel: ObservableObject {
    @Published var marks: [ContextMark] = []
    @Published var searchQuery: String = ""
    @Published var errorMessage: String?

    private let markDAO = ContextMarkDAO.shared

    var filteredMarks: [ContextMark] {
        guard !searchQuery.isEmpty else { return marks }
        return marks.filter {
            $0.content.localizedCaseInsensitiveContains(searchQuery) ||
            $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchQuery) })
        }
    }

    func load(for conversationId: String) async {
        do {
            marks = try await markDAO.fetch(byConversationId: conversationId, includeDeleted: false)
        } catch {
            errorMessage = "load error: \(error)"
        }
    }

    func delete(_ mark: ContextMark) async {
        do {
            try await markDAO.softDelete(id: mark.id)
            await load(for: mark.conversationId)
        } catch {
            errorMessage = "delete error: \(error)"
        }
    }
}
