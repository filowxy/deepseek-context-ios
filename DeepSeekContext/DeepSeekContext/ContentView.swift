import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ConversationListView()
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }

            ContextTabView()
                .tabItem {
                    Label("Context", systemImage: "bookmark.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    ContentView()
}
