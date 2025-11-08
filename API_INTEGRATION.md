# TRINITY - API Integration Guide

Anleitung zur Integration von Cloud-APIs (OpenAI, Anthropic Claude) in die TRINITY App.

## Übersicht

TRINITY kann in **3 Modi** arbeiten:

```
1. Nur Lokal (Standard)
   ✅ 100% Privat
   ✅ Offline
   ✅ Keine Kosten
   ⚠️ Begrenzte Genauigkeit

2. Cloud-Unterstützt
   ✅ Lokal für normale Fälle
   ✅ Cloud bei niedriger Confidence
   ⚠️ Kosten variieren
   ⚠️ Internet erforderlich

3. Cloud Bevorzugt
   ✅ Beste Genauigkeit
   ⚠️ Höhere Kosten
   ⚠️ Daten gehen an externe Server
   ⚠️ Internet erforderlich
```

---

## 🚀 Quick Start

### Schritt 1: API Keys besorgen

#### OpenAI (GPT-4 Vision)
```
1. Gehe zu: https://platform.openai.com/api-keys
2. Klicke "Create new secret key"
3. Kopiere: sk-proj-...
4. Speichere sicher!
```

**Kosten**: ~$0.01 pro Bildbeschreibung

#### Anthropic Claude (Claude 3.5 Sonnet Vision)
```
1. Gehe zu: https://console.anthropic.com/settings/keys
2. Klicke "Create Key"
3. Kopiere: sk-ant-api03-...
4. Speichere sicher!
```

**Kosten**: ~$0.008 pro Bildbeschreibung

### Schritt 2: API Keys in App eintragen

#### Via Code (für Entwicklung):
```swift
// In TrinityCoordinator.swift beim Init:
Configuration.shared.openAIKey = "sk-proj-..."
Configuration.shared.claudeKey = "sk-ant-..."
```

#### Via UI (für Endnutzer):
```
App öffnen
→ Settings
→ Cloud-APIs
→ API Keys konfigurieren
→ Keys eingeben
→ Speichern
```

### Schritt 3: Enhanced Perception Agent aktivieren

```swift
// In TrinityCoordinator.swift ersetzen:

// ALT:
self.perceptionAgent = try PerceptionAgent(
    embeddingGenerator: embeddingGenerator
)

// NEU:
self.perceptionAgent = try EnhancedPerceptionAgent(
    embeddingGenerator: embeddingGenerator,
    openAIKey: Configuration.shared.openAIKey,
    claudeKey: Configuration.shared.claudeKey,
    mode: .cloudEnhanced  // oder .localOnly, .cloudFirst
)
```

### Schritt 4: Testen!

```swift
// Build & Run
Cmd + R

// App öffnet
→ Start drücken
→ Kamera auf Szene richten
→ Warte auf Beschreibung

// Bei niedriger Confidence wird automatisch Cloud genutzt
```

---

## 📖 Detaillierte Integration

### 1. OpenAI Integration

#### Einfache Bildbeschreibung:

```swift
import Foundation

let openAI = OpenAIClient(apiKey: "sk-proj-...")

// Bild beschreiben
if let imageData = UIImage(named: "scene.jpg")?.jpegData(compressionQuality: 0.8) {
    let description = try await openAI.describeImage(imageData)
    print("GPT-4 Vision sagt: \(description)")
}
```

**Ausgabe:**
```
"Ich sehe einen Wohnraum mit einem Sofa links, einem Couchtisch mittig
und einer Tür rechts. Der Couchtisch ist etwa 1 Meter entfernt."
```

#### Navigation generieren:

```swift
let navText = try await openAI.generateNavigationDescription(
    objects: ["Tisch", "Stuhl", "Tür"],
    distances: [0.5, 1.2, 3.0],
    context: "Wohnzimmer, Nachmittag"
)
print(navText)
```

**Ausgabe:**
```
"Vorsicht: Tisch direkt vor Ihnen in 50cm Entfernung. Stuhl links in
1.2m. Tür geradeaus in 3m."
```

#### Text Embeddings:

