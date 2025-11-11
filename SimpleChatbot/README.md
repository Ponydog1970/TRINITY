# 🤖 Simple Chatbot - Lokale KI Übungsprojekt

Ein einfacher Chatbot mit SwiftUI und lokaler KI-Integration - perfekt zum Üben von Xcode und Cursor!

## 📋 Was ist das?

Dies ist ein Übungsprojekt, um zu lernen:
- ✅ Wie man ein Xcode-Projekt strukturiert
- ✅ SwiftUI für moderne iOS/macOS Apps
- ✅ Ordner-Organisation (Xcode + Cursor kompatibel)
- ✅ Lokale KI-Integration (Vorbereitet für MLX, CoreML, llama.cpp)

## 🚀 Schnellstart

### Option 1: In Xcode öffnen (Empfohlen)

1. **Xcode öffnen**
   ```bash
   open SimpleChatbot/Package.swift
   ```
   Oder:
   - Doppelklick auf `Package.swift` im Finder

2. **Warten bis Dependencies geladen sind**
   - Xcode lädt automatisch alle Pakete

3. **App auswählen**
   - Oben links: Wählen Sie `SimpleChatbot` Schema
   - Wählen Sie ein Target (z.B. "iPhone 15 Pro" oder "My Mac")

4. **Build & Run**
   - Drücken Sie ⌘R oder klicken Sie auf ▶️ Play-Button

### Option 2: Mit Cursor bearbeiten

```bash
# Cursor im Projekt-Ordner öffnen
cd /home/user/TRINITY
cursor SimpleChatbot/

# Oder von überall:
cursor /home/user/TRINITY/SimpleChatbot
```

**In Cursor können Sie:**
- Code bearbeiten und AI-Assistenz nutzen
- Struktur verstehen und erweitern
- Neue Features hinzufügen

**Dann in Xcode:**
- Build und Run ausführen
- App testen und debuggen

## 📁 Projektstruktur

```
SimpleChatbot/
├── Package.swift                    # Swift Package Definition
├── README.md                        # Diese Datei
└── SimpleChatbot/
    ├── App/
    │   └── SimpleChatbotApp.swift  # App Entry Point (@main)
    ├── Views/
    │   └── ChatView.swift          # Chat UI (SwiftUI)
    ├── Models/
    │   └── Message.swift           # Message Datenmodell
    └── Services/
        └── LocalAIService.swift    # KI-Service (aktuell simuliert)
```

**💡 Diese Struktur ist optimal für:**
- ✅ Xcode (klare Navigation)
- ✅ Cursor (sieht alle Ordner)
- ✅ Git (saubere Historie)

## 🎯 Features

### Aktuell implementiert:
- ✅ Modernes SwiftUI Chat-Interface
- ✅ Nachrichten-Historie
- ✅ Auto-Scroll zu neuen Nachrichten
- ✅ Zeitstempel für jede Nachricht
- ✅ User/Bot Unterscheidung
- ✅ Simulierter KI-Service (regelbasiert)

### Chat-Funktionen zum Ausprobieren:
Probieren Sie in der App:
- "Hallo" → Begrüßung
- "Wie heißt du?" → Stellt sich vor
- "Wie funktionierst du?" → Erklärt lokale KI
- "Hilfe" → Zeigt Möglichkeiten

## 🔧 Erweitern mit echter lokaler KI

### Option 1: MLX Swift (Apple Silicon)

```swift
// In LocalAIService.swift ersetzen:

import MLX
import MLXRandom
import MLXNN

class LocalAIService: ObservableObject {
    private var model: LanguageModel?

    func loadModel() async {
        // Lade MLX Modell
        model = try? await LanguageModel.load("mlx-community/Llama-3.2-1B-4bit")
    }

    func generateResponse(for message: String) async -> String {
        guard let model = model else { return "Modell wird geladen..." }

        let prompt = "User: \(message)\nAssistant:"
        let output = model.generate(prompt: prompt, maxTokens: 200)
        return output
    }
}
```

**Installation:**
```bash
# In Package.swift dependencies hinzufügen:
.package(url: "https://github.com/ml-explore/mlx-swift", from: "0.1.0")
```

### Option 2: CoreML

```swift
import CoreML

class CoreMLChatService: ObservableObject {
    private var model: YourCoreMLModel?

    init() {
        model = try? YourCoreMLModel(configuration: .init())
    }

    func generateResponse(for message: String) async -> String {
        guard let model = model else { return "Modell nicht geladen" }

        let input = YourCoreMLModelInput(text: message)
        let prediction = try? model.prediction(input: input)
        return prediction?.response ?? "Keine Antwort"
    }
}
```

