import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List(viewModel.conversations) { conversation in
                HStack {
                    VStack(alignment: .leading) {
                        Text(conversation.title ?? "Untitled")
                            .font(.headline)
                        Text("Counter correction")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField("Count", value: Binding(
                        get: { viewModel.counts[conversation.id] ?? 0 },
                        set: { newValue in
                            viewModel.counts[conversation.id] = newValue
                        }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        Task {
                            await viewModel.updateCount(
                                for: conversation.id,
                                count: viewModel.counts[conversation.id] ?? 0
                            )
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                await viewModel.load()
            }
        }
    }
}