```swift
let embedding = try await openAI.generateEmbedding(
    text: "Tisch vor mir im Wohnzimmer"
)
print("Embedding: \(embedding.count) Dimensionen")
// [0.23, -0.45, 0.67, ..., 0.12] (512 oder 1536 Dimensionen)
```

### 2. Anthropic Claude Integration

#### Szenenanalyse (strukturiert):

```swift
let claude = AnthropicClient(apiKey: "sk-ant-...")

let analysis = try await claude.analyzeScene(
    imageData,
    context: "Innenraum"
)

// Strukturierte Antwort:
print("Objekte:")
for obj in analysis.objects {
    print("- \(obj.name): \(obj.distance), \(obj.direction), Risiko: \(obj.risk)")
}

print("\nBeschreibung: \(analysis.sceneDescription)")
print("Navigation: \(analysis.navigationAdvice)")

if !analysis.warnings.isEmpty {
    print("\n⚠️ Warnungen:")
    for warning in analysis.warnings {
        print("- \(warning)")
    }
}
```

**Ausgabe:**
```
Objekte:
- Tisch: 0.5m, mittig, Risiko: hoch
- Stuhl: 1.2m, links, Risiko: mittel
- Wand: 3.0m, vorne, Risiko: niedrig

Beschreibung: Wohnraum mit Möbeln, gut beleuchtet

Navigation: Bitte nach links ausweichen, Tisch direkt voraus

⚠️ Warnungen:
- Tisch sehr nah, Kollisionsgefahr
```

#### Kontextuelle Navigation:

```swift
let navText = try await claude.generateContextualNavigation(
    currentObservation: "Tisch vor mir",
    recentHistory: [
        "War gerade im Flur",
        "Tür nach links aufgemacht",
        "Jetzt im Raum"
    ],
    knownLocation: "Wohnzimmer"
)
```

**Ausgabe:**
```
"Sie sind ins Wohnzimmer gekommen. Der Couchtisch steht wie immer
mittig - gehen Sie links dran vorbei zum Sofa."
```

#### Memory-Konsolidierung:

```swift
let memories = [
    "Tisch im Wohnzimmer gesehen",
    "Wohnzimmer Tisch, mittags",
    "Couchtisch Wohnzimmer Nachmittag",
    "Stuhl neben Tisch im Wohnzimmer"
]

let consolidated = try await claude.consolidateMemories(memories: memories)
```

**Ausgabe:**
```
[
  "Couchtisch mittig im Wohnzimmer (mehrfach beobachtet)",
  "Stuhl neben Couchtisch"
]
```

### 3. Enhanced Perception Agent

#### Cloud-Enhanced Mode (Empfohlen):

```swift
let agent = try EnhancedPerceptionAgent(
    embeddingGenerator: embeddingGenerator,
    openAIKey: "sk-proj-...",
    claudeKey: "sk-ant-...",
    mode: .cloudEnhanced
)

let output = try await agent.process(input)

// Logik:
// 1. Versuche lokal (Core ML)
// 2. Wenn Confidence < 0.8 → Nutze Cloud
// 3. Kombiniere Ergebnisse
```

**Vorteile:**
- ✅ Meiste Zeit offline (privat + kostenlos)
- ✅ Cloud nur bei Unsicherheit
- ✅ Beste Balance Privacy/Genauigkeit

**Workflow:**
```
Frame kommt rein
→ Vision Framework analysiert
→ Confidence: 0.65 (niedrig!)
→ Ruft Claude API
→ Claude: Confidence 0.95
→ Kombiniert Ergebnisse
→ Finale Confidence: 0.95
```

#### Cloud-First Mode:

```swift
let agent = try EnhancedPerceptionAgent(
    embeddingGenerator: embeddingGenerator,
    claudeKey: "sk-ant-...",
    mode: .cloudFirst
)
```

**Vorteile:**
- ✅ Maximale Genauigkeit
- ✅ Detaillierte Beschreibungen
- ✅ Strukturierte Ausgabe

**Nachteile:**
- ⚠️ Höhere Kosten (~$10-30/Monat bei normaler Nutzung)
- ⚠️ Internet erforderlich
- ⚠️ Bilder gehen an externe Server

