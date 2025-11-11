//
//  RAGAgent.swift
//  TRINITY Vision Aid
//
//  Agent responsible for Retrieval-Augmented Generation (RAG)
//  Combines retrieval from memory with text generation
//

import Foundation
import NaturalLanguage
import CoreLocation

/// Input for RAG agent
struct RAGInput {
    let query: String
    let queryEmbedding: [Float]?
    let maxContextItems: Int
    let memoryLayers: [MemoryLayerType]?
    let includeCurrentObservation: Bool
}

/// Output from RAG agent
struct RAGOutput {
    let answer: String
    let retrievedContext: [VectorEntry]
    let confidence: Float
    let sources: [RAGSource]
    let reasoning: String?
}

/// Source of information used in RAG
struct RAGSource {
    let entryId: UUID
    let memoryLayer: MemoryLayerType
    let relevanceScore: Float
    let excerpt: String
}

/// Agent that performs Retrieval-Augmented Generation
class RAGAgent: BaseAgent<RAGInput, RAGOutput> {
    private let memoryManager: MemoryManager
    private let embeddingGenerator: EmbeddingGenerator
    private let vectorDatabase: VectorDatabase
    private let contextAgent: ContextAgent
    
    // Configuration
    private let defaultMaxContextItems = 10
    private let minRelevanceThreshold: Float = 0.5
    private let maxAnswerLength = 500
    
    init(
        memoryManager: MemoryManager,
        embeddingGenerator: EmbeddingGenerator,
        vectorDatabase: VectorDatabase,
        contextAgent: ContextAgent
    ) {
        self.memoryManager = memoryManager
        self.embeddingGenerator = embeddingGenerator
        self.vectorDatabase = vectorDatabase
        self.contextAgent = contextAgent
        super.init(name: "RAGAgent")
    }
    
    override func process(_ input: RAGInput) async throws -> RAGOutput {
        // Step 1: Generate query embedding if not provided
        let queryEmbedding = try await getQueryEmbedding(
            query: input.query,
            providedEmbedding: input.queryEmbedding
        )
        
        // Step 2: Retrieve relevant context from memory
        let retrievedContext = try await retrieveContext(
            queryEmbedding: queryEmbedding,
            maxItems: input.maxContextItems,
            layers: input.memoryLayers
        )
        
        // Step 3: Augment query with retrieved context
        let augmentedContext = augmentQuery(
            query: input.query,
            context: retrievedContext
        )
        
        // Step 4: Generate answer using augmented context
        let answer = try await generateAnswer(
            query: input.query,
            augmentedContext: augmentedContext
        )
        
        // Step 5: Calculate confidence and extract sources
        let sources = extractSources(from: retrievedContext, queryEmbedding: queryEmbedding)
        let confidence = calculateConfidence(
            sources: sources,
            answerLength: answer.count
        )
        
        // Step 6: Generate reasoning (optional)
        let reasoning = generateReasoning(
            query: input.query,
            sources: sources,
            answer: answer
        )
        
        return RAGOutput(
            answer: answer,
            retrievedContext: retrievedContext,
            confidence: confidence,
            sources: sources,
            reasoning: reasoning
        )
    }
    
    // MARK: - Retrieval Phase
    
    private func getQueryEmbedding(
        query: String,
        providedEmbedding: [Float]?
    ) async throws -> [Float] {
        if let embedding = providedEmbedding {
            return embedding
        }
        
        return try await embeddingGenerator.generateEmbedding(from: query)
    }
    
    private func retrieveContext(
        queryEmbedding: [Float],
        maxItems: Int,
        layers: [MemoryLayerType]?
    ) async throws -> [VectorEntry] {
        let maxContextItems = maxItems > 0 ? maxItems : defaultMaxContextItems
        
        // Search in specified layers or all layers
        if let layers = layers, !layers.isEmpty {
            var allResults: [VectorEntry] = []
            
            for layer in layers {
                let results = try await vectorDatabase.search(
                    query: queryEmbedding,
                    topK: maxContextItems,
                    layer: layer
                )
                allResults.append(contentsOf: results)
            }
            
            // Re-rank and deduplicate
            return reRankAndDeduplicate(
                results: allResults,
                queryEmbedding: queryEmbedding,
                topK: maxContextItems
            )
        } else {
            // Search all layers
            return try await vectorDatabase.search(
                query: queryEmbedding,
                topK: maxContextItems
            )
        }
    }
    
