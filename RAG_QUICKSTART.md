# 🚀 RAG System - Quick Start Guide

Schneller Einstieg in das RAG-System für TRINITY Vision Aid.

---

## ⚡️ Installation (3 Minuten)

### 1. Projekt Setup

Das RAG-System ist bereits im TRINITY Projekt integriert:

```
TrinityApp/Sources/RAG/
├── RAGRetriever.swift      → Retrieval Logic
├── RAGQueryEngine.swift    → Query Orchestration  
├── RAGExamples.swift       → Usage Examples
├── README.md               → Full Documentation
└── TwitterSnippets.md      → Social Media Content
```

### 2. Dependencies

Alle Dependencies sind bereits vorhanden:
- ✅ VectorDatabase
- ✅ EmbeddingGenerator
- ✅ MemoryManager

Keine zusätzlichen Pakete nötig!

---

## 🎯 Erste Schritte (5 Minuten)

### Basic Query

```swift
import Foundation

// 1. Setup (einmalig)
let vectorDB = try VectorDatabase()
let embeddings = try EmbeddingGenerator()

let ragEngine = RAGQueryEngine(
    vectorDatabase: vectorDB,
    embeddingGenerator: embeddings
)

// 2. Query ausführen
let response = try await ragEngine.query("Was ist vor mir?")

// 3. Ergebnis ausgeben
print("Antwort: \(response.answer)")
print("Confidence: \(response.confidence)")
print("Quellen: \(response.sources.count)")
```

**Output:**
```
Antwort: Stuhl, 2.5m entfernt
Confidence: 0.87
Quellen: 3
```

---

## 📸 Vision-basierte Query (3 Minuten)

```swift
// Mit Kamera-Input
let observation = getCurrentObservation() // von SensorManager

let response = try await ragEngine.query(
    observation: observation,
    question: "Was sehe ich gerade?"
)

print(response.answer)
```

**Was passiert?**
1. Observation → Multimodal Embedding
2. VectorDB Search → Ähnliche Memories
3. Context Building → Frühere Beobachtungen
4. Answer Generation → Kontext-bewusste Antwort

---

## 🔍 Advanced Features

### 1. Custom Configuration

```swift
let config = RetrievalConfig(
    topK: 5,                    // Top 5 Dokumente
    similarityThreshold: 0.7,   // Min 70% Ähnlichkeit
    layers: [.working, .episodic], // Nur diese Layers
    reranking: true             // Reranking aktivieren
)

let response = try await ragEngine.query(
    "Hindernisse in der Nähe?",
    config: config
)
```

### 2. Hybrid Search

```swift
let retriever = RAGRetriever(
    vectorDatabase: vectorDB,
    embeddingGenerator: embeddings
)

let docs = try await retriever.hybridSearch(
    query: "gefährliche Objekte",
    keywords: ["Hindernis", "Gefahr", "Warnung"]
)

for doc in docs {
    print("\(doc.content) (Score: \(doc.similarity))")
}
```

### 3. Conversational RAG

```swift
var history: [RAGResponse] = []

// Turn 1
let r1 = try await ragEngine.query("Was ist links?")
history.append(r1)
print("Q: Was ist links?")
print("A: \(r1.answer)\n")

// Turn 2 (mit Context)
let r2 = try await ragEngine.conversationalQuery(
    question: "Wie weit weg?",
    history: history
)
history.append(r2)
print("Q: Wie weit weg?")
print("A: \(r2.answer)")
```

---

## 🎯 Use Cases

### Navigation Assistant

```swift
// Hindernisse erkennen
let response = try await ragEngine.query(
    "Sind Hindernisse in 2 Metern?",
    config: RetrievalConfig(
        topK: 5,
        similarityThreshold: 0.6,
        layers: [.working],
        reranking: true
    )
)

if response.confidence > 0.7 {
    print("⚠️ WARNUNG: \(response.answer)")
}
```

### Location Memory

```swift
// Orte wiedererkennen
let response = try await ragEngine.query(
    "War ich schon hier?",
    config: RetrievalConfig(
        topK: 3,
        similarityThreshold: 0.75,
        layers: [.episodic, .semantic],
        reranking: true
    )
)

print("Location Check: \(response.answer)")
print("Basierend auf \(response.sources.count) früheren Besuchen")
```

### Object Recognition

```swift
// Objekte identifizieren
let response = try await ragEngine.query(
    observation: currentFrame,
    question: "Was ist dieses Objekt und wann sah ich es zuletzt?"
)

print(response.answer)
// → "Laptop, zuletzt gesehen: heute 14:30 Uhr"
```

---

## 📊 Performance Tuning

### Schneller (für Real-time)

```swift
let fastConfig = RetrievalConfig(
    topK: 3,                    // Weniger Dokumente
    similarityThreshold: 0.8,   // Höherer Threshold
    layers: [.working],         // Nur Working Memory
    reranking: false            // Kein Reranking
)

// → <100ms Response Time
```

### Genauer (für komplexe Queries)

```swift
let accurateConfig = RetrievalConfig(
    topK: 10,                   // Mehr Dokumente
    similarityThreshold: 0.5,   // Niedriger Threshold
    layers: [.working, .episodic, .semantic], // Alle Layers
    reranking: true             // Mit Reranking
)

// → ~300ms Response Time, höhere Genauigkeit
```

