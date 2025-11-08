# TRINITY Vision Aid - Setup Guide

Komplette Anleitung zur Installation und Konfiguration der TRINITY Vision Aid App.

## Voraussetzungen

### Hardware
- **iPhone 17 Pro** oder neuer (mit LiDAR Scanner)
- **Mac** mit Apple Silicon (für Entwicklung)
- **Xcode 15+** installiert

### Software
- **macOS**: Sonoma 14.0 oder höher
- **Xcode**: Version 15.0 oder höher
- **iOS Deployment Target**: 17.0
- **Apple Developer Account**: Für Code Signing

### Kenntnisse
- Grundkenntnisse in Swift
- Vertrautheit mit SwiftUI
- Verständnis von ARKit und Core ML

## Installation - Schritt für Schritt

### 1. Repository klonen

```bash
git clone https://github.com/yourusername/TRINITY.git
cd TRINITY
```

### 2. Xcode Projekt erstellen

Da dies ein Source-Code-Repository ist, müssen Sie das Xcode-Projekt manuell erstellen:

#### 2.1 Neues Projekt in Xcode

1. Öffnen Sie Xcode
2. **File → New → Project**
3. Wählen Sie **iOS → App**
4. Konfiguration:
   ```
   Product Name: TRINITY
   Team: [Ihr Apple Developer Team]
   Organization Identifier: com.trinity
   Bundle Identifier: com.trinity.visionaid
   Interface: SwiftUI
   Language: Swift
   Storage: SwiftData (optional)
   Include Tests: Yes
   ```
5. Speichern Sie das Projekt im `TRINITY` Ordner

#### 2.2 Dateien hinzufügen

1. Im Xcode Navigator, **Rechtsklick auf TRINITY → Add Files to "TRINITY"**
2. Navigieren Sie zu `TrinityApp/Sources/`
3. Wählen Sie alle Ordner aus:
   - `App/`
   - `Agents/`
   - `Memory/`
   - `VectorDB/`
   - `Sensors/`
   - `Models/`
   - `Utils/`
   - `UI/`
4. Optionen:
   - ✅ Copy items if needed
   - ✅ Create groups
   - ✅ Add to target: TRINITY

### 3. Info.plist konfigurieren

#### 3.1 Info.plist öffnen

1. Im Navigator: `TRINITY → TRINITY → Info.plist`
2. Fügen Sie folgende Keys hinzu:

```xml
<!-- Kamera Berechtigung -->
<key>NSCameraUsageDescription</key>
<string>TRINITY benötigt Zugriff auf die Kamera für Objekterkennung</string>

<!-- Standort Berechtigung -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>TRINITY verwendet Ihren Standort für Navigation</string>

<!-- ARKit -->
<key>NSARKitUsageDescription</key>
<string>TRINITY nutzt AR für räumliche Erfassung</string>
```

#### 3.2 Oder Info.plist ersetzen

Alternativ kopieren Sie die bereitgestellte `Info.plist`:

```bash
cp TrinityApp/Info.plist TRINITY/TRINITY/Info.plist
```

### 4. Frameworks verknüpfen

#### 4.1 Build Phases

1. Wählen Sie Target **TRINITY**
2. Tab **Build Phases**
3. Erweitern Sie **Link Binary With Libraries**
4. Klicken Sie **+** und fügen Sie hinzu:
   - `ARKit.framework`
   - `AVFoundation.framework`
   - `CoreML.framework`
   - `Vision.framework`
   - `CoreLocation.framework`
   - `CloudKit.framework`
   - `NaturalLanguage.framework`
   - `Combine.framework`

#### 4.2 Import Verification

Überprüfen Sie in jeder Swift-Datei die Imports:

```swift
// Sollte ohne Fehler kompilieren
import ARKit
import AVFoundation
import CoreML
import Vision
```

### 5. Capabilities konfigurieren

#### 5.1 Signing & Capabilities

1. Wählen Sie Target **TRINITY**
2. Tab **Signing & Capabilities**
3. Klicken Sie **+ Capability**

#### 5.2 Capabilities hinzufügen

**iCloud:**
- ✅ CloudKit
- Container: `iCloud.com.trinity.visionaid`

**Background Modes:**
- ✅ Location updates
- ✅ Audio, AirPlay, and Picture in Picture

**Maps:**
- ✅ (Automatisch hinzugefügt)

### 6. Core ML Models (Optional)

#### 6.1 Modelle herunterladen

Sie können vortrainierte Core ML Modelle verwenden:

**Option 1: Apple Models**
```bash
# MobileNetV3 für Objektklassifikation
https://developer.apple.com/machine-learning/models/

# Download: MobileNetV3.mlmodel
```

**Option 2: Custom Models**
```bash
# Eigenes Modell trainieren mit Create ML
# Oder konvertieren von TensorFlow/PyTorch
```

#### 6.2 Models zu Xcode hinzufügen

1. Ziehen Sie `.mlmodel` Datei in Xcode
2. Target: TRINITY
3. Xcode generiert automatisch Swift Interface

#### 6.3 Model Integration

In `EmbeddingGenerator.swift` aktualisieren:

```swift
// Zeile ~20 ersetzen:
self.visionModel = try VNCoreMLModel(for: MobileNetV3().model)
```

### 7. Build Settings

#### 7.1 Wichtige Einstellungen

Im Target **TRINITY → Build Settings**:

```
iOS Deployment Target: 17.0
Swift Language Version: Swift 5
Enable Bitcode: No
Debug Information Format: DWARF with dSYM File
```

#### 7.2 Optimization

**Debug:**
```
Optimization Level: None [-Onone]
```

**Release:**
```
Optimization Level: Optimize for Speed [-O]
Whole Module Optimization: Yes
```