    private func reRankAndDeduplicate(
        results: [VectorEntry],
        queryEmbedding: [Float],
        topK: Int
    ) -> [VectorEntry] {
        // Calculate similarity scores
        let scoredResults = results.map { entry in
            (entry, entry.similarity(to: queryEmbedding))
        }
        .filter { $0.1 >= minRelevanceThreshold } // Filter by threshold
        .sorted { $0.1 > $1.1 } // Sort by relevance
        
        // Deduplicate by ID
        var seen = Set<UUID>()
        var uniqueResults: [VectorEntry] = []
        
        for (entry, _) in scoredResults {
            if !seen.contains(entry.id) {
                uniqueResults.append(entry)
                seen.insert(entry.id)
                
                if uniqueResults.count >= topK {
                    break
                }
            }
        }
        
        return uniqueResults
    }
    
    // MARK: - Augmentation Phase
    
    private func augmentQuery(
        query: String,
        context: [VectorEntry]
    ) -> AugmentedContext {
        // Build context summary from retrieved entries
        let contextSummaries = context.map { entry in
            buildContextSummary(from: entry)
        }
        
        // Extract key information
        let keyObjects = extractKeyObjects(from: context)
        let temporalInfo = extractTemporalInfo(from: context)
        let spatialInfo = extractSpatialInfo(from: context)
        
        return AugmentedContext(
            originalQuery: query,
            contextSummaries: contextSummaries,
            keyObjects: keyObjects,
            temporalInfo: temporalInfo,
            spatialInfo: spatialInfo,
            totalContextItems: context.count
        )
    }
    
    private func buildContextSummary(from entry: VectorEntry) -> String {
        var summary = entry.metadata.description
        
        // Add object type
        if !entry.metadata.objectType.isEmpty {
            summary += " (Type: \(entry.metadata.objectType))"
        }
        
        // Add tags if available
        if !entry.metadata.tags.isEmpty {
            let tags = entry.metadata.tags.prefix(3).joined(separator: ", ")
            summary += " [Tags: \(tags)]"
        }
        
        // Add spatial info if available
        if let spatial = entry.metadata.spatialData {
            summary += " [Distance: \(String(format: "%.1f", spatial.depth))m]"
        }
        
        // Add timestamp context
        let timeAgo = formatTimeAgo(since: entry.metadata.timestamp)
        summary += " [\(timeAgo)]"
        
        return summary
    }
    
    private func extractKeyObjects(from context: [VectorEntry]) -> [String] {
        let objectTypes = context.map { $0.metadata.objectType }
        let objectCounts = Dictionary(grouping: objectTypes, by: { $0 })
            .mapValues { $0.count }
        
        return objectCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }
    
    private func extractTemporalInfo(from context: [VectorEntry]) -> TemporalInfo {
        let timestamps = context.map { $0.metadata.timestamp }
        let mostRecent = timestamps.max()
        let oldest = timestamps.min()
        
        return TemporalInfo(
            mostRecent: mostRecent,
            oldest: oldest,
            totalItems: context.count
        )
    }
    
    private func extractSpatialInfo(from context: [VectorEntry]) -> SpatialInfo {
        let locations = context.compactMap { $0.metadata.location }
        
        guard !locations.isEmpty else {
            return SpatialInfo(hasLocation: false, locationCount: 0)
        }
        
        return SpatialInfo(
            hasLocation: true,
            locationCount: locations.count
        )
    }
    
    // MARK: - Generation Phase
    
    private func generateAnswer(
        query: String,
        augmentedContext: AugmentedContext
    ) async throws -> String {
        // Build prompt with context
        let prompt = buildPrompt(query: query, context: augmentedContext)
        
        // Generate answer using local generation
        // In production, this could use Apple Intelligence APIs
        let answer = try await localGeneration(prompt: prompt)
        
        // Post-process answer
        return postProcessAnswer(answer, maxLength: maxAnswerLength)
    }
    
