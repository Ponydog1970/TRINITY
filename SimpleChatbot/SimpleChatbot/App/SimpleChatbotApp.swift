import SwiftUI

@main
struct SimpleChatbotApp: App {
    @StateObject private var chatService = LocalAIService()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(chatService)
        }
    }
}
