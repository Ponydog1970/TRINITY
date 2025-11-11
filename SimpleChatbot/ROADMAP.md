# 🚀 SimpleChatbot Ausbau-Roadmap

Von einfachem Chatbot zu einer vollwertigen KI-App mit Perplexity API und RAG-Speicher.

---

## 📍 Phase 0: Basis (✅ ERLEDIGT)

**Status:** ✅ Abgeschlossen

### Was wir haben:
- ✅ SwiftUI Chat-Interface
- ✅ Message-Modell mit Historie
- ✅ Basis-Service-Struktur
- ✅ Ordner-Organisation (Xcode + Cursor kompatibel)
- ✅ Regelbasierte Antworten

### Dateien:
- `SimpleChatbotApp.swift` - App Entry Point
- `ChatView.swift` - UI
- `Message.swift` - Datenmodell
- `LocalAIService.swift` - Service-Layer

---

## 🎯 Phase 1: Perplexity API Integration

**Ziel:** Echte KI-Antworten über Perplexity API

### 1.1 API-Konfiguration

**Neue Dateien:**
```
SimpleChatbot/SimpleChatbot/
├── Config/
│   └── APIConfig.swift          # API Keys & Endpoints
└── Services/
    ├── PerplexityService.swift  # API Client
    └── NetworkManager.swift     # HTTP Client
```

**API Setup:**
```swift
// APIConfig.swift
struct APIConfig {
    static let perplexityAPIKey = "pplx-..."
    static let baseURL = "https://api.perplexity.ai"
    static let model = "llama-3.1-sonar-small-128k-online" // oder andere
}
```

**Perplexity API Modelle:**
- `llama-3.1-sonar-small-128k-online` - Schnell, mit Internet-Zugang
- `llama-3.1-sonar-large-128k-online` - Genauer, mit Internet-Zugang
- `llama-3.1-sonar-huge-128k-online` - Beste Qualität

### 1.2 PerplexityService implementieren

```swift
// PerplexityService.swift
class PerplexityService: ObservableObject {
    @Published var isLoading = false

    func chat(messages: [Message]) async throws -> String {
        // POST zu https://api.perplexity.ai/chat/completions
        // Format: OpenAI-kompatibel
    }

    func streamChat(messages: [Message]) async throws -> AsyncStream<String> {
        // Streaming für Echtzeit-Antworten
    }
}
```

### 1.3 UI für Streaming-Antworten

**Erweiterungen:**
- Typing-Indikator während API-Call
- Streaming Text (Wort-für-Wort erscheinend)
- Fehlerbehandlung bei API-Problemen
- Retry-Logik

**Geschätzte Zeit:** 4-6 Stunden

---

## 🎨 Phase 2: Schönes UI/UX

**Ziel:** Modernes, ansprechendes Design wie ChatGPT/Perplexity

### 2.1 Enhanced Message Bubbles

**Features:**
- [ ] Markdown-Rendering (Code-Blöcke, Listen, Links)
- [ ] Syntax-Highlighting für Code
- [ ] Copy-Button für Nachrichten
- [ ] Regenerate-Button für Bot-Antworten
- [ ] Nachrichten-Feedback (👍/👎)

**Neue Dependencies:**
```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
    .package(url: "https://github.com/raspu/Highlightr", from: "2.1.0")
]
```

### 2.2 Moderne Chat-Features

**Typing Indicator:**
```swift
struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
    }
}
```

**Smooth Animations:**
- Nachrichten erscheinen mit Fade-In
- Smooth Scroll zu neuen Nachrichten
- Haptic Feedback bei Senden

### 2.3 Theming & Customization

**Theme System:**
```swift
// Theme.swift
enum ChatTheme {
    case light, dark, system
    case custom(primary: Color, secondary: Color, background: Color)
}

class ThemeManager: ObservableObject {
    @Published var currentTheme: ChatTheme = .system
}
```

**Dark Mode Optimierung:**
- Perfekte Farben für Dark/Light Mode
- Smooth Transitions
- System Theme Respekt

### 2.4 UI Components

**Neue Views:**
```
Views/
├── ChatView.swift              # Hauptview
├── Components/
│   ├── MessageBubble.swift     # Enhanced Bubble
│   ├── TypingIndicator.swift   # Typing Animation
│   ├── InputField.swift        # Erweitertes Input
│   └── MarkdownView.swift      # Markdown Rendering
└── Settings/
    └── SettingsView.swift      # Einstellungen
```

**Features:**
- Voice Input Button (Speech Recognition)
- Attachment Button (Bilder, PDFs)
- Quick Actions (Vorgeschlagene Prompts)

**Geschätzte Zeit:** 8-10 Stunden

---

## 🧠 Phase 3: RAG (Retrieval-Augmented Generation) Speicher

**Ziel:** Kontext aus vorherigen Chats und Dokumenten nutzen

