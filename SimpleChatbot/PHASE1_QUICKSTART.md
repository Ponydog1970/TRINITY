# 🚀 Phase 1 Quick Start: Perplexity API Integration

Schnellanleitung um echte KI in 30 Minuten zu integrieren!

---

## Schritt 1: API Key besorgen (5 Min)

1. Gehen Sie zu: https://www.perplexity.ai/settings/api
2. Account erstellen (falls nicht vorhanden)
3. "Generate API Key" klicken
4. Key kopieren (sieht aus wie: `pplx-...`)

**Wichtig:** API Key ist geheim! Nie in Git committen!

---

## Schritt 2: Projekt-Struktur erstellen (5 Min)

### In Xcode oder Cursor:

```bash
# Neue Ordner erstellen
mkdir -p SimpleChatbot/SimpleChatbot/Config
mkdir -p SimpleChatbot/SimpleChatbot/Network
```

### Oder in Terminal:
```bash
cd SimpleChatbot
mkdir -p SimpleChatbot/{Config,Network}
```

---

## Schritt 3: API Configuration (5 Min)

### Datei: `SimpleChatbot/Config/APIConfig.swift`

```swift
import Foundation

/// API Configuration
/// WICHTIG: Niemals API Keys in Git committen!
struct APIConfig {
    // TODO: Ersetzen Sie mit Ihrem API Key
    // Am besten aus Environment Variable oder Keychain laden
    static var perplexityAPIKey: String {
        // Option 1: Aus Environment
        if let key = ProcessInfo.processInfo.environment["PERPLEXITY_API_KEY"] {
            return key
        }

        // Option 2: Aus Info.plist (nicht in Git!)
        if let key = Bundle.main.object(forInfoDictionaryKey: "PerplexityAPIKey") as? String {
            return key
        }

        // Option 3: Hardcoded (nur für Testing, NICHT in Production!)
        // return "pplx-YOUR-KEY-HERE"

        fatalError("⚠️ Perplexity API Key nicht gefunden!")
    }

    static let baseURL = "https://api.perplexity.ai"
    static let model = "llama-3.1-sonar-small-128k-online"

    // Alternative Modelle:
    // "llama-3.1-sonar-large-128k-online" - Genauer
    // "llama-3.1-sonar-huge-128k-online" - Beste Qualität
}
```

### Sicher API Key speichern:

**Für Development - Xcode Scheme:**
1. Xcode: Product → Scheme → Edit Scheme
2. Run → Arguments → Environment Variables
3. Name: `PERPLEXITY_API_KEY`, Value: `pplx-...`

**Für Production - Keychain:**
```swift
import Security

class KeychainManager {
    static func save(key: String, value: String) {
        // Keychain API
    }

    static func retrieve(key: String) -> String? {
        // Keychain API
    }
}
```

---

## Schritt 4: Network Manager (10 Min)

### Datei: `SimpleChatbot/Network/NetworkManager.swift`

```swift
import Foundation

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültige URL"
        case .invalidResponse: return "Ungültige Server-Antwort"
        case .apiError(let message): return "API Fehler: \(message)"
        case .decodingError: return "Fehler beim Verarbeiten der Antwort"
        }
    }
}

class NetworkManager {
    static let shared = NetworkManager()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    func post<T: Decodable>(
        url: URL,
        body: [String: Any],
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Headers hinzufügen
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Body als JSON
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Request ausführen
        let (data, response) = try await session.data(for: request)

        // Response validieren
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorMessage = try? JSONDecoder().decode(
                ErrorResponse.self,
                from: data
            ) {
                throw NetworkError.apiError(errorMessage.error?.message ?? "Unbekannter Fehler")
            }
            throw NetworkError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Decode Response
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("❌ Decode Error:", error)
            throw NetworkError.decodingError
        }
    }

    // Streaming Support (für später)
    func stream(
        url: URL,
        body: [String: Any],
        headers: [String: String] = [:]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // TODO: Implement Server-Sent Events (SSE) streaming
                continuation.finish()
            }
        }
    }
}

// Error Response Model
private struct ErrorResponse: Decodable {
    struct ErrorDetail: Decodable {
        let message: String
    }
    let error: ErrorDetail?
}
```

