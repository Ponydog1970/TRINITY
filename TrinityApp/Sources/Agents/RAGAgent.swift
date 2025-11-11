//
//  RAGAgent.swift
//  TRINITY Vision Aid
//
//  Retrieval-Augmented Generation Agent for answering queries using memory context
//

import Foundation
import CoreLocation

/// Input for RAG agent
struct RAGInput {
    let query: String
    let queryType: RAGQueryType
    let maxResults: Int
    let memoryLayers: [MemoryLayerType]?
    let includeTemporalContext: Bool
    let includeSpatialContext: Bool
}

/// Output from RAG agent
struct RAGOutput {
    let answer: String
    let relevantContext: [VectorEntry]
    let confidence: Float
    let sources: [RAGSource]
    let queryEmbedding: [Float]
    let processingTime: TimeInterval
}

/// Type of query being processed
enum RAGQueryType {
    case question        // "Was ist vor mir?"
    case description     // "Beschreibe die Szene"
    case navigation      // "Wie komme ich zu..."
    case memory          // "Was habe ich hier schon mal gesehen?"
    case general         // Allgemeine Anfrage
}

/// Source of information used in the answer
struct RAGSource {
    let entry: VectorEntry
    let relevanceScore: Float
    let contribution: String  // What this source contributed to the answer
}

/// Retrieval-Augmented Generation Agent
/// Answers user queries by retrieving relevant context from memory and generating contextual responses
class RAGAgent: BaseAgent<RAGInput, RAGOutput> {
    private let memoryManager: MemoryManager
    private let embeddingGenerator: EmbeddingGenerator
    private let contextAgent: ContextAgent
    
    // Configuration
    private let defaultMaxResults = 10
    private let minRelevanceThreshold: Float = 0.5
    private let highRelevanceThreshold: Float = 0.8
    
    init(
        memoryManager: MemoryManager,
        embeddingGenerator: EmbeddingGenerator,
        contextAgent: ContextAgent
    ) {
        self.memoryManager = memoryManager
        self.embeddingGenerator = embeddingGenerator
        self.contextAgent = contextAgent
        super.init(name: "RAGAgent")
    }
    
    override func process(_ input: RAGInput) async throws -> RAGOutput {
        let startTime = Date()
        
        // Step 1: Generate embedding for the query
        let queryEmbedding = try await embeddingGenerator.generateEmbedding(from: input.query)
        
        // Step 2: Determine which memory layers to search
        let layersToSearch = input.memoryLayers ?? determineRelevantLayers(for: input.queryType)
        
        // Step 3: Retrieve relevant context from memory
        let relevantContext = try await retrieveContext(
            queryEmbedding: queryEmbedding,
            layers: layersToSearch,
            maxResults: input.maxResults
        )
        
        // Step 4: Filter by relevance threshold
        let filteredContext = relevantContext.filter { entry in
            entry.similarity(to: queryEmbedding) >= minRelevanceThreshold
        }
        
        // Step 5: Enhance with temporal/spatial context if requested
        var enhancedContext = filteredContext
        if input.includeTemporalContext || input.includeSpatialContext {
            enhancedContext = try await enhanceWithContext(
                context: filteredContext,
                includeTemporal: input.includeTemporalContext,
                includeSpatial: input.includeSpatialContext
            )
        }
        
        // Step 6: Generate answer based on query type and context
        let answer = try await generateAnswer(
            query: input.query,
            queryType: input.queryType,
            context: enhancedContext,
            queryEmbedding: queryEmbedding
        )
        
        // Step 7: Calculate confidence score
        let confidence = calculateConfidence(
            context: enhancedContext,
            queryEmbedding: queryEmbedding
        )
        
        // Step 8: Identify sources and their contributions
        let sources = identifySources(
            context: enhancedContext,
            queryEmbedding: queryEmbedding,
            answer: answer
        )
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return RAGOutput(
            answer: answer,
            relevantContext: enhancedContext,
            confidence: confidence,
            sources: sources,
            queryEmbedding: queryEmbedding,
            processingTime: processingTime
        )
    }
    