### 3.1 Vector Database Setup

**Architektur:**
```
SimpleChatbot/SimpleChatbot/
├── Database/
│   ├── VectorStore.swift        # Vector DB Interface
│   ├── EmbeddingService.swift   # Text → Embeddings
│   └── ChromaDBClient.swift     # ChromaDB Client (oder Qdrant)
├── RAG/
│   ├── RAGManager.swift         # RAG Orchestrator
│   ├── DocumentProcessor.swift  # Dokumente verarbeiten
│   └── ContextBuilder.swift     # Kontext für Prompts
└── Models/
    ├── Document.swift           # Dokument-Modell
    └── Embedding.swift          # Embedding-Modell
```

### 3.2 Embedding Service

**Optionen:**

**Option A: OpenAI Embeddings**
```swift
class EmbeddingService {
    func generateEmbedding(text: String) async throws -> [Float] {
        // OpenAI text-embedding-3-small
        // 1536 Dimensionen
    }
}
```

**Option B: Lokale Embeddings (CoreML)**
```swift
class LocalEmbeddingService {
    private let model: SentenceEmbeddingModel

    func generateEmbedding(text: String) -> [Float] {
        // MobileBERT oder DistilBERT
        // Läuft auf Gerät
    }
}
```

### 3.3 Vector Store Integration

**ChromaDB (Cloud/Local):**
```swift
class ChromaDBClient {
    func addDocuments(_ documents: [Document]) async throws
    func search(query: String, limit: Int) async throws -> [Document]
    func deleteCollection() async throws
}
```

**Alternative: Lokale SQLite mit VSS Extension:**
```swift
// Für vollständig lokale Lösung
class LocalVectorStore {
    private let db: SQLite.Connection

    func initialize() throws {
        // sqlite-vss Extension laden
    }

    func addVector(id: String, embedding: [Float], metadata: [String: Any]) throws
    func searchSimilar(embedding: [Float], limit: Int) throws -> [Result]
}
```

### 3.4 RAG Pipeline

```swift
class RAGManager {
    let vectorStore: VectorStore
    let embeddingService: EmbeddingService
    let perplexityService: PerplexityService

    func answerWithContext(query: String, chatHistory: [Message]) async throws -> String {
        // 1. Query → Embedding
        let queryEmbedding = try await embeddingService.generateEmbedding(text: query)

        // 2. Ähnliche Dokumente finden
        let relevantDocs = try await vectorStore.search(embedding: queryEmbedding, limit: 3)

        // 3. Kontext aufbauen
        let context = buildContext(docs: relevantDocs, history: chatHistory)

        // 4. Prompt mit Kontext erstellen
        let enhancedPrompt = """
        Context:
        \(context)

        User Question: \(query)

        Answer based on the context above. If the context doesn't contain relevant information, say so.
        """

        // 5. Perplexity API mit erweitertem Prompt
        return try await perplexityService.chat(prompt: enhancedPrompt)
    }
}
```

### 3.5 Document Management

**UI für RAG:**
```
Views/
├── DocumentsView.swift          # Dokumente verwalten
├── DocumentUploadView.swift     # Upload Interface
└── DocumentPreviewView.swift    # Preview & Chunks
```

**Features:**
- PDF Upload & OCR
- Text-Dateien importieren
- Web-Links scrapen
- Automatisches Chunking
- Chunk-Preview

**Geschätzte Zeit:** 12-15 Stunden

---

## 🔧 Phase 4: Erweiterte Features

### 4.1 Multi-Konversations-Management

```swift
// Models/Conversation.swift
struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    var createdAt: Date
    var updatedAt: Date
}

// Views/ConversationsListView.swift
struct ConversationsListView: View {
    @StateObject var manager = ConversationManager()

    var body: some View {
        List(manager.conversations) { conv in
            NavigationLink(destination: ChatView(conversation: conv)) {
                ConversationRow(conversation: conv)
            }
        }
    }
}
```

### 4.2 Persistenz (SwiftData)

```swift
import SwiftData

@Model
class ConversationModel {
    @Attribute(.unique) var id: UUID
    var title: String
    @Relationship(deleteRule: .cascade) var messages: [MessageModel]
    var createdAt: Date
}

@Model
class MessageModel {
    var id: UUID
    var text: String
    var isUser: Bool
    var timestamp: Date
    var conversation: ConversationModel?
}
```

### 4.3 Export & Sharing

**Features:**
- Export als Markdown
- Export als PDF
- Share als Text
- Copy to Clipboard

### 4.4 Search & Filter

**Full-Text Search:**
```swift
class SearchManager {
    func searchMessages(query: String, in conversations: [Conversation]) -> [Message] {
        // Full-text search
    }

    func filterByDate(from: Date, to: Date) -> [Conversation] {
        // Date filtering
    }
}
```

