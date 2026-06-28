import SwiftUI

struct ConversationListView: View {
    @StateObject private var viewModel = ConversationListViewModel()
    @State private var newTitle: String = ""
    @State private var showNewConversation: Bool = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.conversations) { conversation in
                    NavigationLink(destination: ChatContainerView(conversation: conversation)) {
                        VStack(alignment: .leading) {
                            Text(conversation.title ?? "Untitled")
                                .font(.headline)
                            Text(conversation.updatedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Archive", role: .destructive) {
                            Task { await viewModel.archive(conversation) }
                        }
                        Button("Child") {
                            Task { await viewModel.createChildConversation(title: nil, parentId: conversation.id) }
                        }
                        .tint(.blue)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        Task { await viewModel.delete(viewModel.conversations[index]) }
                    }
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewConversation = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Conversation", isPresented: $showNewConversation) {
                TextField("Title", text: $newTitle)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    Task {
                        await viewModel.createConversation(title: newTitle.isEmpty ? nil : newTitle)
                        newTitle = ""
                    }
                }
            }
            .alert("Archive old conversations", isPresented: $viewModel.showArchiveAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Active conversation limit reached. Archive some old conversations to create new ones.")
            }
            .task {
                await viewModel.load()
            }
        }
    }
}