**Modelle:**
- Download von [Hugging Face](https://huggingface.co/models?library=coreml)
- Konvertiere mit `coremltools`

### Option 3: Llama.cpp (Cross-Platform)

```swift
// Package.swift:
.package(url: "https://github.com/ShenghaiWang/SwiftLlama", from: "1.0.0")

// LocalAIService.swift:
import SwiftLlama

class LocalAIService: ObservableObject {
    private var llama: SwiftLlama?

    func loadModel(path: String) {
        llama = try? SwiftLlama(modelPath: path)
    }

    func generateResponse(for message: String) async -> String {
        let prompt = "### User: \(message)\n### Assistant:"
        let response = llama?.predict(prompt, maxTokens: 200)
        return response ?? "Fehler"
    }
}
```

## 🎨 UI Anpassen

### Farben ändern:
```swift
// In ChatView.swift, MessageBubble:

.background(message.isUser ? Color.green : Color.orange)  // Neue Farben
```

### Mehr Features hinzufügen:
```swift
// In Message.swift:
struct Message: Identifiable {
    let id: UUID
    let text: String
    let isUser: Bool
    let timestamp: Date

    // Neue Properties:
    var isTyping: Bool = false        // Typing Indicator
    var hasError: Bool = false        // Fehler-Status
    var attachments: [URL] = []       // Datei-Anhänge
}
```

## 🔍 Debugging

### Xcode Console:
```swift
// In LocalAIService.swift hinzufügen:
func generateResponse(for message: String) async -> String {
    print("🤖 Verarbeite: \(message)")

    let response = generateSimpleResponse(for: message)

    print("✅ Antwort: \(response)")
    return response
}
```

### Xcode Breakpoints:
1. Klicken Sie auf die Zeilennummer (blauer Punkt erscheint)
2. Run mit ⌘R
3. App pausiert bei Breakpoint
4. Inspizieren Sie Variablen im Debug-Bereich

## 📱 Plattformen

### Aktuell unterstützt:
- iOS 17+
- macOS 14+

### Zum Anpassen in `Package.swift`:
```swift
platforms: [
    .iOS(.v16),      // Für iOS 16+
    .macOS(.v13),    // Für macOS 13+
    .watchOS(.v9)    // Watch hinzufügen
]
```

## 🤝 Xcode + Cursor Workflow

### Empfohlener Workflow:

1. **Code schreiben in Cursor:**
   - AI-Assistenz nutzen
   - Schnelles Refactoring
   - Suchen und Ersetzen

2. **Testen in Xcode:**
   - Build & Run (⌘R)
   - Debugger nutzen
   - UI Preview

3. **Zwischen beiden wechseln:**
   - Beide Apps können gleichzeitig offen sein
   - Xcode lädt Änderungen automatisch
   - Speichern in Cursor → Reload in Xcode

### Ordner hinzufügen (beide Tools sehen sie):

```bash
# Im Terminal:
mkdir -p SimpleChatbot/SimpleChatbot/Utilities
echo "// Utilities" > SimpleChatbot/SimpleChatbot/Utilities/Helpers.swift
```

**In Xcode:**
1. Rechtsklick auf `SimpleChatbot` Gruppe
2. "Add Files to SimpleChatbot..."
3. Wählen Sie den `Utilities` Ordner
4. ✅ Aktivieren: "Create folder references" (blau!)
5. Klick auf "Add"

**In Cursor:**
- Ordner erscheint sofort im File Explorer
- Beide Tools sehen jetzt dieselbe Struktur! 🎉

## 📚 Weitere Schritte

### Lernen:
- [ ] SwiftUI Tutorials: [Apple Developer](https://developer.apple.com/tutorials/swiftui)
- [ ] ML Integration: [Create ML](https://developer.apple.com/machine-learning/create-ml/)
- [ ] MLX Swift: [GitHub](https://github.com/ml-explore/mlx-swift)

### Erweitern:
- [ ] Spracherkennung (Speech Framework)
- [ ] Text-to-Speech Ausgabe
- [ ] Nachrichten-Persistenz (SwiftData)
- [ ] Theming (Dark/Light Mode)
- [ ] Export Chat-Historie
- [ ] Mehrere Konversationen

## ❓ Häufige Fragen

### "Module 'SimpleChatbot' not found"
→ Warten Sie, bis Xcode Dependencies geladen hat (oben in der Mitte sehen Sie den Fortschritt)

### "Build failed"
→ Stellen Sie sicher, dass Sie iOS 17+ oder macOS 14+ als Target haben

### "Cursor sieht die Ordner nicht"
→ In Xcode: Verwenden Sie "folder references" (blaue Ordner) statt "groups" (gelbe Ordner)

### "Wie teste ich auf einem echten iPhone?"
→ iPhone per USB verbinden, in Xcode oben links das Gerät auswählen, ⌘R drücken

## 🎉 Viel Erfolg!

Dies ist Ihr Übungsprojekt - experimentieren Sie!

**Nächste Schritte:**
1. Öffnen Sie in Xcode
2. Drücken Sie ⌘R
3. Chatten Sie mit dem Bot
4. Öffnen Sie in Cursor und erweitern Sie ihn!

**Fragen?** Schauen Sie in `XCODE_CURSOR_INTEGRATION.md` im Hauptverzeichnis.
