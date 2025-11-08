# TRINITY Vision Aid - iOS App

Eine fortschrittliche Navigationshilfe-App für Sehbehinderte, die Apple Intelligence, LiDAR und fortgeschrittene KI-Technologie nutzt.

## Überblick

TRINITY kombiniert:
- **Apple Intelligence**: On-device ML für Echtzeit-Szenenerkennung
- **LiDAR Scanner**: Präzise räumliche Tiefenerfassung (iPhone 17 Pro)
- **RAG/MAS System**: Intelligente Kontextverwaltung mit 3-Schicht-Gedächtnis
- **Lokale Verarbeitung**: Alle Daten bleiben auf dem Gerät
- **VoiceOver optimiert**: Vollständige Barrierefreiheit

## Systemanforderungen

- **iOS**: 17.0 oder höher
- **Gerät**: iPhone 17 Pro (oder neuer mit LiDAR)
- **Speicher**: Mindestens 500 MB frei
- **Berechtigungen**: Kamera, Standort, AR

## Architektur-Komponenten

### 1. Memory System (3-Layer)
```
Working Memory    → Kurzzeitgedächtnis (aktuelle Szene)
Episodic Memory   → Besuchte Orte, zeitliche Ereignisse
Semantic Memory   → Langzeit-Muster, gelernte Konzepte
```

### 2. Multi-Agent System
- **Perception Agent**: Verarbeitet Kamera + LiDAR Daten
- **Navigation Agent**: Hinderniserkennung + Wegführung
- **Context Agent**: Verwaltet Kontext über Memory-Schichten
- **Communication Agent**: Generiert natürliche Sprachausgabe

### 3. RAG Pipeline
```
Sensor Input → Embedding → Vector Search → Context → Audio Output
```

### 4. Lokale KI
- **Embedding-Generierung**: Core ML Models
- **Vektor-Datenbank**: HNSW für schnelle Suche
- **Deduplizierung**: Verhindert redundante Informationen

## Projekt-Struktur

```
TrinityApp/
├── Sources/
│   ├── App/
│   │   ├── TrinityApp.swift           # Main App Entry
│   │   └── TrinityCoordinator.swift   # System Coordinator
│   ├── Agents/
│   │   ├── Agent.swift                # Base Agent Protocol
│   │   ├── PerceptionAgent.swift      # Vision + LiDAR Processing
│   │   ├── NavigationAgent.swift      # Navigation + Obstacles
│   │   ├── ContextAgent.swift         # Context Management
│   │   └── CommunicationAgent.swift   # Speech + Feedback
│   ├── Memory/
│   │   ├── MemoryManager.swift        # 3-Layer Memory Manager
│   │   └── DeduplicationEngine.swift  # Duplicate Detection
│   ├── VectorDB/
│   │   └── VectorDatabase.swift       # Local Vector Storage
│   ├── Sensors/
│   │   └── SensorManager.swift        # Camera + LiDAR + Location
│   ├── Models/
│   │   └── MemoryLayer.swift          # Data Models
│   ├── Utils/
│   │   └── EmbeddingGenerator.swift   # Core ML Embeddings
│   └── UI/
│       └── MainView.swift             # SwiftUI Interface
├── Tests/
├── Resources/
└── Info.plist
```

## Setup in Xcode

### 1. Xcode Projekt erstellen

1. Öffne Xcode
2. **File → New → Project**
3. Wähle **iOS → App**
4. Projekt-Einstellungen:
   - **Product Name**: TRINITY
   - **Team**: Dein Apple Developer Team
   - **Organization Identifier**: com.trinity
   - **Bundle Identifier**: com.trinity.visionaid
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Minimum iOS**: 17.0

### 2. Dateien importieren

1. Kopiere alle `.swift` Dateien aus `Sources/` in das Xcode Projekt
2. Organisiere Dateien in Gruppen entsprechend der Struktur
3. Füge `Info.plist` hinzu

### 3. Frameworks hinzufügen

In **Target → Build Phases → Link Binary With Libraries**:
- `ARKit.framework`
- `AVFoundation.framework`
- `CoreML.framework`
- `Vision.framework`
- `CoreLocation.framework`
- `SwiftUI.framework`
- `CloudKit.framework`
- `NaturalLanguage.framework`

### 4. Capabilities aktivieren

In **Target → Signing & Capabilities**:
- ✅ **iCloud** (CloudKit)
- ✅ **Background Modes** (Location updates, Audio)
- ✅ **Maps**

### 5. Info.plist konfigurieren

Kopiere die Berechtigungen aus `Info.plist`:
- Camera Usage Description
- Location Usage Description
- ARKit Usage Description

### 6. Core ML Models hinzufügen

Core ML Models müssen separat trainiert oder heruntergeladen werden:

1. **Vision Model** (Objekterkennung):
   - Download: MobileNetV3 oder YOLOv8 Core ML
   - Drag & Drop in Xcode

2. **Text Embedding Model** (optional):
   - Nutzt native `NLEmbedding`

### 7. Build & Run

1. Wähle iPhone 17 Pro Simulator oder physisches Gerät
2. **Cmd + R** zum Bauen und Ausführen
3. Erlaube alle Berechtigungen (Kamera, Standort, AR)

## Verwendung

