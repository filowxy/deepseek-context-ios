import SwiftUI

struct ContextManagementView: View {
    let conversationId: String
    @StateObject private var viewModel = ContextManagementViewModel()

    var body: some View {
        List(viewModel.filteredMarks) { mark in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(mark.markId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(mark.type.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
                Text(mark.content)
                    .font(.body)
                if !mark.tags.isEmpty {
                    Text(mark.tags.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .swipeActions {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.delete(mark) }
                }
            }
        }
        .searchable(text: $viewModel.searchQuery, prompt: "Search marks")
        .navigationTitle("Context")
        .task {
            await viewModel.load(for: conversationId)
        }
    }
}