**Geschätzte Zeit:** 8-10 Stunden

---

## 📊 Phase 5: Analytics & Monitoring

### 5.1 Usage Analytics

**Tracking:**
- Anzahl der Nachrichten
- API-Kosten
- Response-Zeiten
- Fehlerrate
- Beliebte Themen

### 5.2 Error Handling & Logging

```swift
class ErrorLogger {
    static func log(_ error: Error, context: String) {
        // OSLog für Debugging
        // Optional: Sentry/Crashlytics
    }
}
```

### 5.3 Rate Limiting & Quotas

```swift
class RateLimiter {
    private var requestCount: Int = 0
    private var resetTime: Date

    func canMakeRequest() -> Bool {
        // Check limits
    }
}
```

**Geschätzte Zeit:** 4-6 Stunden

---

## 🎯 Zusammenfassung & Timeline

| Phase | Beschreibung | Dauer | Status |
|-------|-------------|-------|--------|
| 0 | Basis Chatbot | - | ✅ Fertig |
| 1 | Perplexity API | 4-6h | ⏳ Geplant |
| 2 | Schönes UI | 8-10h | ⏳ Geplant |
| 3 | RAG Speicher | 12-15h | ⏳ Geplant |
| 4 | Erweiterte Features | 8-10h | ⏳ Geplant |
| 5 | Analytics | 4-6h | ⏳ Geplant |

**Gesamt:** ~40-50 Stunden für vollständige Implementation

---

## 🚀 Empfohlene Reihenfolge

### Minimal Viable Product (MVP):
1. ✅ Basis-Chat (fertig)
2. **Phase 1** - Perplexity API (echte KI!)
3. **Phase 2.1-2.2** - UI Basics (Markdown, Typing)

**Danach MVP ist nutzbar!** (~12-16 Stunden)

### Vollversion:
4. Phase 2.3-2.4 - Advanced UI
5. Phase 3 - RAG
6. Phase 4 - Multi-Conversations
7. Phase 5 - Analytics

---

## 🔑 API Keys & Services benötigt

### Sofort:
- [ ] **Perplexity API Key**
  - Registrierung: https://www.perplexity.ai/settings/api
  - Pricing: ~$1-5 per 1M tokens (günstiger als OpenAI)

### Optional (später):
- [ ] **OpenAI API** (für Embeddings)
  - Oder: Lokale Embeddings mit CoreML
- [ ] **ChromaDB Cloud** (für Vector Store)
  - Oder: Lokale SQLite-VSS

---

## 📝 Nächste Schritte

### Jetzt gleich starten:

1. **Perplexity API Key besorgen:**
   ```
   https://www.perplexity.ai/settings/api
   ```

2. **API Configuration erstellen:**
   ```bash
   # In Xcode:
   # Rechtsklick auf SimpleChatbot → New Group → "Config"
   # Neue Datei: APIConfig.swift
   ```

3. **NetworkManager implementieren:**
   - URLSession für API-Calls
   - Error Handling
   - Response Parsing

4. **PerplexityService integrieren:**
   - Replace LocalAIService
   - Oder: Hybrid-Ansatz (local + API)

### Dann weiter mit UI:

5. **Markdown-Rendering hinzufügen**
6. **Typing Indicator**
7. **Streaming Responses**

---

## 💡 Tipps für Entwicklung

### Cursor + Xcode Workflow:

**In Cursor:**
- Neue Dateien erstellen
- Code mit AI schreiben
- Refactoring

**In Xcode:**
- Build & Test (⌘R)
- UI Previews
- Debugging

### Git Workflow:

```bash
# Feature Branch für jede Phase
git checkout -b feature/perplexity-api
# ... work ...
git commit -m "Add Perplexity API integration"
git push

git checkout -b feature/enhanced-ui
# ... work ...
```

### Testing:

```bash
# Unit Tests in SimpleChatbot/Tests/
mkdir -p SimpleChatbot/Tests
# Test für jeden Service
```

---

## 📚 Ressourcen

### API Dokumentation:
- **Perplexity API:** https://docs.perplexity.ai/
- **OpenAI Embeddings:** https://platform.openai.com/docs/guides/embeddings

### UI Libraries:
- **MarkdownUI:** https://github.com/gonzalezreal/swift-markdown-ui
- **Highlightr:** https://github.com/raspu/Highlightr

### RAG Resources:
- **ChromaDB:** https://docs.trychroma.com/
- **SQLite VSS:** https://github.com/asg017/sqlite-vss

### SwiftUI:
- **Apple Tutorials:** https://developer.apple.com/tutorials/swiftui
- **Hacking with Swift:** https://www.hackingwithswift.com/

---

## 🎉 Los geht's!

**Bereit für Phase 1?** Sagen Sie Bescheid, und wir implementieren die Perplexity API Integration! 🚀