    // MARK: - Context Retrieval
    
    private func retrieveContext(
        queryEmbedding: [Float],
        layers: [MemoryLayerType],
        maxResults: Int
    ) async throws -> [VectorEntry] {
        var allResults: [VectorEntry] = []
        
        // Search each layer
        for layer in layers {
            let layerResults = try await memoryManager.search(
                embedding: queryEmbedding,
                topK: maxResults
            )
            
            // Filter to only this layer
            let filtered = layerResults.filter { $0.memoryLayer == layer }
            allResults.append(contentsOf: filtered)
        }
        
        // Sort by relevance and remove duplicates
        let uniqueResults = Array(Set(allResults.map { $0.id }))
            .compactMap { id in
                allResults.first { $0.id == id }
            }
            .sorted { entry1, entry2 in
                entry1.similarity(to: queryEmbedding) > entry2.similarity(to: queryEmbedding)
            }
            .prefix(maxResults)
        
        return Array(uniqueResults)
    }
    
    private func determineRelevantLayers(for queryType: RAGQueryType) -> [MemoryLayerType] {
        switch queryType {
        case .question, .description:
            // Current scene - working memory most relevant
            return [.working, .episodic]
        case .navigation:
            // Navigation - episodic memory for routes
            return [.episodic, .semantic]
        case .memory:
            // Historical queries - all layers
            return [.working, .episodic, .semantic]
        case .general:
            // General queries - prioritize semantic memory
            return [.semantic, .episodic, .working]
        }
    }
    
    private func enhanceWithContext(
        context: [VectorEntry],
        includeTemporal: Bool,
        includeSpatial: Bool
    ) async throws -> [VectorEntry] {
        var enhanced = context
        
        // Get current observation (would need to be passed or retrieved)
        // For now, we'll use the most recent entry as a proxy
        guard let mostRecent = context.first else {
            return enhanced
        }
        
        // Create a mock observation for context agent
        let mockObservation = Observation(
            timestamp: mostRecent.metadata.timestamp,
            cameraImage: nil,
            depthMap: nil,
            detectedObjects: [],
            location: mostRecent.metadata.location.map { coord in
                CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            },
            deviceOrientation: Orientation(pitch: 0, yaw: 0, roll: 0)
        )
        
        let contextInput = ContextInput(
            currentObservation: mockObservation,
            query: nil,
            memorySearchResults: context
        )
        
        let contextOutput = try await contextAgent.process(contextInput)
        
        // Add temporal context if requested
        if includeTemporal {
            enhanced.append(contentsOf: contextOutput.temporalContext.recentEvents)
            enhanced.append(contentsOf: contextOutput.temporalContext.historicalPatterns)
        }
        
        // Add spatial context if requested
        if includeSpatial {
            enhanced.append(contentsOf: contextOutput.spatialContext.nearbyPlaces)
        }
        
        // Remove duplicates and limit
        let uniqueEnhanced = Array(Set(enhanced.map { $0.id }))
            .compactMap { id in enhanced.first { $0.id == id } }
            .prefix(20)
        
        return Array(uniqueEnhanced)
    }
    
    // MARK: - Answer Generation
    
    private func generateAnswer(
        query: String,
        queryType: RAGQueryType,
        context: [VectorEntry],
        queryEmbedding: [Float]
    ) async throws -> String {
        // If no context, return a default response
        guard !context.isEmpty else {
            return generateNoContextAnswer(for: queryType)
        }
        
        switch queryType {
        case .question:
            return generateQuestionAnswer(query: query, context: context)
        case .description:
            return generateDescriptionAnswer(context: context)
        case .navigation:
            return generateNavigationAnswer(query: query, context: context)
        case .memory:
            return generateMemoryAnswer(context: context)
        case .general:
            return generateGeneralAnswer(query: query, context: context)
        }
    }
    
