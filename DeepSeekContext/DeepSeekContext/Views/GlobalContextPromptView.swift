import SwiftUI

struct GlobalContextPromptView: View {
    var title: String = "Global Context"
    let content: String
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
            Text(content)
                .font(.body)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Ignore", role: .cancel, action: onReject)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Inject", action: onAccept)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding(24)
    }
}