---

## 🐛 Troubleshooting

### Problem: Keine Ergebnisse

```swift
let response = try await ragEngine.query("test")
if response.sources.isEmpty {
    print("Keine Dokumente gefunden!")
    print("→ Threshold zu hoch?")
    print("→ VectorDB leer?")
    print("→ Query zu spezifisch?")
}
```

**Lösung**: Threshold senken

```swift
let config = RetrievalConfig(
    topK: 10,
    similarityThreshold: 0.3,  // ← Niedriger
    layers: [.working, .episodic, .semantic],
    reranking: true
)
```

### Problem: Langsame Performance

```swift
// Messen
let start = Date()
let response = try await ragEngine.query("test")
let time = Date().timeIntervalSince(start)
print("Query Time: \(time * 1000)ms")
```

**Lösung**: Optimieren

```swift
// 1. Weniger Dokumente
topK: 3 // statt 10

// 2. Weniger Layers
layers: [.working] // statt alle

// 3. Kein Reranking
reranking: false
```

### Problem: Low Confidence

```swift
if response.confidence < 0.5 {
    print("⚠️ Low confidence: \(response.confidence)")
    print("→ Mehr Training Data?")
    print("→ Query umformulieren?")
}
```

**Lösung**: Query verbessern

```swift
// Schlecht: "Objekt?"
// Gut: "Welches Objekt ist 2m vor mir?"

// Schlecht: "Links?"
// Gut: "Was befindet sich links von mir?"
```

---

## 📚 Nächste Schritte

1. **Beispiele durchgehen**: `RAGExamples.swift`
2. **Dokumentation lesen**: `RAG/README.md`
3. **Integration in App**: Mit SensorManager verbinden
4. **Testing**: Unit Tests schreiben
5. **Optimization**: Performance tuning

---

## 🔗 Ressourcen

- [Full Documentation](./TrinityApp/Sources/RAG/README.md)
- [Code Examples](./TrinityApp/Sources/RAG/RAGExamples.swift)
- [Twitter Guide](./RAG_TWITTER_GUIDE.md)
- [Architecture](./ARCHITECTURE.md)
- [Project Overview](./PROJECT_OVERVIEW.md)

---

## 💡 Pro Tips

### 1. Caching für bessere Performance

```swift
// Cache RAG Engine (einmalig erstellen)
class RAGService {
    static let shared = RAGService()
    
    private let ragEngine: RAGQueryEngine
    
    private init() {
        let vectorDB = try! VectorDatabase()
        let embeddings = try! EmbeddingGenerator()
        
        self.ragEngine = RAGQueryEngine(
            vectorDatabase: vectorDB,
            embeddingGenerator: embeddings
        )
    }
    
    func query(_ question: String) async throws -> RAGResponse {
        return try await ragEngine.query(question)
    }
}

// Usage
let response = try await RAGService.shared.query("test")
```

### 2. Batch Processing für Multiple Queries

```swift
let questions = [
    "Was sehe ich?",
    "Wo bin ich?",
    "Gibt es Hindernisse?"
]

let responses = try await ragEngine.batchQuery(questions: questions)

for (q, r) in zip(questions, responses) {
    print("Q: \(q)")
    print("A: \(r.answer)\n")
}
```

### 3. Error Handling

```swift
do {
    let response = try await ragEngine.query("test")
    print(response.answer)
} catch EmbeddingError.emptyText {
    print("Query darf nicht leer sein")
} catch {
    print("Fehler: \(error.localizedDescription)")
}
```

---

## ⏱️ Timing Guide

**Setup**: 1 Minute
- VectorDB initialisieren
- EmbeddingGenerator laden
- RAGQueryEngine erstellen

**First Query**: 2 Minuten
- Query schreiben
- Ausführen
- Ergebnis verarbeiten

**Custom Config**: 1 Minute
- RetrievalConfig anpassen
- Testen
- Optimieren

**Integration**: 5 Minuten
- Mit SensorManager verbinden
- UI Updates
- Error Handling

**Total**: ~10 Minuten bis zur ersten funktionierenden Integration! 🚀

---

## ✅ Checklist

- [ ] VectorDatabase initialisiert
- [ ] EmbeddingGenerator geladen
- [ ] RAGQueryEngine erstellt
- [ ] Erste Query ausgeführt
- [ ] Ergebnis validiert
- [ ] Custom Config getestet
- [ ] Error Handling implementiert
- [ ] Performance gemessen
- [ ] Integration in App
- [ ] Unit Tests geschrieben

---

## 🎓 Learning Path

**Beginner** (30 Minuten):
1. Basic Query ausführen
2. Ergebnis verstehen
3. Config anpassen

**Intermediate** (1 Stunde):
1. Vision-based Query
2. Conversational RAG
3. Custom Retrieval Config

**Advanced** (2 Stunden):
1. Hybrid Search
2. Performance Optimization
3. Custom Answer Generation
4. Integration in App

---

Viel Erfolg! 🚀

Bei Fragen: GitHub Issues oder Twitter DM
