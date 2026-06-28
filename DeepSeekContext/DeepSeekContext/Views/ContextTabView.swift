import SwiftUI

struct ContextTabView: View {
    @StateObject private var viewModel = ContextTabViewModel()
    @State private var selectedConversationId: String?

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Conversation", selection: $selectedConversationId) {
                    Text("Select conversation").tag(String?.none)
                    ForEach(viewModel.conversations) { conversation in
                        Text(conversation.title ?? "Untitled").tag(conversation.id as String?)
                    }
                }
                .pickerStyle(.menu)
                .padding()

                if let id = selectedConversationId {
                    ContextManagementView(conversationId: id)
                } else {
                    Spacer()
                    Text("Select a conversation to manage context")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .navigationTitle("Context")
            .task {
                await viewModel.load()
            }
        }
    }
}

@MainActor
final class ContextTabViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []

    private let conversationDAO = ConversationDAO.shared

    func load() async {
        do {
            conversations = try await conversationDAO.fetchAll()
        } catch {
            conversations = []
        }
    }
}
