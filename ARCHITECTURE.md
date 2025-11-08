# TRINITY - Vision Aid App Architektur

## Übersicht
TRINITY ist eine iOS-App für Sehbehinderte, die Apple Intelligence, LiDAR und Kamera nutzt, um Navigationshilfe bereitzustellen. Die App verwendet ein RAG/MAS-System mit 3-Schicht-Gedächtnisstruktur.

## System-Komponenten

### 1. iOS App Layer (Swift/SwiftUI)

#### 1.1 Sensor-Integration
- **LiDAR Scanner**: Räumliche Tiefenerfassung (ARKit)
- **Kamera**: Objekterkennung, Texterkennung (Vision Framework)
- **Apple Intelligence**: On-device ML für Szenenerkennung

#### 1.2 User Interface
- **VoiceOver optimiert**: Vollständige Barrierefreiheit
- **Haptic Feedback**: Taktile Rückmeldungen
- **Audio-Navigation**: Sprachausgabe für Umgebungsbeschreibungen
- **Minimal Visual UI**: Große, kontrastreiche Elemente

### 2. TRINITY RAG/MAS System

#### 2.1 Three-Layer Memory Architecture

```
┌─────────────────────────────────────────┐
│   Working Memory (Kurzzeitgedächtnis)   │
│   - Aktuelle Szene                      │
│   - Momentane Objekte                   │
│   - Live-Sensor-Daten                   │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│  Episodic Memory (Episodisches Gedächtnis) │
│   - Besuchte Orte                       │
│   - Zeitliche Ereignisse                │
│   - Routen-Historie                     │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│  Semantic Memory (Semantisches Gedächtnis) │
│   - Gelernte Objekte                    │
│   - Raum-Konzepte                       │
│   - Langzeit-Muster                     │
└─────────────────────────────────────────┘
```

#### 2.2 Multi-Agent System (MAS)

**Agent-Typen:**
1. **Perception Agent**: Verarbeitet Sensor-Daten (Kamera, LiDAR)
2. **Navigation Agent**: Plant Routen, gibt Navigationshinweise
3. **Object Recognition Agent**: Identifiziert und katalogisiert Objekte
4. **Context Agent**: Verwaltet Kontext und Gedächtnisschichten
5. **Communication Agent**: Generiert Audio-Beschreibungen

#### 2.3 RAG (Retrieval-Augmented Generation)

**Pipeline:**
```
Sensor Input → Embedding → Vector Search → Context Retrieval → LLM → Audio Output
```

### 3. Data Layer

#### 3.1 Lokale Embedding-Generierung
- **Core ML Models**:
  - Apple's CLIP für Vision-Text Embeddings
  - Custom fine-tuned models für spezifische Objekte
  - Sentence Transformers für Text-Embeddings

#### 3.2 Vektor-Datenbank
- **Technologie**: HNSWLIB (Hierarchical Navigable Small World)
  - Schnelle ANN (Approximate Nearest Neighbor) Suche
  - Speichereffizient für mobile Geräte
  - Offline-fähig

**Schema:**
```swift
struct VectorEntry {
    id: UUID
    embedding: [Float]        // 512 oder 768 Dimensionen
    metadata: Metadata
    memoryLayer: MemoryLayer  // Working/Episodic/Semantic
    timestamp: Date
    location: CLLocation?
}

struct Metadata {
    objectType: String
    description: String
    confidence: Float
    tags: [String]
    spatialData: SpatialData?
}
```

#### 3.3 Datenspeicherung
- **Lokal**: SwiftData (iOS 17+) oder Core Data
- **iCloud**: CloudKit für Sync
  - Inkrementelles Sync
  - Konfliktauflösung
  - Offline-First-Architektur

### 4. Deduplizierung und Katalogisierung

#### 4.1 Non-Redundant Information Storage
```swift
class DeduplicationEngine {
    // Cosine-Similarity-Schwellwert für Duplikate
    let similarityThreshold: Float = 0.95

    func isDuplicate(newEmbedding: [Float], existingEmbeddings: [[Float]]) -> Bool
    func mergeInformation(existing: VectorEntry, new: VectorEntry) -> VectorEntry
    func updateConfidence(entry: VectorEntry, newObservation: Observation)
}
```

#### 4.2 Informations-Katalogisierung
- **Räumliche Indexierung**: Quadtree für Geo-Daten
- **Temporale Indexierung**: Zeitbasierte Gruppierung
- **Semantische Indexierung**: Hierarchische Kategorien