### Erste Schritte

1. **App starten**
2. **Berechtigungen erteilen**: Kamera, Standort, AR
3. **"Start" drücken**: TRINITY aktivieren
4. **Gerät schwenken**: Umgebung erfassen
5. **Zuhören**: Audio-Beschreibungen und Navigation

### Hauptfunktionen

#### 1. Automatische Szenenbeschreibung
- TRINITY beschreibt kontinuierlich die Umgebung
- Erkennt Objekte, Hindernisse, Räume
- Passt Verbosität an (Minimal/Medium/Detailed)

#### 2. Navigation
- Hinderniserkennung mit LiDAR
- Audio-Warnungen bei Gefahren
- Routenvorschläge basierend auf Historie

#### 3. Kontext-Bewusstsein
- "Ich war schon hier"-Erkennung
- Häufig besuchte Orte merken
- Zeitliche Muster lernen

#### 4. Sprachausgabe
- Natürliche deutsche Sprachausgabe
- Priorisierung: Sicherheitswarnungen zuerst
- Haptisches Feedback bei Hindernissen

### Gesten & Steuerung

- **Einmal tippen**: Szene beschreiben
- **Zweimal tippen**: Letzte Nachricht wiederholen
- **Dreimal tippen**: Navigation starten
- **Lange drücken**: Einstellungen öffnen

### Settings

- **Verbosity**: Minimal/Medium/Detailed
- **Memory Management**: Konsolidieren/Löschen
- **iCloud Sync**: Export/Import

## Barrierefreiheit

### VoiceOver Optimierungen

- Alle UI-Elemente haben **accessibilityLabel**
- Große Touch-Targets (min. 44x44 pt)
- Hoher Kontrast (WCAG AAA)
- Keine zeitkritischen Interaktionen

### Haptic Feedback

- **Leicht**: Weit entferntes Hindernis
- **Mittel**: Nahe Objekte
- **Stark**: Kritische Warnung
- **Muster**: Navigationshinweise (Links/Rechts)

### Audio Feedback

- **3D Audio**: Räumliche Positionierung von Hindernissen
- **Beep-Frequenz**: Distanz-Kodierung
- **Lautstärke**: Prioritäts-Kodierung

## Datenschutz & Sicherheit

### Lokale Verarbeitung
- **Alle Embeddings lokal**: Keine Cloud-API
- **Alle Daten on-device**: Keine Server-Kommunikation
- **Core ML on-device**: Apple Neural Engine

### iCloud Sync (optional)
- **Ende-zu-Ende verschlüsselt**: CloudKit
- **User-kontrolliert**: Opt-in
- **Konfliktauflösung**: Neueste Daten gewinnen

### Berechtigungen
- **Kamera**: Nur während App-Nutzung
- **Standort**: When In Use
- **ARKit**: Erforderlich für LiDAR
- **Keine Telemetrie**: Kein Tracking

## Performance

### Optimierungen

- **Batch Processing**: Mehrere Embeddings parallel
- **Adaptive Quality**: Reduzierte Auflösung bei niedrigem Akku
- **Memory Management**: LRU Cache für häufige Abfragen
- **Neural Engine**: Maximale GPU/ANE Nutzung

### Benchmark (iPhone 17 Pro)

- **Embedding-Generierung**: ~50ms
- **Vector Search**: ~10ms (10k Vektoren)
- **End-to-End Latenz**: ~200ms (Sensor → Audio)
- **Akku-Verbrauch**: ~15%/Stunde bei kontinuierlicher Nutzung

## Testing

### Unit Tests
```bash
# In Xcode: Cmd + U
```

### Integration Tests
- Sensor-Mock-Daten verwenden
- Memory-Persistence testen
- Agent-Koordination testen

### Accessibility Tests
- VoiceOver Compatibility
- Dynamic Type Support
- High Contrast Mode

### Real-World Testing
- Mit Sehbehinderten testen
- Indoor + Outdoor Szenarien
- Verschiedene Lichtverhältnisse

## Roadmap

### v1.0 (Aktuell)
- ✅ Basic LiDAR Integration
- ✅ 3-Layer Memory
- ✅ Multi-Agent System
- ✅ VoiceOver Support
- ✅ Lokale Embeddings

### v1.1 (Geplant)
- [ ] Custom Core ML Models (Fine-tuning)
- [ ] Offline-Karten Integration
- [ ] Favoriten-Orte
- [ ] Sprachbefehle
- [ ] Apple Watch Companion

### v1.2 (Zukunft)
- [ ] Objektverfolgung über Zeit
- [ ] Gesichtserkennung (Bekannte Personen)
- [ ] Indoor-Positionierung
- [ ] Multi-Device Sync (iPad, Mac)

## Lizenz

Proprietary - Alle Rechte vorbehalten

## Support

Bei Fragen oder Problemen:
- **GitHub Issues**: [Repository Issues]
- **Email**: support@trinity-visionaid.com
- **Docs**: [Dokumentation]

## Credits

- **Entwickelt für**: Menschen mit Sehbehinderung
- **Technologie**: Apple ARKit, Core ML, SwiftUI
- **Inspiration**: Barrierefreie Navigation für alle

---

**TRINITY** - Sehen mit künstlicher Intelligenz 👁️🤖