    private func buildPrompt(
        query: String,
        context: AugmentedContext
    ) -> String {
        var prompt = """
        Based on the following context from memory, answer the user's question.
        
        User Question: \(query)
        
        Relevant Context:
        """
        
        // Add context summaries
        for (index, summary) in context.contextSummaries.enumerated() {
            prompt += "\n\(index + 1). \(summary)"
        }
        
        // Add key objects
        if !context.keyObjects.isEmpty {
            prompt += "\n\nKey Objects Mentioned: \(context.keyObjects.joined(separator: ", "))"
        }
        
        // Add temporal info
        if let mostRecent = context.temporalInfo.mostRecent {
            let timeAgo = formatTimeAgo(since: mostRecent)
            prompt += "\n\nMost Recent Context: \(timeAgo)"
        }
        
        prompt += "\n\nProvide a clear, concise answer based on the context above. If the context doesn't contain enough information, say so."
        
        return prompt
    }
    
    private func localGeneration(prompt: String) async throws -> String {
        // Template-based generation for local use
        // In production, integrate with Apple Intelligence or Core ML models
        
        // Simple rule-based generation as fallback
        return generateTemplateBasedAnswer(from: prompt)
    }
    
    private func generateTemplateBasedAnswer(from prompt: String) -> String {
        // Extract query from prompt
        guard let queryRange = prompt.range(of: "User Question: ") else {
            return "I couldn't process your question. Please try again."
        }
        
        let queryStart = prompt.index(queryRange.upperBound, offsetBy: 0)
        guard let queryEnd = prompt.range(of: "\n\nRelevant Context:", range: queryStart..<prompt.endIndex) else {
            return "I found some context, but couldn't formulate a complete answer."
        }
        
        let query = String(prompt[queryStart..<queryEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
        
        // Extract context summaries
        let contextStart = prompt.range(of: "Relevant Context:\n")?.upperBound ?? prompt.endIndex
        let contextEnd = prompt.range(of: "\n\nKey Objects", range: contextStart..<prompt.endIndex)?.lowerBound
            ?? prompt.range(of: "\n\nMost Recent Context", range: contextStart..<prompt.endIndex)?.lowerBound
            ?? prompt.endIndex
        
        let contextText = String(prompt[contextStart..<contextEnd])
        let contextLines = contextText.components(separatedBy: "\n")
            .filter { $0.hasPrefix(CharacterSet.decimalDigits) || $0.hasPrefix(" ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard !contextLines.isEmpty else {
            return "I don't have enough information in my memory to answer that question."
        }
        
        // Generate answer based on query type
        let lowerQuery = query.lowercased()
        
        if lowerQuery.contains("what") || lowerQuery.contains("was") || lowerQuery.contains("were") {
            return generateWhatAnswer(query: query, context: contextLines)
        } else if lowerQuery.contains("where") {
            return generateWhereAnswer(query: query, context: contextLines)
        } else if lowerQuery.contains("when") {
            return generateWhenAnswer(query: query, context: contextLines)
        } else if lowerQuery.contains("who") {
            return generateWhoAnswer(query: query, context: contextLines)
        } else if lowerQuery.contains("how") {
            return generateHowAnswer(query: query, context: contextLines)
        } else {
            return generateGeneralAnswer(query: query, context: contextLines)
        }
    }
    
    private func generateWhatAnswer(query: String, context: [String]) -> String {
        if context.count == 1 {
            return "Based on my memory: \(context[0])"
        } else {
            let summary = context.prefix(3).joined(separator: ". ")
            return "Based on my memory, I found: \(summary)."
        }
    }
    
    private func generateWhereAnswer(query: String, context: [String]) -> String {
        let locationContext = context.filter { $0.contains("Distance:") || $0.contains("location") }
        
        if !locationContext.isEmpty {
            return "Based on my memory: \(locationContext.first ?? context.first ?? "I don't have location information.")"
        }
        
        return "I don't have specific location information for that in my memory."
    }
    
    private func generateWhenAnswer(query: String, context: [String]) -> String {
        let timeContext = context.filter { $0.contains("ago") || $0.contains("minutes") || $0.contains("hours") }
        
        if !timeContext.isEmpty {
            return "Based on my memory: \(timeContext.first ?? context.first ?? "I don't have time information.")"
        }
        
        return "I don't have specific time information for that in my memory."
    }
    
    private func generateWhoAnswer(query: String, context: [String]) -> String {
        return generateGeneralAnswer(query: query, context: context)
    }
    
    private func generateHowAnswer(query: String, context: [String]) -> String {
        return generateGeneralAnswer(query: query, context: context)
    }
    
    private func generateGeneralAnswer(query: String, context: [String]) -> String {
        if context.isEmpty {
            return "I don't have enough information in my memory to answer that question."
        }
        
        let summary = context.prefix(2).joined(separator: " Also, ")
        return "Based on my memory: \(summary)."
    }
    
    private func postProcessAnswer(_ answer: String, maxLength: Int) -> String {
        var processed = answer.trimmingCharacters(in: .whitespaces)
        
        // Truncate if too long
        if processed.count > maxLength {
            let truncated = String(processed.prefix(maxLength))
            if let lastSentence = truncated.lastIndex(of: ".") {
                processed = String(truncated[...lastSentence])
            } else {
                processed = truncated + "..."
            }
        }
        
        // Ensure proper capitalization
        if !processed.isEmpty {
            processed = processed.prefix(1).uppercased() + processed.dropFirst()
        }
        
        return processed
    }
    
    // MARK: - Source Extraction
    
    private func extractSources(
        from context: [VectorEntry],
        queryEmbedding: [Float]
    ) -> [RAGSource] {
        return context.map { entry in
            let relevanceScore = entry.similarity(to: queryEmbedding)
            let excerpt = buildContextSummary(from: entry)
            
            return RAGSource(
                entryId: entry.id,
                memoryLayer: entry.memoryLayer,
                relevanceScore: relevanceScore,
                excerpt: excerpt
            )
        }
        .sorted { $0.relevanceScore > $1.relevanceScore }
    }
    
    private func calculateConfidence(
        sources: [RAGSource],
        answerLength: Int
    ) -> Float {
        guard !sources.isEmpty else { return 0.0 }
        
        // Base confidence on source relevance
        let avgRelevance = sources.map { $0.relevanceScore }.reduce(0, +) / Float(sources.count)
        
        // Adjust based on number of sources
        let sourceCountFactor = min(Float(sources.count) / 5.0, 1.0)
        
        // Adjust based on answer quality (length indicates completeness)
        let answerQualityFactor = min(Float(answerLength) / 100.0, 1.0)
        
        return (avgRelevance * 0.5) + (sourceCountFactor * 0.3) + (answerQualityFactor * 0.2)
    }
    
    private func generateReasoning(
        query: String,
        sources: [RAGSource],
        answer: String
    ) -> String? {
        guard !sources.isEmpty else { return nil }
        
        var reasoning = "I found \(sources.count) relevant memory entr\(sources.count == 1 ? "y" : "ies"). "
        
        let topSource = sources.first!
        reasoning += "The most relevant was from \(topSource.memoryLayer.rawValue) memory with \(Int(topSource.relevanceScore * 100))% relevance. "
        
        if sources.count > 1 {
            reasoning += "I also considered \(sources.count - 1) other related memories."
        }
        
        return reasoning
    }
    
    // MARK: - Utility Functions
    
    private func formatTimeAgo(since date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    
    override func reset() {
        // Clear any cached state
    }
}

// MARK: - Supporting Types

struct AugmentedContext {
    let originalQuery: String
    let contextSummaries: [String]
    let keyObjects: [String]
    let temporalInfo: TemporalInfo
    let spatialInfo: SpatialInfo
    let totalContextItems: Int
}

struct TemporalInfo {
    let mostRecent: Date?
    let oldest: Date?
    let totalItems: Int
}

struct SpatialInfo {
    let hasLocation: Bool
    let locationCount: Int
}
