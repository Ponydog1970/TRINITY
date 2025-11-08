//
//  AdvancedEmbeddingGenerator.swift
//  TRINITY Vision Aid
//
//  Enhanced embedding generation with semantic richness
//

import Foundation
import CoreML
import Vision
import NaturalLanguage

/// Advanced embedding generator with semantic metadata
class AdvancedEmbeddingGenerator: EmbeddingGenerator {

    // MARK: - Enhanced Embedding with Metadata

    struct RichEmbedding {
        let vector: [Float]                  // 512D embedding vector
        let metadata: EmbeddingMetadata
        let quality: Float                   // 0.0 - 1.0
        let sourceType: SourceType

        enum SourceType {
            case vision         // Von Kamera/Bild
            case text          // Von Text/Sprache
            case spatial       // Von LiDAR
            case multimodal    // Kombiniert
        }
    }

    struct EmbeddingMetadata {
        // Semantische Info
        let keywords: [String]              // Extrahierte Schlüsselwörter
        let entities: [Entity]              // Erkannte Entitäten (Person, Ort, Objekt)
        let sentiment: Float?               // Optional: Sentiment (-1 bis +1)

        // Kontext
        let timestamp: Date
        let location: CLLocationCoordinate2D?
        let weatherContext: String?         // "sonnig", "regnerisch"
        let timeOfDay: TimeOfDay           // morning, afternoon, evening, night

        // Hierarchische Tags
        let categories: [String]            // ["Möbel", "Innenraum", "Hindernis"]
        let importance: Float               // 0.0 - 1.0 (wie wichtig ist das?)

        // Verknüpfungen
        var relatedMemoryIDs: [UUID]       // Links zu anderen Memories
        var conversationContext: String?   // Kontext aus Gespräch/Interaktion
    }

    struct Entity {
        let name: String
        let type: EntityType
        let confidence: Float

        enum EntityType {
            case person
            case place
            case object
            case event
            case organization
        }
    }

    enum TimeOfDay: String, Codable {
        case morning = "Morgen"
        case afternoon = "Nachmittag"
        case evening = "Abend"
        case night = "Nacht"

        static func from(hour: Int) -> TimeOfDay {
            switch hour {
            case 5..<12: return .morning
            case 12..<17: return .afternoon
            case 17..<21: return .evening
            default: return .night
            }
        }
    }

    // MARK: - Rich Embedding Generation

    /// Generiert semantisch reichhaltiges Embedding
    func generateRichEmbedding(
        from observation: Observation,
        conversationContext: String? = nil
    ) async throws -> RichEmbedding {

        // 1. Basis-Embedding generieren
        let baseEmbedding = try await generateEmbedding(from: observation)

        // 2. Semantische Analyse
        let keywords = extractKeywords(from: observation)
        let entities = extractEntities(from: observation)

        // 3. Kontext sammeln
        let timeOfDay = TimeOfDay.from(hour: Calendar.current.component(.hour, from: Date()))

        // 4. Kategorisierung
        let categories = categorize(observation: observation)

        // 5. Wichtigkeit berechnen
        let importance = calculateImportance(
            observation: observation,
            entities: entities,
            timeOfDay: timeOfDay
        )

        // 6. Metadata zusammenstellen
        let metadata = EmbeddingMetadata(
            keywords: keywords,
            entities: entities,
            sentiment: nil,
            timestamp: observation.timestamp,
            location: observation.location?.coordinate,
            weatherContext: nil, // Kann später erweitert werden
            timeOfDay: timeOfDay,
            categories: categories,
            importance: importance,
            relatedMemoryIDs: [],
            conversationContext: conversationContext
        )

        // 7. Quality Score
        let quality = assessQuality(
            embedding: baseEmbedding,
            metadata: metadata,
            observation: observation
        )

        return RichEmbedding(
            vector: baseEmbedding,
            metadata: metadata,
            quality: quality,
            sourceType: .multimodal
        )
    }

    // MARK: - Semantic Extraction

    private func extractKeywords(from observation: Observation) -> [String] {
        var keywords: [String] = []

        // Von erkannten Objekten
        keywords += observation.detectedObjects.map { $0.label }

        // NLP auf Objekt-Labels
        let text = observation.detectedObjects.map { $0.label }.joined(separator: " ")

        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text

        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if let tag = tag {
                keywords.append(String(text[range]))
            }
            return true
        }