---

## 💰 Kosten-Kalkulation

### OpenAI GPT-4 Vision
```
Preis: $0.01 pro Bild
Bei 100 Bildern/Tag: $1/Tag = ~$30/Monat
Bei 20 Bildern/Tag: $0.20/Tag = ~$6/Monat
```

### Anthropic Claude 3.5 Sonnet Vision
```
Preis: ~$0.008 pro Bild
Bei 100 Bildern/Tag: $0.80/Tag = ~$24/Monat
Bei 20 Bildern/Tag: $0.16/Tag = ~$5/Monat
```

### Empfohlene Nutzung:

**Cloud-Enhanced Mode** (Hybrid):
```
90% lokal (kostenlos)
10% Cloud (bei niedriger Confidence)

→ Bei 100 Analysen/Tag:
   - 90 lokal: $0
   - 10 Cloud: $0.10
   → ~$3/Monat
```

### Rate Limiting setzen:

```swift
// Max 50 Cloud-Calls pro Tag
Configuration.shared.maxCloudCallsPerDay = 50

// Prüfen vor Call:
if !Configuration.shared.hasReachedCloudLimit() {
    let result = try await openAI.describeImage(imageData)
    Configuration.shared.incrementCloudCalls()
}
```

---

## 🔐 Sicherheit & Datenschutz

### API Keys sicher speichern:

✅ **Gut:**
```swift
// Nutze Configuration (speichert in UserDefaults verschlüsselt)
Configuration.shared.openAIKey = "sk-..."
```

❌ **NIEMALS:**
```swift
// Nicht im Code hardcoden!
let key = "sk-proj-abc123..."  // ❌ Landet in Git!

// Nicht in Klartext loggen!
print("API Key: \(key)")  // ❌ Landet in Logs!
```

### Environment Variables (Entwicklung):

```bash
# .env Datei (NICHT committen!)
OPENAI_API_KEY=sk-proj-...
CLAUDE_API_KEY=sk-ant-...

# .gitignore
.env
*.env
```

```swift
// In Code laden:
Configuration.shared.loadFromEnvironment()
```

### User Consent:

```swift
// Immer User fragen vor Cloud-Nutzung!
if !Configuration.shared.allowCloudProcessing {
    // Zeige Alert
    "Diese Funktion sendet Bilder an externe Server. Erlauben?"

    if userAllows {
        Configuration.shared.allowCloudProcessing = true
    }
}
```

---

## 🧪 Testing

### Mock API für Testing:

```swift
class MockOpenAIClient: OpenAIClient {
    override func describeImage(_ imageData: Data, prompt: String) async throws -> String {
        return "Test-Beschreibung: Tisch vor Ihnen"
    }
}

// In Tests verwenden:
let agent = try EnhancedPerceptionAgent(
    embeddingGenerator: embeddingGenerator,
    mode: .localOnly  // Keine echten API Calls
)
```

### Rate Limit Testing:

```swift
func testRateLimit() async throws {
    Configuration.shared.maxCloudCallsPerDay = 10
    Configuration.shared.resetDailyCloudCalls()

    for i in 1...15 {
        if !Configuration.shared.hasReachedCloudLimit() {
            Configuration.shared.incrementCloudCalls()
            print("Call #\(i) erfolgreich")
        } else {
            print("Rate Limit erreicht bei Call #\(i)")
            break
        }
    }
}
```

---

## 📊 Monitoring & Analytics

### Kosten-Tracking:

```swift
// Täglich Kosten tracken
extension Configuration {
    func logCloudUsage() {
        let cost = Double(cloudCallsToday) * 0.01  // $0.01 pro Call
        print("Heute: \(cloudCallsToday) Calls, $\(cost)")
    }
}

// Monatliche Schätzung
let monthlyCost = Configuration.shared.estimatedMonthlyCost()
print("Geschätzt diesen Monat: $\(monthlyCost)")
```

### Performance-Vergleich:

