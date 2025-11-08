//
//  EnhancedMemoryLayer.swift
//  TRINITY Vision Aid
//
//  Enhanced memory with rich metadata, importance, connections, and triggers
//

import Foundation
import CoreLocation

/// Erweiterte Memory-Struktur mit allen Metadaten
struct EnhancedVectorEntry: Codable, Identifiable {
    let id: UUID
    let embedding: [Float]
    let memoryLayer: MemoryLayerType

    // MARK: - Rich Metadata

    /// Basis-Informationen
    let objectType: String
    let description: String
    let confidence: Float

    /// Semantische Anreicherung
    let keywords: [String]              // ["Tisch", "Holz", "Hindernis"]
    let categories: [String]            // ["Möbel", "Innenraum"]
    let entities: [EntityInfo]          // Erkannte Entitäten

    /// Wichtigkeit & Relevanz
    var importance: Float               // 0.0 - 1.0
    var accessCount: Int                // Wie oft abgerufen?
    var lastAccessed: Date

    /// Temporale Informationen
    let timestamp: Date
    let timeOfDay: String               // "Morgen", "Nachmittag", etc.
    let dayOfWeek: String               // "Montag", "Dienstag"

    /// Räumliche Informationen
    let location: CLLocationCoordinate2D?
    let locationName: String?           // "Wohnzimmer", "Hauptbahnhof"
    let spatialData: SpatialData?

    /// Kontext
    let weatherContext: String?         // "Sonnig", "Regnerisch"
    let conversationContext: String?    // Kontext aus Gespräch
    let userIntent: String?             // "Navigation", "Objektsuche"

    // MARK: - Verknüpfungen (Graph-Struktur)

    /// Verbindungen zu anderen Memories
    var relatedMemories: [MemoryConnection]

    /// Thematische Cluster
    var clusterID: UUID?                // Gehört zu Cluster (z.B. "Wohnzimmer")

    /// Sequenzen (zeitliche Abfolge)
    var previousMemoryID: UUID?         // Vorheriges Memory
    var nextMemoryID: UUID?             // Nächstes Memory

    // MARK: - Trigger-Informationen

    /// Proaktive Trigger
    var triggers: [MemoryTrigger]

    // MARK: - Datenquellen

    let sourceType: String              // "Vision", "LiDAR", "Conversation"
    let quality: Float                  // Embedding-Qualität

    // MARK: - Lifecycle

    var consolidationCount: Int         // Wie oft konsolidiert?
    var lastConsolidated: Date?
    var expiresAt: Date?                // Optional: Auto-Delete

    init(
        id: UUID = UUID(),
        embedding: [Float],
        memoryLayer: MemoryLayerType,
        objectType: String,
        description: String,
        confidence: Float,
        keywords: [String] = [],
        categories: [String] = [],
        entities: [EntityInfo] = [],
        importance: Float = 0.5,
        timestamp: Date = Date(),
        timeOfDay: String,
        dayOfWeek: String,
        location: CLLocationCoordinate2D? = nil,
        locationName: String? = nil,
        spatialData: SpatialData? = nil,
        weatherContext: String? = nil,
        conversationContext: String? = nil,
        userIntent: String? = nil,
        relatedMemories: [MemoryConnection] = [],
        triggers: [MemoryTrigger] = [],
        sourceType: String,
        quality: Float
    ) {
        self.id = id
        self.embedding = embedding
        self.memoryLayer = memoryLayer
        self.objectType = objectType
        self.description = description
        self.confidence = confidence
        self.keywords = keywords
        self.categories = categories
        self.entities = entities
        self.importance = importance
        self.accessCount = 0
        self.lastAccessed = Date()
        self.timestamp = timestamp
        self.timeOfDay = timeOfDay
        self.dayOfWeek = dayOfWeek
        self.location = location
        self.locationName = locationName
        self.spatialData = spatialData
        self.weatherContext = weatherContext
        self.conversationContext = conversationContext
        self.userIntent = userIntent
        self.relatedMemories = relatedMemories
        self.clusterID = nil
        self.previousMemoryID = nil
        self.nextMemoryID = nil
        self.triggers = triggers
        self.sourceType = sourceType
        self.quality = quality
        self.consolidationCount = 0
        self.lastConsolidated = nil
        self.expiresAt = nil
    }
}

