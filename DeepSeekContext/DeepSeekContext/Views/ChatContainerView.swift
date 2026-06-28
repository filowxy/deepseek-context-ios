import SwiftUI

struct ChatContainerView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var showSkillSheet: Bool = false
    @State private var rejectFeedback: String = ""

    init(conversation: Conversation) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversation: conversation))
    }

    var body: some View {
        ZStack {
            ChatView(coordinator: viewModel.coordinator)
                .ignoresSafeArea(.keyboard)

            VStack {
                Spacer()
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .onTapGesture {
                            viewModel.errorMessage = nil
                        }
                }
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSkillSheet = true
                } label: {
                    Image(systemName: "bolt.fill")
                }
            }
        }
        .sheet(isPresented: $showSkillSheet) {
            SkillPickerView(conversationId: viewModel.conversation.id) { skill in
                viewModel.injectSkill(skill)
                showSkillSheet = false
            }
        }
        .overlay {
            if viewModel.showGlobalContextPrompt {
                GlobalContextPromptView(
                    content: viewModel.globalContextContent,
                    onAccept: viewModel.acceptGlobalContext,
                    onReject: viewModel.rejectGlobalContext
                )
            }
            if let suggestion = viewModel.pendingGlobalSuggestion {
                GlobalContextPromptView(
                    title: "AI Suggested Global Context",
                    content: suggestion.content + (suggestion.reason.map { "\n\nReason: \($0)" } ?? ""),
                    onAccept: viewModel.acceptGlobalSuggestion,
                    onReject: { viewModel.rejectGlobalSuggestion(feedback: rejectFeedback) }
                )
            }
        }
    }
}