---

## Schritt 5: Perplexity Service (10 Min)

### Datei: `SimpleChatbot/Services/PerplexityService.swift`

```swift
import Foundation
import SwiftUI

/// Perplexity AI Service
/// Dokumentation: https://docs.perplexity.ai/
@MainActor
class PerplexityService: ObservableObject {
    @Published var isProcessing = false

    private let networkManager = NetworkManager.shared

    // MARK: - API Models

    struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double?
        let max_tokens: Int?
        let stream: Bool?

        struct ChatMessage: Encodable {
            let role: String  // "system", "user", "assistant"
            let content: String
        }
    }

    struct ChatResponse: Decodable {
        let id: String
        let model: String
        let choices: [Choice]
        let usage: Usage?

        struct Choice: Decodable {
            let message: Message
            let finish_reason: String?

            struct Message: Decodable {
                let role: String
                let content: String
            }
        }

        struct Usage: Decodable {
            let prompt_tokens: Int
            let completion_tokens: Int
            let total_tokens: Int
        }
    }

    // MARK: - Public Methods

    /// Generiert eine Antwort basierend auf Chat-Historie
    func generateResponse(
        for userMessage: String,
        chatHistory: [Message] = []
    ) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        // Build Messages Array
        var messages: [ChatRequest.ChatMessage] = []

        // System Prompt (Optional)
        messages.append(.init(
            role: "system",
            content: """
            Du bist ein hilfreicher, freundlicher KI-Assistent.
            Antworte präzise und auf Deutsch.
            """
        ))

        // Chat History (optional: nur letzte N Nachrichten)
        let recentHistory = chatHistory.suffix(10)
        for msg in recentHistory {
            messages.append(.init(
                role: msg.isUser ? "user" : "assistant",
                content: msg.text
            ))
        }

        // Aktuelle User-Nachricht
        messages.append(.init(role: "user", content: userMessage))

        // Request Body
        let requestBody: [String: Any] = [
            "model": APIConfig.model,
            "messages": messages.map { msg in
                ["role": msg.role, "content": msg.content]
            },
            "temperature": 0.7,
            "max_tokens": 1024,
            "stream": false
        ]

        // Headers
        let headers = [
            "Authorization": "Bearer \(APIConfig.perplexityAPIKey)"
        ]

        // API Call
        guard let url = URL(string: "\(APIConfig.baseURL)/chat/completions") else {
            throw NetworkError.invalidURL
        }

        let response: ChatResponse = try await networkManager.post(
            url: url,
            body: requestBody,
            headers: headers
        )

        // Extract response text
        guard let firstChoice = response.choices.first else {
            throw NetworkError.apiError("Keine Antwort erhalten")
        }

        // Optional: Log Usage
        if let usage = response.usage {
            print("📊 Token Usage: \(usage.total_tokens) (prompt: \(usage.prompt_tokens), completion: \(usage.completion_tokens))")
        }

        return firstChoice.message.content
    }

    /// Convenience Methode ohne Historie
    func quickResponse(for message: String) async throws -> String {
        return try await generateResponse(for: message, chatHistory: [])
    }
}
```

---

## Schritt 6: ChatView Integration (5 Min)

### Datei: `SimpleChatbot/Views/ChatView.swift` - Update

**Ersetzen Sie den `sendMessage()` Block:**

```swift
private func sendMessage() {
    guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

    // User-Nachricht hinzufügen
    let userMessage = Message(text: messageText, isUser: true)
    messages.append(userMessage)

    let currentMessage = messageText
    messageText = ""

    // AI-Antwort generieren - NEU: Mit Perplexity!
    Task {
        do {
            // ✨ Perplexity API verwenden
            let perplexityService = PerplexityService()
            let response = try await perplexityService.generateResponse(
                for: currentMessage,
                chatHistory: messages.filter { !$0.isUser }.suffix(5).map { $0 }
            )

            await MainActor.run {
                messages.append(Message(text: response, isUser: false))
            }
        } catch {
            // Fehlerbehandlung
            await MainActor.run {
                let errorMessage = "❌ Fehler: \(error.localizedDescription)"
                messages.append(Message(text: errorMessage, isUser: false))
            }
        }
    }
}
```