    private func generateQuestionAnswer(query: String, context: [VectorEntry]) -> String {
        // Analyze query to understand what's being asked
        let queryLower = query.lowercased()
        
        // Extract key information from top context entries
        let topContext = context.prefix(5)
        
        var answerComponents: [String] = []
        
        // Object-related questions
        if queryLower.contains("was") || queryLower.contains("what") {
            let objects = topContext
                .flatMap { $0.metadata.tags }
                .uniqued()
                .prefix(5)
            
            if !objects.isEmpty {
                answerComponents.append("Ich sehe: \(objects.joined(separator: ", "))")
            }
        }
        
        // Location-related questions
        if queryLower.contains("wo") || queryLower.contains("where") {
            if let location = topContext.first?.metadata.location {
                answerComponents.append("Sie befinden sich in der Nähe einer bekannten Stelle")
            }
        }
        
        // Time-related questions
        if queryLower.contains("wann") || queryLower.contains("when") {
            if let timestamp = topContext.first?.metadata.timestamp {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                let relativeTime = formatter.localizedString(for: timestamp, relativeTo: Date())
                answerComponents.append("Das wurde \(relativeTime) erkannt")
            }
        }
        
        // Default: Describe what we know
        if answerComponents.isEmpty {
            let descriptions = topContext
                .map { $0.metadata.description }
                .filter { !$0.isEmpty }
                .prefix(3)
            
            if !descriptions.isEmpty {
                answerComponents.append(descriptions.joined(separator: ". "))
            }
        }
        
        return answerComponents.isEmpty
            ? "Ich habe keine relevanten Informationen zu dieser Frage gefunden."
            : answerComponents.joined(separator: ". ")
    }
    
    private func generateDescriptionAnswer(context: [VectorEntry]) -> String {
        let topContext = context.prefix(5)
        
        var description: [String] = []
        
        // Group by object types
        let objects = topContext
            .flatMap { $0.metadata.tags }
            .uniqued()
            .prefix(10)
        
        if !objects.isEmpty {
            description.append("Erkannte Objekte: \(objects.joined(separator: ", "))")
        }
        
        // Add location context
        let locations = topContext
            .compactMap { $0.metadata.location }
            .uniqued()
        
        if !locations.isEmpty {
            description.append("Sie befinden sich in einem bekannten Bereich")
        }
        
        // Add temporal context
        let recentEntries = topContext.filter { entry in
            Date().timeIntervalSince(entry.metadata.timestamp) < 300 // Last 5 minutes
        }
        
        if !recentEntries.isEmpty {
            description.append("Diese Szene wurde kürzlich erkannt")
        }
        
        return description.isEmpty
            ? "Keine detaillierte Beschreibung verfügbar"
            : description.joined(separator: ". ")
    }
    
    private func generateNavigationAnswer(query: String, context: [VectorEntry]) -> String {
        // Extract destination from query (simplified)
        let queryLower = query.lowercased()
        
        // Look for route information in episodic memory
        let routeEntries = context.filter { $0.memoryLayer == .episodic }
        
        if !routeEntries.isEmpty {
            let waypoints = routeEntries
                .map { $0.metadata.description }
                .filter { !$0.isEmpty }
                .prefix(5)
            
            return "Ich erkenne eine bekannte Route mit folgenden Wegpunkten: \(waypoints.joined(separator: ", "))"
        }
        
        return "Ich habe keine Route zu diesem Ziel gefunden. Bitte geben Sie weitere Details an."
    }
    
    private func generateMemoryAnswer(context: [VectorEntry]) -> String {
        // Group by memory layer
        let working = context.filter { $0.memoryLayer == .working }
        let episodic = context.filter { $0.memoryLayer == .episodic }
        let semantic = context.filter { $0.memoryLayer == .semantic }
        
        var answer: [String] = []
        
        if !working.isEmpty {
            answer.append("Aktuell im Arbeitsgedächtnis: \(working.count) Einträge")
        }
        
        if !episodic.isEmpty {
            let recentEpisodic = episodic.filter { entry in
                Date().timeIntervalSince(entry.metadata.timestamp) < 7 * 24 * 60 * 60 // Last week
            }
            answer.append("In den letzten Tagen: \(recentEpisodic.count) ähnliche Situationen")
        }
        
        if !semantic.isEmpty {
            answer.append("Langfristige Muster: \(semantic.count) gelernte Konzepte")
        }
        
        return answer.isEmpty
            ? "Keine relevanten Erinnerungen gefunden"
            : answer.joined(separator: ". ")
    }
    