### 8. Signing konfigurieren

#### 8.1 Automatisches Signing

1. Target **TRINITY → Signing & Capabilities**
2. ✅ **Automatically manage signing**
3. **Team**: Wählen Sie Ihr Team
4. **Bundle Identifier**: `com.trinity.visionaid`

#### 8.2 Provisioning Profile

Xcode erstellt automatisch ein Development Profile.

Für Distribution:
1. Apple Developer Portal → Certificates, Identifiers & Profiles
2. Erstellen Sie App ID: `com.trinity.visionaid`
3. Provisioning Profile für Distribution

### 9. Testen

#### 9.1 Simulator (begrenzt)

**Warnung**: Simulator hat kein LiDAR/ARKit!

```bash
# Simulator starten
Cmd + R
```

Für vollständige Tests: **Physisches iPhone 17 Pro erforderlich**

#### 9.2 Physisches Gerät

1. Verbinden Sie iPhone via USB-C
2. **Product → Destination → Ihr iPhone**
3. **Cmd + R** zum Build & Run
4. Bei erster Installation:
   - iPhone: **Settings → General → Device Management**
   - Vertrauen Sie dem Developer Certificate

#### 9.3 Berechtigungen akzeptieren

Beim ersten Start:
1. ✅ Kamera erlauben
2. ✅ Standort erlauben (When In Use)
3. ✅ Bewegung & Fitness (für ARKit)

### 10. Troubleshooting

#### Problem: "ARKit not supported"

**Lösung**:
- Nur echtes iPhone 17 Pro (oder iPhone 12 Pro+)
- Simulator nicht unterstützt

#### Problem: "Code signing failed"

**Lösung**:
```bash
# Xcode schließen
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# Xcode neu öffnen und rebuilden
```

#### Problem: "CoreML model not found"

**Lösung**:
```swift
// In EmbeddingGenerator.swift
// Kommentieren Sie vorübergehend aus:
// self.visionModel = nil

// Verwenden Sie Fallback-Embeddings
```

#### Problem: "Framework not found"

**Lösung**:
1. Überprüfen Sie **Build Phases → Link Binary**
2. Alle Frameworks sollten **Status: Required** haben
3. Clean Build Folder: **Cmd + Shift + K**
4. Rebuild: **Cmd + B**

#### Problem: Kompilierungsfehler

**Lösung**:
```bash
# Alle Warnungen und Fehler beheben
# Häufige Ursachen:

# 1. Missing imports
import ARKit  # Am Anfang der Datei

# 2. @MainActor Isolation
# Funktionen mit async await müssen richtig annotiert sein

# 3. Deprecated APIs
# Aktualisieren Sie auf neueste iOS 17 APIs
```

## Entwicklungsworkflow

### Empfohlene Ordnerstruktur in Xcode

```
TRINITY/
├── App/
│   ├── TrinityApp.swift
│   └── TrinityCoordinator.swift
├── Agents/
│   ├── Agent.swift
│   ├── PerceptionAgent.swift
│   ├── NavigationAgent.swift
│   ├── ContextAgent.swift
│   └── CommunicationAgent.swift
├── Memory/
│   ├── MemoryManager.swift
│   └── DeduplicationEngine.swift
├── VectorDB/
│   └── VectorDatabase.swift
├── Sensors/
│   └── SensorManager.swift
├── Models/
│   └── MemoryLayer.swift
├── Utils/
│   └── EmbeddingGenerator.swift
├── UI/
│   └── MainView.swift
├── Resources/
│   └── [Core ML Models]
├── Tests/
│   └── TRINITYTests/
└── Info.plist
```

### Git Workflow

```bash
# Feature Branch
git checkout -b feature/navigation-improvements

# Entwickeln...

# Commit
git add .
git commit -m "Add enhanced obstacle detection"

# Push
git push origin feature/navigation-improvements

# Pull Request erstellen
```

### Code Style

Folgen Sie Apple's Swift Style Guide:

```swift
// ✅ Gut
func processObservation(_ observation: Observation) async throws {
    // Code...
}

// ❌ Schlecht
func ProcessObservation(observation: Observation) {
    // Code...
}
```

## Deployment

### TestFlight

1. **Archive erstellen**:
   - **Product → Archive**
   - Warten auf Archivierung

2. **Upload zu TestFlight**:
   - **Window → Organizer**
   - Wählen Sie Archive
   - **Distribute App → TestFlight**

3. **Beta Testing**:
   - App Store Connect → TestFlight
   - Externe Tester hinzufügen

### App Store

1. **Vorbereitung**:
   - App Store Connect: Neue App erstellen
   - Screenshots (6.7", 6.5", 5.5")
   - App Description (Deutsch + Englisch)
   - Keywords: "Barrierefreiheit, Navigation, Sehbehinderung"

2. **Submission**:
   - **Product → Archive**
   - **Distribute → App Store**
   - Warten auf Review (1-3 Tage)

## Next Steps

Nach erfolgreicher Installation:

1. ✅ **ARCHITECTURE.md** lesen für Systemverständnis
2. ✅ **TrinityApp/README.md** für App-Dokumentation
3. ✅ Erste Tests auf iPhone 17 Pro
4. ✅ Barrierefreiheitstests mit VoiceOver
5. ✅ Real-world Testing mit Sehbehinderten

## Support & Community

- **Issues**: GitHub Issues für Bugs
- **Discussions**: GitHub Discussions für Features
- **Wiki**: Detaillierte Dokumentation
- **Discord**: Community Chat (Link folgt)

---

**Viel Erfolg mit TRINITY!** 🚀

Bei Fragen oder Problemen öffnen Sie ein GitHub Issue.