```swift
// Messe Latenz
let start = Date()

// Lokal
let localOutput = try await localAgent.process(input)
let localTime = Date().timeIntervalSince(start)

// Cloud
let cloudStart = Date()
let cloudOutput = try await enhancedAgent.process(input)
let cloudTime = Date().timeIntervalSince(cloudStart)

print("""
Lokal: \(Int(localTime * 1000))ms, Confidence: \(localOutput.confidence)
Cloud: \(Int(cloudTime * 1000))ms, Confidence: \(cloudOutput.confidence)
""")
```

---

## 🎯 Best Practices

### 1. Hybrid Approach (Empfohlen)

```swift
// Nutze Lokal für normale Fälle
// Cloud nur bei:
// - Niedriger Confidence
// - Komplexen Szenen
// - User-Request

if localConfidence > 0.8 || !networkAvailable {
    return localResult
} else {
    return cloudResult
}
```

### 2. Offline-Fähigkeit

```swift
// Immer Fallback auf Lokal
do {
    if networkAvailable && allowCloud {
        return try await cloudProcess()
    }
} catch {
    print("Cloud failed, fallback to local")
}
return try await localProcess()
```

### 3. User-Kontrolle

```swift
// User entscheidet:
// - Cloud ja/nein
// - Rate Limits
// - Kosten-Budget
// - API Anbieter (OpenAI vs Claude)

if Configuration.shared.canUseCloudAPIs() {
    // User hat explizit erlaubt
}
```

---

## 🔧 Troubleshooting

### Problem: "Invalid API Key"

```swift
// Prüfe Key-Format:
if !Configuration.shared.hasValidOpenAIKey() {
    print("OpenAI Key ungültig: muss mit 'sk-' beginnen")
}

if !Configuration.shared.hasValidClaudeKey() {
    print("Claude Key ungültig: muss mit 'sk-ant-' beginnen")
}
```

### Problem: "Rate Limit Exceeded"

```swift
// Option 1: Täglich zurücksetzen
Configuration.shared.resetDailyCloudCalls()

// Option 2: Limit erhöhen
Configuration.shared.maxCloudCallsPerDay = 100

// Option 3: Upgrade API Plan
// → OpenAI Tier erhöhen
// → Claude Credits kaufen
```

### Problem: "Network Error"

```swift
// Fallback auf Lokal
do {
    return try await cloudProcess()
} catch {
    print("Network Error: \(error)")
    print("Fallback to local processing")
    return try await localProcess()
}
```

---

## 📱 UI Integration

### Settings mit Cloud-Konfiguration:

```swift
// Verwende EnhancedSettingsView statt SettingsView

.sheet(isPresented: $showSettings) {
    EnhancedSettingsView()  // Neue Version mit API Config
        .environmentObject(coordinator)
}
```

**Features:**
- ✅ API Key Eingabe (maskiert)
- ✅ Mode-Auswahl (Lokal/Hybrid/Cloud)
- ✅ Rate Limit Konfiguration
- ✅ Kosten-Schätzung
- ✅ Privacy-Warnungen

---

## 🚀 Deployment

### Production Checklist:

```
✅ API Keys aus Code entfernen
✅ .env in .gitignore
✅ User Consent UI implementiert
✅ Rate Limiting aktiviert
✅ Fallback auf Lokal funktioniert
✅ Kosten-Warnung bei Cloud-Nutzung
✅ Privacy Policy aktualisiert
```

### App Store Submission:

**Info.plist:**
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
</dict>
```

**Privacy Manifest:**
```
Data Sent to Third Parties:
- OpenAI: Images for object recognition (optional)
- Anthropic: Images for scene analysis (optional)

User Control: Yes, can be disabled in Settings
```

---

## 📚 Weiterführende Ressourcen

- [OpenAI API Docs](https://platform.openai.com/docs)
- [Anthropic Claude Docs](https://docs.anthropic.com)
- [Apple Privacy Guidelines](https://developer.apple.com/privacy)
- [iOS Security Best Practices](https://developer.apple.com/security)

---

**Status**: ✅ API Integration vollständig implementiert

**Nächste Schritte**: API Keys besorgen & testen!