    private func generateGeneralAnswer(query: String, context: [VectorEntry]) -> String {
        // Combine information from all context entries
        let topContext = context.prefix(5)
        
        let keyInfo = topContext
            .map { entry -> String in
                var info = entry.metadata.description
                if !entry.metadata.tags.isEmpty {
                    info += " (Tags: \(entry.metadata.tags.prefix(3).joined(separator: ", ")))"
                }
                return info
            }
            .filter { !$0.isEmpty }
        
        if !keyInfo.isEmpty {
            return "Basierend auf meinem Gedächtnis: \(keyInfo.joined(separator: ". "))"
        }
        
        return "Ich habe keine spezifischen Informationen zu Ihrer Anfrage gefunden."
    }
    
    private func generateNoContextAnswer(for queryType: RAGQueryType) -> String {
        switch queryType {
        case .question:
            return "Ich habe keine Informationen zu dieser Frage. Bitte versuchen Sie es später erneut."
        case .description:
            return "Keine Beschreibung verfügbar. Das System sammelt noch Informationen."
        case .navigation:
            return "Keine Navigationsinformationen verfügbar."
        case .memory:
            return "Keine Erinnerungen gefunden."
        case .general:
            return "Keine Informationen verfügbar."
        }
    }
    
    // MARK: - Confidence Calculation
    
    private func calculateConfidence(
        context: [VectorEntry],
        queryEmbedding: [Float]
    ) -> Float {
        guard !context.isEmpty else { return 0.0 }
        
        // Average similarity score
        let similarities = context.map { $0.similarity(to: queryEmbedding) }
        let avgSimilarity = similarities.reduce(0, +) / Float(similarities.count)
        
        // Boost confidence if we have multiple high-quality sources
        let highQualitySources = similarities.filter { $0 >= highRelevanceThreshold }.count
        let sourceBonus = min(Float(highQualitySources) / 5.0, 0.2)
        
        // Boost confidence if context is recent (for working/episodic memory)
        let recentEntries = context.filter { entry in
            Date().timeIntervalSince(entry.metadata.timestamp) < 300 // Last 5 minutes
        }
        let recencyBonus = min(Float(recentEntries.count) / 5.0, 0.1)
        
        return min(avgSimilarity + sourceBonus + recencyBonus, 1.0)
    }
    
    // MARK: - Source Identification
    
    private func identifySources(
        context: [VectorEntry],
        queryEmbedding: [Float],
        answer: String
    ) -> [RAGSource] {
        return context.prefix(10).map { entry in
            let relevanceScore = entry.similarity(to: queryEmbedding)
            
            // Determine what this source contributed
            let contribution = determineContribution(entry: entry, answer: answer)
            
            return RAGSource(
                entry: entry,
                relevanceScore: relevanceScore,
                contribution: contribution
            )
        }
    }
    
    private func determineContribution(entry: VectorEntry, answer: String) -> String {
        // Simple heuristic: check if entry's tags/description appear in answer
        let answerLower = answer.lowercased()
        
        for tag in entry.metadata.tags {
            if answerLower.contains(tag.lowercased()) {
                return "Information über \(tag)"
            }
        }
        
        if answerLower.contains(entry.metadata.description.lowercased()) {
            return "Beschreibung: \(entry.metadata.description)"
        }
        
        return "Kontextuelle Information"
    }
    
    override func reset() {
        // Clear any cached state
    }
}

// MARK: - Helper Extensions

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension CLLocationCoordinate2D: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
    
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