        return Array(Set(keywords)) // Deduplizieren
    }

    private func extractEntities(from observation: Observation) -> [Entity] {
        var entities: [Entity] = []

        for object in observation.detectedObjects {
            let entityType = classifyEntityType(label: object.label)

            let entity = Entity(
                name: object.label,
                type: entityType,
                confidence: object.confidence
            )

            entities.append(entity)
        }

        return entities
    }

    private func classifyEntityType(label: String) -> Entity.EntityType {
        let lowercased = label.lowercased()

        // Einfache Klassifikation (kann mit ML verbessert werden)
        if lowercased.contains("person") || lowercased.contains("mensch") {
            return .person
        } else if lowercased.contains("straße") || lowercased.contains("platz") {
            return .place
        } else if lowercased.contains("firma") || lowercased.contains("geschäft") {
            return .organization
        } else {
            return .object
        }
    }

    private func categorize(observation: Observation) -> [String] {
        var categories: [String] = []

        for object in observation.detectedObjects {
            let objectCategories = categorizeObject(object.label)
            categories += objectCategories
        }

        return Array(Set(categories))
    }

    private func categorizeObject(_ label: String) -> [String] {
        let lowercased = label.lowercased()
        var categories: [String] = []

        // Hierarchische Kategorisierung
        if ["tisch", "stuhl", "sofa", "schrank"].contains(lowercased) {
            categories += ["Möbel", "Innenraum", "Hindernis"]
        }

        if ["auto", "bus", "fahrrad"].contains(lowercased) {
            categories += ["Fahrzeug", "Außenraum", "Beweglich", "Gefahr"]
        }

        if ["hund", "katze", "vogel"].contains(lowercased) {
            categories += ["Tier", "Lebendig", "Beweglich"]
        }

        if ["tür", "fenster", "treppe"].contains(lowercased) {
            categories += ["Navigation", "Durchgang", "Wichtig"]
        }

        if ["wand", "boden", "decke"].contains(lowercased) {
            categories += ["Struktur", "Statisch"]
        }

        return categories
    }

    // MARK: - Importance Calculation

    private func calculateImportance(
        observation: Observation,
        entities: [Entity],
        timeOfDay: TimeOfDay
    ) -> Float {
        var importance: Float = 0.5 // Basis

        // 1. Proximity (näher = wichtiger)
        if let closestObject = observation.detectedObjects
            .compactMap({ $0.spatialData })
            .min(by: { $0.depth < $1.depth }) {

            if closestObject.depth < 1.0 {
                importance += 0.3 // Sehr nah!
            } else if closestObject.depth < 2.0 {
                importance += 0.15
            }
        }

        // 2. Gefährliche Objekte wichtiger
        let dangerousKeywords = ["auto", "treppe", "stufe", "loch", "abgrund"]
        for entity in entities {
            if dangerousKeywords.contains(where: { entity.name.lowercased().contains($0) }) {
                importance += 0.2
            }
        }

        // 3. Personen wichtiger
        if entities.contains(where: { $0.type == .person }) {
            importance += 0.15
        }

        // 4. Navigationselemente wichtiger
        let navKeywords = ["tür", "ausgang", "eingang", "treppe"]
        for entity in entities {
            if navKeywords.contains(where: { entity.name.lowercased().contains($0) }) {
                importance += 0.1
            }
        }

        // 5. Nachts sind Hindernisse wichtiger
        if timeOfDay == .night {
            importance += 0.1
        }

        return min(importance, 1.0)
    }

    private func assessQuality(
        embedding: [Float],
        metadata: EmbeddingMetadata,
        observation: Observation
    ) -> Float {
        var quality: Float = 0.5

        // 1. Embedding-Qualität (Magnitude check)
        let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        if magnitude > 0.9 && magnitude < 1.1 {
            quality += 0.2 // Gut normalisiert
        }

        // 2. Confidence der Objekte
        let avgConfidence = observation.detectedObjects.isEmpty ? 0.0 :
            observation.detectedObjects.map { $0.confidence }.reduce(0, +) / Float(observation.detectedObjects.count)
        quality += avgConfidence * 0.3

        // 3. Anzahl Objekte (mehr = besser)
        if observation.detectedObjects.count > 3 {
            quality += 0.1
        }

        // 4. Metadata-Reichhaltigkeit
        if !metadata.keywords.isEmpty {
            quality += 0.1
        }
        if metadata.location != nil {
            quality += 0.1
        }

        return min(quality, 1.0)
    }
}

// MARK: - Usage Example

/*
 let advancedGen = AdvancedEmbeddingGenerator()

 let richEmbedding = try await advancedGen.generateRichEmbedding(
     from: observation,
     conversationContext: "User fragte nach Hindernissen"
 )

 print("Embedding Quality: \(richEmbedding.quality)")
 print("Importance: \(richEmbedding.metadata.importance)")
 print("Keywords: \(richEmbedding.metadata.keywords)")
 print("Categories: \(richEmbedding.metadata.categories)")
 */
