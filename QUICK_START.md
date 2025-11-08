# TRINITY Vision Aid - Quick Start Guide

Schnelleinstieg für Entwickler, die sofort mit TRINITY arbeiten möchten.

## 5-Minuten-Setup

### 1. Voraussetzungen prüfen

```bash
# Xcode installiert?
xcode-select -p
# Sollte ausgeben: /Applications/Xcode.app/Contents/Developer

# iOS Deployment Target
# Mindestens: iOS 17.0

# Gerät
# iPhone 17 Pro oder neuer (mit LiDAR)
```

### 2. Projekt klonen & öffnen

```bash
git clone https://github.com/yourusername/TRINITY.git
cd TRINITY
open -a Xcode .
```

### 3. Xcode Projekt erstellen (erstmaliges Setup)

Falls noch kein `.xcodeproj` existiert:

1. Xcode öffnen
2. **File → New → Project → iOS App**
3. Settings:
   - Name: `TRINITY`
   - Bundle ID: `com.trinity.visionaid`
   - Interface: **SwiftUI**
   - Language: **Swift**
4. Speichern im `TRINITY` Ordner

### 4. Source Files hinzufügen

```bash
# In Xcode Navigator:
# Rechtsklick auf TRINITY → Add Files to "TRINITY"
# Wähle: TrinityApp/Sources/ (alle Ordner)
# ✅ Copy items if needed
# ✅ Create groups
```

### 5. Frameworks verknüpfen

**Target → Build Phases → Link Binary With Libraries → +**

Hinzufügen:
- ARKit
- AVFoundation
- CoreML
- Vision
- CoreLocation
- CloudKit
- NaturalLanguage

### 6. Info.plist kopieren

```bash
cp TrinityApp/Info.plist TRINITY/TRINITY/Info.plist
```

Oder manuell Permissions hinzufügen:
- Camera Usage
- Location Usage
- ARKit Usage

### 7. Build & Run

```bash
# In Xcode:
Cmd + R

# Oder via Command Line:
xcodebuild -scheme TRINITY -destination 'platform=iOS,name=Your iPhone'
```

## Erste Schritte im Code

### Verstehen der Architektur

```swift
// 1. Entry Point: TrinityApp.swift
@main
struct TrinityApp: App {
    @StateObject private var coordinator: TrinityCoordinator
    // ...
}

// 2. Coordinator: TrinityCoordinator.swift
class TrinityCoordinator {
    // Orchestriert alle Komponenten
    private let sensorManager: SensorManager
    private let memoryManager: MemoryManager
    private let agents: [Agent]
    // ...
}

// 3. Sensors: SensorManager.swift
class SensorManager {
    // Verwaltet Kamera, LiDAR, Location
    private var arSession: ARSession
    // ...
}

// 4. Memory: MemoryManager.swift
class MemoryManager {
    // 3-Schicht Gedächtnis
    var workingMemory: [VectorEntry]
    var episodicMemory: [VectorEntry]
    var semanticMemory: [VectorEntry]
    // ...
}

// 5. Agents: Agent.swift + Implementierungen
protocol Agent {
    func process(_ input: Input) async throws -> Output
}
```

### Datenfluss verstehen

```
1. Sensor Input
   ↓
2. SensorManager (ARFrame, Location)
   ↓
3. PerceptionAgent (Objekterkennung)
   ↓
4. EmbeddingGenerator (Vector)
   ↓
5. MemoryManager (Speichern + Suchen)
   ↓
6. ContextAgent (Kontext aufbauen)
   ↓
7. NavigationAgent (Hindernisse)
   ↓
8. CommunicationAgent (Sprache)
   ↓
9. Audio Output + Haptics
```

## Typische Entwicklungsaufgaben

### Task 1: Neues Objekt erkennen

**Datei**: `Agents/PerceptionAgent.swift`

```swift
// Zeile ~50: processVisionFrame
private func processVisionFrame(_ imageData: Data) async throws -> [DetectedObject] {
    // Hier Vision Framework Integration

    let request = VNRecognizeObjectsRequest { request, error in
        // Verarbeite Ergebnisse
    }

    // Führe Request aus
}
```

### Task 2: Neue Memory-Query

**Datei**: `Memory/MemoryManager.swift`

```swift
// Zeile ~100: search
func search(embedding: [Float], topK: Int = 5) async throws -> [VectorEntry] {
    // Suche über alle Memory Layers
    var results: [VectorEntry] = []

    // Working Memory durchsuchen
    results += workingMemory.filter { ... }

    return results.sorted { $0.similarity > $1.similarity }
}
```

### Task 3: UI anpassen

**Datei**: `UI/MainView.swift`

```swift
// Zeile ~30: VStack mit Buttons
VStack(spacing: 30) {
    // Neuen Button hinzufügen
    ActionButton(
        title: "Neue Funktion",
        icon: "star.fill",
        action: {
            // Action hier
        }
    )
}
```

### Task 4: Neuen Agent hinzufügen

**Neue Datei**: `Agents/MyAgent.swift`