**Oder: Ersetzen Sie den gesamten Service:**

```swift
// In SimpleChatbotApp.swift
@main
struct SimpleChatbotApp: App {
    @StateObject private var perplexityService = PerplexityService() // ✨ NEU

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(perplexityService) // ✨ NEU
        }
    }
}

// In ChatView.swift
struct ChatView: View {
    @EnvironmentObject var perplexityService: PerplexityService // ✨ NEU

    // ...

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let userMessage = Message(text: messageText, isUser: true)
        messages.append(userMessage)

        let currentMessage = messageText
        messageText = ""

        Task {
            do {
                let response = try await perplexityService.generateResponse(
                    for: currentMessage,
                    chatHistory: messages
                )

                await MainActor.run {
                    messages.append(Message(text: response, isUser: false))
                }
            } catch {
                await MainActor.run {
                    messages.append(Message(
                        text: "❌ \(error.localizedDescription)",
                        isUser: false
                    ))
                }
            }
        }
    }
}
```

---

## Schritt 7: Testen! (5 Min)

### In Xcode:

1. **API Key setzen:**
   - Product → Scheme → Edit Scheme
   - Environment Variable: `PERPLEXITY_API_KEY` = Ihr Key

2. **Build & Run:**
   ```
   ⌘R
   ```

3. **Testen Sie:**
   - "Hallo, wie geht's?"
   - "Was ist SwiftUI?"
   - "Erkläre mir RAG in einfachen Worten"

### Erwartetes Verhalten:

✅ User-Nachricht erscheint sofort
✅ Kurze Pause (API-Call)
✅ Bot-Antwort erscheint
✅ Intelligente, kontextuelle Antworten!

---

## 🎉 Geschafft!

Sie haben jetzt eine funktionierende KI-Chat-App mit Perplexity API!

### Was Sie erreicht haben:

- ✅ Echte KI-Integration
- ✅ API-Kommunikation
- ✅ Error Handling
- ✅ Sicherer Key-Management
- ✅ Chat-Historie Support

### Nächste Schritte:

**Sofort verbessern:**
1. Loading Indicator während API-Call
2. Retry bei Fehlern
3. Token Counter

**Siehe ROADMAP.md für:**
- Phase 2: Schönes UI
- Phase 3: RAG Speicher
- Phase 4: Erweiterte Features

---

## 🐛 Troubleshooting

### "API Key nicht gefunden"
→ Environment Variable `PERPLEXITY_API_KEY` in Xcode Scheme setzen

### "Invalid API Key"
→ Prüfen Sie, ob Key richtig kopiert wurde (inkl. `pplx-` prefix)

### "Network Error"
→ Internet-Verbindung prüfen, Firewall-Einstellungen

### "Decoding Error"
→ API Response Format hat sich geändert - Response loggen:
```swift
print("Response:", String(data: data, encoding: .utf8) ?? "")
```

### "Rate Limit Exceeded"
→ Zu viele Requests - warten Sie 60 Sekunden oder upgraden Sie Plan

---

## 💰 Kosten

**Perplexity Pricing (ca.):**
- Sonar Small: ~$0.20 per 1M tokens
- Sonar Large: ~$1.00 per 1M tokens
- Sonar Huge: ~$5.00 per 1M tokens

**Beispiel:** 1000 Nachrichten à 500 tokens = ~$0.10

**Tipp:** Starten Sie mit dem Small Model!

---

## 📚 Ressourcen

- **Perplexity Docs:** https://docs.perplexity.ai/
- **API Playground:** https://www.perplexity.ai/playground
- **Pricing:** https://docs.perplexity.ai/docs/pricing

---

**Los geht's!** 🚀 In 30 Minuten haben Sie echte KI in Ihrer App!
