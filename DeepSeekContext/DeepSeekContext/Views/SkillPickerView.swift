import SwiftUI

struct SkillPickerView: View {
    let conversationId: String
    let onSelect: (Skill) -> Void
    @StateObject private var viewModel = SkillPickerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(viewModel.skills) { skill in
                Button {
                    onSelect(skill)
                } label: {
                    VStack(alignment: .leading) {
                        Text(skill.name)
                            .font(.headline)
                        Text(skill.whentouse)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Select Skill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await viewModel.load(for: conversationId)
            }
        }
    }
}

@MainActor
final class SkillPickerViewModel: ObservableObject {
    @Published var skills: [Skill] = []

    private let skillManager = SkillManager.shared

    func load(for conversationId: String) async {
        do {
            skills = try await skillManager.loadSkills(for: conversationId)
        } catch {
            skills = []
        }
    }
}