// MARK: - Supporting Types

struct EntityInfo: Codable {
    let name: String
    let type: String                    // "Person", "Place", "Object"
    let confidence: Float
}

/// Verbindung zwischen Memories (Graph-Edge)
struct MemoryConnection: Codable {
    let targetMemoryID: UUID
    let connectionType: ConnectionType
    let strength: Float                 // 0.0 - 1.0 (wie stark ist die Verbindung?)
    let context: String?                // Warum verbunden?

    enum ConnectionType: String, Codable {
        case spatialProximity           // Räumlich nah beieinander
        case temporalSequence           // Zeitlich aufeinanderfolgend
        case semanticSimilarity         // Inhaltlich ähnlich
        case causalRelation             // Kausal verbunden ("Tür öffnen → Raum betreten")
        case partOfWhole                // Teil-von-Beziehung ("Tisch → Wohnzimmer")
        case conversational             // Aus gleichem Gespräch
    }
}

/// Proaktiver Trigger
struct MemoryTrigger: Codable {
    let id: UUID
    let triggerType: TriggerType
    let condition: TriggerCondition
    let action: TriggerAction
    let priority: Int                   // Höher = wichtiger
    var isActive: Bool

    enum TriggerType: String, Codable {
        case objectDetected             // Bestimmtes Objekt gesehen
        case locationEntered            // Bestimmter Ort betreten
        case timeOfDay                  // Bestimmte Tageszeit
        case spatialProximity           // Nähe zu gespeichertem Ort
        case conversationKeyword        // Schlüsselwort im Gespräch
        case pattern                    // Wiederkehrendes Muster
    }

    struct TriggerCondition: Codable {
        let objectLabels: [String]?     // z.B. ["Auto", "Hund"]
        let locationRadius: Double?     // Meter um GPS-Punkt
        let locationCoordinate: CLLocationCoordinate2D?
        let timeRange: TimeRange?
        let keywords: [String]?
        let minConfidence: Float?

        struct TimeRange: Codable {
            let startHour: Int
            let endHour: Int
        }
    }

    struct TriggerAction: Codable {
        let actionType: ActionType
        let message: String?            // Nachricht an User
        let relatedMemoryIDs: [UUID]?   // Memories zum Abrufen
        let webSearchQuery: String?     // Internet-Suche
        let customData: [String: String]?

        enum ActionType: String, Codable {
            case notify                 // User benachrichtigen
            case speak                  // Sprachausgabe
            case retrieve               // Memories abrufen
            case webSearch              // Internet-Suche starten
            case log                    // Nur loggen
            case custom                 // Benutzerdefiniert
        }
    }

    init(
        id: UUID = UUID(),
        triggerType: TriggerType,
        condition: TriggerCondition,
        action: TriggerAction,
        priority: Int = 5,
        isActive: Bool = true
    ) {
        self.id = id
        self.triggerType = triggerType
        self.condition = condition
        self.action = action
        self.priority = priority
        self.isActive = isActive
    }
}

// MARK: - Helper Extensions

extension EnhancedVectorEntry {

    /// Fügt Verbindung zu anderem Memory hinzu
    mutating func addConnection(
        to memoryID: UUID,
        type: MemoryConnection.ConnectionType,
        strength: Float,
        context: String? = nil
    ) {
        let connection = MemoryConnection(
            targetMemoryID: memoryID,
            connectionType: type,
            strength: strength,
            context: context
        )
        relatedMemories.append(connection)
    }

    /// Erhöht Wichtigkeit basierend auf Zugriff
    mutating func incrementAccess() {
        accessCount += 1
        lastAccessed = Date()

        // Wichtigkeit steigt mit häufigem Zugriff
        let accessBonus = min(Float(accessCount) * 0.01, 0.3)
        importance = min(importance + accessBonus, 1.0)
    }

