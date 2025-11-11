# RAG-System Dokumentation

## Übersicht

Das RAG-System (Retrieval-Augmented Generation) ermöglicht es der TRINITY-App, Benutzeranfragen zu beantworten, indem relevante Informationen aus dem Gedächtnissystem abgerufen und kontextuelle Antworten generiert werden.

## Architektur

Das RAG-System besteht aus folgenden Komponenten:

1. **RAGAgent**: Hauptagent für die Verarbeitung von Queries
2. **RAGInput/RAGOutput**: Datenstrukturen für Input/Output
3. **Integration in TrinityCoordinator**: Benutzerfreundliche Query-Interface

## Verwendung

### Einfache Query

```swift
let coordinator = try TrinityCoordinator()
try await coordinator.start()

// Einfache Frage stellen
let answer = try await coordinator.askQuestion("Was ist vor mir?")
print(answer) // "Ich sehe: Tisch, Stuhl, Tür"

// Umgebung beschreiben
let description = try await coordinator.describeSurroundings()
print(description) // "Erkannte Objekte: Tisch, Stuhl, Tür..."

// Gedächtnis abfragen
let memoryAnswer = try await coordinator.queryMemory("Was habe ich hier schon mal gesehen?")
print(memoryAnswer) // "In den letzten Tagen: 5 ähnliche Situationen..."
```

### Erweiterte Query mit Optionen

```swift
let ragOutput = try await coordinator.processQuery(
    "Wie komme ich zum Ausgang?",
    queryType: .navigation,
    includeTemporalContext: true,
    includeSpatialContext: true
)

print("Antwort: \(ragOutput.answer)")
print("Konfidenz: \(ragOutput.confidence)")
print("Verarbeitungszeit: \(ragOutput.processingTime)s")
print("Quellen: \(ragOutput.sources.count)")
```

### Query-Typen

Das System unterstützt verschiedene Query-Typen:

- **`.question`**: Allgemeine Fragen ("Was ist das?")
- **`.description`**: Beschreibungsanfragen ("Beschreibe die Szene")
- **`.navigation`**: Navigationsanfragen ("Wie komme ich zu...")
- **`.memory`**: Gedächtnisabfragen ("Was habe ich hier schon mal gesehen?")
- **`.general`**: Allgemeine Anfragen

Der Query-Typ wird automatisch erkannt, kann aber auch manuell angegeben werden.

## Funktionsweise

1. **Query-Embedding**: Die Benutzeranfrage wird in einen Vektor umgewandelt
2. **Retrieval**: Ähnliche Einträge werden aus dem Vector-Datenbank abgerufen
3. **Kontext-Erweiterung**: Optional werden temporale und räumliche Kontexte hinzugefügt
4. **Antwort-Generierung**: Basierend auf dem Kontext wird eine Antwort generiert
5. **Konfidenz-Berechnung**: Die Zuverlässigkeit der Antwort wird berechnet

## Memory-Layer Auswahl

Das System wählt automatisch die relevanten Memory-Layer basierend auf dem Query-Typ:

- **Fragen/Beschreibungen**: Working Memory + Episodic Memory
- **Navigation**: Episodic Memory + Semantic Memory
- **Gedächtnisabfragen**: Alle Layer
- **Allgemein**: Semantic Memory priorisiert

## Konfidenz-Score

Der Konfidenz-Score (0.0 - 1.0) basiert auf:
- Durchschnittliche Ähnlichkeit der abgerufenen Kontexte
- Anzahl hochwertiger Quellen
- Aktualität der Informationen

## Quellen-Tracking

Jede Antwort enthält Informationen über die verwendeten Quellen:
- Welche Memory-Einträge wurden verwendet
- Relevanz-Score jedes Eintrags
- Beitrag jedes Eintrags zur Antwort

## Beispiel-Workflow

```swift
// 1. System starten
let coordinator = try TrinityCoordinator()
try await coordinator.start()

// 2. System sammelt Beobachtungen (automatisch)
// ... System läuft und sammelt Daten ...

// 3. Benutzer stellt Frage
let answer = try await coordinator.askQuestion("Was ist vor mir?")

// 4. System:
//    - Generiert Embedding für die Frage
//    - Sucht ähnliche Einträge in Working Memory
//    - Findet: "Tisch", "Stuhl", "Tür"
//    - Generiert Antwort: "Ich sehe: Tisch, Stuhl, Tür"
//    - Spricht die Antwort aus

// 5. Benutzer fragt nach Erinnerungen
let memory = try await coordinator.queryMemory("Was habe ich hier schon mal gesehen?")
// System durchsucht alle Memory-Layer und findet ähnliche Situationen
```

## Erweiterte Features

### Temporaler Kontext
Wenn aktiviert, werden aktuelle Ereignisse und historische Muster in die Antwort einbezogen.

### Räumlicher Kontext
Wenn aktiviert, werden nahegelegene Orte und bekannte Routen berücksichtigt.

## Performance

- **Query-Verarbeitung**: < 200ms (typisch)
- **Embedding-Generierung**: < 100ms
- **Vector-Suche**: < 20ms (bei 10k Einträgen)
- **Antwort-Generierung**: < 50ms

## Best Practices

1. **Spezifische Fragen**: Je spezifischer die Frage, desto besser die Antwort
2. **Kontext aktivieren**: Für bessere Antworten temporale und räumliche Kontexte aktivieren
3. **Geduld**: Lassen Sie das System zunächst Daten sammeln, bevor Sie Fragen stellen
4. **Query-Typ**: Lassen Sie den Typ automatisch erkennen oder geben Sie ihn explizit an