```swift
class MyAgent: BaseAgent<MyInput, MyOutput> {
    override init() {
        super.init(name: "MyAgent")
    }

    override func process(_ input: MyInput) async throws -> MyOutput {
        // Implementierung
        return MyOutput(...)
    }
}

// In TrinityCoordinator registrieren:
agentCoordinator.register(myAgent)
```

## Debugging

### Sensor-Daten testen

```swift
// In TrinityCoordinator.swift, Zeile ~150
private func processObservation(_ observation: Observation) async {
    // Debug-Output hinzufügen:
    print("📸 Observation:")
    print("  - Timestamp: \(observation.timestamp)")
    print("  - Objects: \(observation.detectedObjects.count)")
    print("  - Location: \(observation.location?.coordinate)")
}
```

### Memory-Inhalte anzeigen

```swift
// In MemoryManager.swift
func debugPrint() {
    print("🧠 Memory Status:")
    print("  - Working: \(workingMemory.count)")
    print("  - Episodic: \(episodicMemory.count)")
    print("  - Semantic: \(semanticMemory.count)")
}
```

### Embedding-Qualität prüfen

```swift
// In EmbeddingGenerator.swift
func debugEmbedding(_ embedding: [Float]) {
    let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
    print("🔢 Embedding:")
    print("  - Dimension: \(embedding.count)")
    print("  - Magnitude: \(magnitude)")
    print("  - First 5: \(embedding.prefix(5))")
}
```

## Testing

### Unit Test Beispiel

**Datei**: `Tests/MemoryManagerTests.swift`

```swift
import XCTest
@testable import TRINITY

class MemoryManagerTests: XCTestCase {
    var memoryManager: MemoryManager!

    override func setUp() async throws {
        let vectorDB = try VectorDatabase()
        memoryManager = MemoryManager(vectorDatabase: vectorDB)
    }

    func testAddObservation() async throws {
        let observation = createTestObservation()
        let embedding = [Float](repeating: 0.5, count: 512)

        try await memoryManager.addObservation(observation, embedding: embedding)

        XCTAssertEqual(memoryManager.workingMemory.count, 1)
    }
}
```

### UI Test Beispiel

**Datei**: `Tests/MainViewTests.swift`

```swift
import XCTest

class MainViewUITests: XCTestCase {
    func testStartButton() throws {
        let app = XCUIApplication()
        app.launch()

        let startButton = app.buttons["Start TRINITY"]
        XCTAssertTrue(startButton.exists)

        startButton.tap()

        // Überprüfe Status-Änderung
        XCTAssertTrue(app.staticTexts["Running"].exists)
    }
}
```

## Performance-Profiling

### Instruments verwenden

```bash
# In Xcode:
Cmd + I

# Instrumente wählen:
# - Time Profiler (CPU)
# - Allocations (Memory)
# - Energy Log (Battery)
```

### Kritische Performance-Bereiche

1. **Embedding-Generierung**: Sollte < 100ms sein
2. **Vector Search**: Sollte < 20ms sein (10k Vektoren)
3. **UI Updates**: Sollte < 16ms sein (60 FPS)

## Häufige Probleme & Lösungen

### Problem: "ARKit not available"

```swift
// Lösung: Simulator unterstützt kein ARKit
// Testen Sie auf physischem Gerät
guard ARWorldTrackingConfiguration.isSupported else {
    print("⚠️ ARKit nicht verfügbar")
    return
}
```

### Problem: "Memory not persisting"

```swift
// Lösung: Speichern vergessen
await memoryManager.saveMemories()

// Oder Auto-Save aktivieren:
NotificationCenter.default.addObserver(
    forName: UIApplication.didEnterBackgroundNotification,
    object: nil,
    queue: nil
) { _ in
    Task {
        try? await memoryManager.saveMemories()
    }
}
```

### Problem: "Voice output not working"

```swift
// Lösung: Berechtigungen prüfen
AVAudioSession.sharedInstance().requestRecordPermission { granted in
    if !granted {
        print("⚠️ Audio Berechtigung fehlt")
    }
}
```

## Nächste Schritte

Nach dem Quick Start:

1. ✅ **ARCHITECTURE.md** lesen
2. ✅ Code-Kommentare durchgehen
3. ✅ Erste Tests auf iPhone ausführen
4. ✅ Mit VoiceOver testen
5. ✅ Eigene Features entwickeln

## Ressourcen

- **Apple Docs**: [ARKit](https://developer.apple.com/arkit)
- **Core ML**: [Machine Learning](https://developer.apple.com/machine-learning)
- **SwiftUI**: [Tutorial](https://developer.apple.com/tutorials/swiftui)
- **Accessibility**: [Guidelines](https://developer.apple.com/accessibility)

## Community

- **GitHub**: Issues & Discussions
- **Stack Overflow**: Tag `trinity-vision-aid`
- **Discord**: [Link folgt]

---

**Happy Coding!** 🚀

Fragen? → Öffnen Sie ein GitHub Issue
