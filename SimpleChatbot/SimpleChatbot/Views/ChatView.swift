import SwiftUI

struct ChatView: View {
    @EnvironmentObject var chatService: LocalAIService
    @State private var messageText: String = ""
    @State private var messages: [Message] = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()

            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input Field
            InputField(
                messageText: $messageText,
                isInputFocused: $isInputFocused,
                onSend: sendMessage
            )
        }
        .onAppear {
            // Begrüßungsnachricht
            messages.append(Message(
                text: "Hallo! Ich bin dein lokaler AI-Chatbot. Wie kann ich dir helfen?",
                isUser: false
            ))
        }
    }

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        // User-Nachricht hinzufügen
        let userMessage = Message(text: messageText, isUser: true)
        messages.append(userMessage)

        let currentMessage = messageText
        messageText = ""

        // AI-Antwort generieren
        Task {
            let response = await chatService.generateResponse(for: currentMessage)
            await MainActor.run {
                messages.append(Message(text: response, isUser: false))
            }
        }
    }
}

// MARK: - Subviews

struct HeaderView: View {
    var body: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Simple Chatbot")
                    .font(.headline)
                Text("Lokale KI")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(12)
                    .background(message.isUser ? Color.blue : Color(.systemGray5))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(16)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
    }
}

struct InputField: View {
    @Binding var messageText: String
    var isInputFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Nachricht eingeben...", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .focused(isInputFocused)
                .lineLimit(1...5)
                .onSubmit(onSend)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(messageText.isEmpty ? .gray : .blue)
            }
            .disabled(messageText.isEmpty)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

#Preview {
    ChatView()
        .environmentObject(LocalAIService())
}