### 5. Privacy & Security

- **Alle Daten lokal**: Keine Cloud-Processing (außer optional iCloud Backup)
- **Ende-zu-Ende verschlüsselt**: iCloud-Daten verschlüsselt
- **Keine Tracking**: Keine Analytics, keine Telemetrie
- **User Control**: Vollständige Kontrolle über Datenlöschung

## Technologie-Stack

### iOS Development
- **Language**: Swift 5.9+
- **UI**: SwiftUI
- **Minimum iOS**: iOS 17.0 (für Apple Intelligence)
- **Frameworks**:
  - ARKit (LiDAR)
  - Vision (Objekterkennung)
  - Core ML (On-device ML)
  - AVFoundation (Audio/Kamera)
  - SwiftData (Persistenz)
  - CloudKit (iCloud Sync)

### Machine Learning
- **Core ML Models**:
  - MobileNetV3 (leichtgewichtig für Echtzeit)
  - YOLOv8 (Objekterkennung)
  - CLIP (Vision-Language)
  - Depth Estimation Models

### Vector Database
- **HNSWLIB**: C++ Library mit Swift Bindings
- **Alternative**: FAISS (Facebook AI Similarity Search)

## Workflow-Beispiel

### Szenario: Benutzer betritt Raum

1. **Perception Agent**:
   - LiDAR scannt Raum (3D-Mesh)
   - Kamera erfasst visuelle Daten
   - Vision Framework erkennt Objekte

2. **Embedding Generation**:
   - Objekte → Vision Embeddings
   - Raum-Layout → Spatial Embeddings
   - Text (Schilder) → Text Embeddings

3. **Vector Search**:
   - Query Working Memory: "Aktuelle Objekte"
   - Query Episodic Memory: "War ich schon hier?"
   - Query Semantic Memory: "Welche Objekttypen?"

4. **Deduplication**:
   - Vergleich mit existierenden Einträgen
   - Merge bei hoher Similarity
   - Update Confidence Scores

5. **Context Assembly**:
   - Context Agent aggregiert Informationen
   - Kombiniert alle Memory Layers
   - Erstellt kohärenten Kontext

6. **Navigation Agent**:
   - Analysiert Hindernisse
   - Plant sichere Route
   - Generiert Navigationsanweisungen

7. **Communication Agent**:
   - Erstellt natürliche Sprachbeschreibung
   - Priorisiert wichtige Informationen
   - Audio-Output via Text-to-Speech

8. **Memory Update**:
   - Working Memory: Aktuelle Objekte
   - Episodic Memory: "Raum betreten um 14:30"
   - Semantic Memory: Neue Objekttypen lernen

## Performance-Optimierungen

### Für iPhone 17 Pro
- **Neural Engine**: Maximale Nutzung für ML-Inferenz
- **GPU**: LiDAR-Processing und 3D-Rendering
- **Batch Processing**: Mehrere Embeddings parallel
- **Adaptive Quality**: Reduzierte Qualität bei niedrigem Akku

### Speicher-Management
- **Working Memory**: Max 100 Objekte (in-memory)
- **Episodic Memory**: Rolling Window (letzte 30 Tage)
- **Semantic Memory**: Unbegrenzt (disk-based)
- **Cache Strategy**: LRU Cache für häufige Abfragen

## Entwicklungs-Phasen

### Phase 1: Foundation (Woche 1-2)
- iOS Projekt Setup
- Basic UI (VoiceOver-optimiert)
- Kamera + LiDAR Integration
- Einfache Objekterkennung

### Phase 2: Trinity Core (Woche 3-4)
- 3-Layer Memory Architektur
- Vector Database Integration
- Embedding Generation (Core ML)
- Deduplication Engine

### Phase 3: Multi-Agent System (Woche 5-6)
- Agent Framework
- Perception, Navigation, Context Agents
- Inter-Agent Communication
- RAG Pipeline

### Phase 4: Advanced Features (Woche 7-8)
- iCloud Sync
- Advanced Navigation
- Custom ML Model Training
- Performance Optimierung

### Phase 5: Testing & Refinement (Woche 9-10)
- Accessibility Testing
- Real-World Testing mit Sehbehinderten
- Performance Profiling
- Bug Fixes

## Nächste Schritte

1. Xcode Projekt erstellen
2. Basic SwiftUI App mit VoiceOver
3. LiDAR + Kamera Integration testen
4. Core ML Models integrieren
5. Vector Database implementieren