    /// Prüft ob Trigger aktiviert werden soll
    func shouldActivateTrigger(
        _ trigger: MemoryTrigger,
        currentLocation: CLLocation?,
        currentTime: Date,
        detectedObjects: [DetectedObject]
    ) -> Bool {
        guard trigger.isActive else { return false }

        let condition = trigger.condition

        switch trigger.triggerType {
        case .objectDetected:
            guard let requiredLabels = condition.objectLabels else { return false }
            let detectedLabels = detectedObjects.map { $0.label.lowercased() }
            return requiredLabels.contains(where: { requiredLabel in
                detectedLabels.contains(where: { $0.contains(requiredLabel.lowercased()) })
            })

        case .locationEntered:
            guard let currentLoc = currentLocation,
                  let targetCoord = condition.locationCoordinate,
                  let radius = condition.locationRadius else { return false }

            let targetLocation = CLLocation(
                latitude: targetCoord.latitude,
                longitude: targetCoord.longitude
            )
            let distance = currentLoc.distance(from: targetLocation)
            return distance <= radius

        case .timeOfDay:
            guard let timeRange = condition.timeRange else { return false }
            let hour = Calendar.current.component(.hour, from: currentTime)
            return hour >= timeRange.startHour && hour < timeRange.endHour

        case .spatialProximity:
            guard let currentLoc = currentLocation,
                  let myLoc = location,
                  let radius = condition.locationRadius else { return false }

            let myLocation = CLLocation(latitude: myLoc.latitude, longitude: myLoc.longitude)
            let distance = currentLoc.distance(from: myLocation)
            return distance <= radius

        default:
            return false
        }
    }

    /// Berechnet Ähnlichkeit zu anderem Memory
    func similarity(to other: EnhancedVectorEntry) -> Float {
        // Embedding-Ähnlichkeit
        let embeddingSim = cosineSimilarity(embedding, other.embedding)

        // Keyword-Überlappung
        let keywordSim = jaccardSimilarity(Set(keywords), Set(other.keywords))

        // Kategorie-Überlappung
        let categorySim = jaccardSimilarity(Set(categories), Set(other.categories))

        // Gewichteter Durchschnitt
        return (embeddingSim * 0.6) + (keywordSim * 0.2) + (categorySim * 0.2)
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        guard magnitudeA > 0, magnitudeB > 0 else { return 0.0 }
        return dotProduct / (magnitudeA * magnitudeB)
    }

    private func jaccardSimilarity<T: Hashable>(_ a: Set<T>, _ b: Set<T>) -> Float {
        let intersection = a.intersection(b)
        let union = a.union(b)
        guard !union.isEmpty else { return 0.0 }
        return Float(intersection.count) / Float(union.count)
    }
}

// MARK: - CLLocationCoordinate2D Codable (erweitert)

extension MemoryTrigger.TriggerCondition.TimeRange: Equatable {}
extension MemoryTrigger.TriggerCondition: Equatable {}
extension MemoryTrigger.TriggerAction: Equatable {}
extension MemoryTrigger: Equatable {}
extension MemoryConnection: Equatable {}
extension EntityInfo: Equatable {}

// MARK: - Usage Examples

/*
 // Memory mit reichhaltigen Metadaten erstellen:

 let memory = EnhancedVectorEntry(
     embedding: embedding,
     memoryLayer: .episodic,
     objectType: "Auto",
     description: "Rotes Auto auf Parkplatz",
     confidence: 0.92,
     keywords: ["Auto", "rot", "Parkplatz", "Fahrzeug"],
     categories: ["Fahrzeug", "Außenraum", "Gefahr"],
     entities: [
         EntityInfo(name: "Auto", type: "Object", confidence: 0.92)
     ],
     importance: 0.8,
     timeOfDay: "Nachmittag",
     dayOfWeek: "Montag",
     location: CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405),
     locationName: "Parkplatz Hauptbahnhof",
     triggers: [
         MemoryTrigger(
             triggerType: .objectDetected,
             condition: MemoryTrigger.TriggerCondition(
                 objectLabels: ["Auto"],
                 locationRadius: nil,
                 locationCoordinate: nil,
                 timeRange: nil,
                 keywords: nil,
                 minConfidence: 0.8
             ),
             action: MemoryTrigger.TriggerAction(
                 actionType: .speak,
                 message: "Achtung, Auto in der Nähe!",
                 relatedMemoryIDs: nil,
                 webSearchQuery: nil,
                 customData: nil
             ),
             priority: 9
         )
     ],
     sourceType: "Vision",
     quality: 0.95
 )

 // Verbindung hinzufügen:
 memory.addConnection(
     to: otherMemoryID,
     type: .spatialProximity,
     strength: 0.85,
     context: "Beide am Hauptbahnhof"
 )
 */
