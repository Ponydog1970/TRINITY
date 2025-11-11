//
//  RAGRetriever.swift
//  TRINITY Vision Aid
//
//  Retrieves relevant documents from VectorDB for RAG
//

import Foundation

/// Configuration for retrieval
struct RetrievalConfig {
    let topK: Int
    let similarityThreshold: Float
    let layers: [MemoryLayerType]
    let reranking: Bool
    
    static let `default` = RetrievalConfig(
        topK: 5,
        similarityThreshold: 0.7,
        layers: [.working, .episodic, .semantic],
        reranking: true
    )
}

/// Retrieved document with metadata
struct RetrievedDocument: Identifiable {
    let id: UUID
    let content: String
    let similarity: Float
    let metadata: MemoryMetadata
    let memoryLayer: MemoryLayerType
    let embedding: [Float]
}

/// Retrieves relevant documents from vector database
class RAGRetriever {
    private let vectorDatabase: VectorDatabase
    private let embeddingGenerator: EmbeddingGenerator
    
    init(
        vectorDatabase: VectorDatabase,
        embeddingGenerator: EmbeddingGenerator
    ) {
        self.vectorDatabase = vectorDatabase
        self.embeddingGenerator = embeddingGenerator
    }
    
    // MARK: - Retrieval Methods
    
    /// Retrieve documents based on text query
    func retrieve(
        query: String,
        config: RetrievalConfig = .default
    ) async throws -> [RetrievedDocument] {
        // 1. Generate query embedding
        let queryEmbedding = try await embeddingGenerator.generateEmbedding(from: query)
        
        // 2. Search vector database
        var allResults: [(VectorEntry, Float)] = []
        
        for layer in config.layers {
            let entries = try await vectorDatabase.search(
                query: queryEmbedding,
                topK: config.topK * 2, // Get more for reranking
                layer: layer
            )
            
            let resultsWithScore = entries.map { entry in
                (entry, entry.similarity(to: queryEmbedding))
            }
            
            allResults.append(contentsOf: resultsWithScore)
        }
        
        // 3. Filter by threshold
        let filtered = allResults.filter { $0.1 >= config.similarityThreshold }
        
        // 4. Rerank if enabled
        let ranked = config.reranking
            ? try await rerank(results: filtered, query: query)
            : filtered
        
        // 5. Take top K
        let topResults = ranked
            .sorted { $0.1 > $1.1 }
            .prefix(config.topK)
        
        // 6. Convert to RetrievedDocuments
        return topResults.map { entry, similarity in
            RetrievedDocument(
                id: entry.id,
                content: formatContent(from: entry),
                similarity: similarity,
                metadata: entry.metadata,
                memoryLayer: entry.memoryLayer,
                embedding: entry.embedding
            )
        }
    }
    
    /// Retrieve documents based on observation
    func retrieve(
        observation: Observation,
        config: RetrievalConfig = .default
    ) async throws -> [RetrievedDocument] {
        // Generate multimodal embedding
        let queryEmbedding = try await embeddingGenerator.generateEmbedding(from: observation)
        
        // Search across layers
        var allResults: [(VectorEntry, Float)] = []
        
        for layer in config.layers {
            let entries = try await vectorDatabase.search(
                query: queryEmbedding,
                topK: config.topK * 2,
                layer: layer
            )
            
            let resultsWithScore = entries.map { entry in
                (entry, entry.similarity(to: queryEmbedding))
            }
            
            allResults.append(contentsOf: resultsWithScore)
        }
        
        // Filter and sort
        let topResults = allResults
            .filter { $0.1 >= config.similarityThreshold }
            .sorted { $0.1 > $1.1 }
            .prefix(config.topK)
        
        return topResults.map { entry, similarity in
            RetrievedDocument(
                id: entry.id,
                content: formatContent(from: entry),
                similarity: similarity,
                metadata: entry.metadata,
                memoryLayer: entry.memoryLayer,
                embedding: entry.embedding
            )
        }
    }
    
    /// Hybrid search: combines semantic and keyword search
    func hybridSearch(
        query: String,
        keywords: [String],
        config: RetrievalConfig = .default
    ) async throws -> [RetrievedDocument] {
        // 1. Semantic search
        let semanticResults = try await retrieve(query: query, config: config)
        
        // 2. Keyword search (simple implementation)
        let keywordResults = try await keywordSearch(keywords: keywords, config: config)
        
        // 3. Combine and deduplicate
        return combineResults(semantic: semanticResults, keyword: keywordResults)
    }
    
    // MARK: - Private Methods
    
    private func rerank(
        results: [(VectorEntry, Float)],
        query: String
    ) async throws -> [(VectorEntry, Float)] {
        // Simple reranking based on:
        // 1. Recency (temporal relevance)
        // 2. Access count (popularity)
        // 3. Similarity score
        
        let now = Date()
        
        return results.map { entry, similarity in
            // Time decay: newer is better
            let timeDiff = now.timeIntervalSince(entry.lastAccessed)
            let timeFactor = exp(-timeDiff / (24 * 60 * 60)) // 1 day decay
            
            // Access count factor: more accessed is better
            let accessFactor = Float(entry.accessCount) / 100.0
            
            // Combine scores
            let finalScore = similarity * 0.7 + Float(timeFactor) * 0.2 + accessFactor * 0.1
            
            return (entry, finalScore)
        }
    }
    
    private func keywordSearch(
        keywords: [String],
        config: RetrievalConfig
    ) async throws -> [RetrievedDocument] {
        var matchingDocuments: [RetrievedDocument] = []
        
        for layer in config.layers {
            let entries = try await vectorDatabase.load(layer: layer)
            
            for entry in entries {
                let content = formatContent(from: entry)
                let matchCount = keywords.filter { keyword in
                    content.lowercased().contains(keyword.lowercased())
                }.count
                
                if matchCount > 0 {
                    let similarity = Float(matchCount) / Float(keywords.count)
                    
                    if similarity >= config.similarityThreshold {
                        matchingDocuments.append(
                            RetrievedDocument(
                                id: entry.id,
                                content: content,
                                similarity: similarity,
                                metadata: entry.metadata,
                                memoryLayer: entry.memoryLayer,
                                embedding: entry.embedding
                            )
                        )
                    }
                }
            }
        }
        
        return matchingDocuments
    }
    
    private func combineResults(
        semantic: [RetrievedDocument],
        keyword: [RetrievedDocument]
    ) -> [RetrievedDocument] {
        var combined = [UUID: RetrievedDocument]()
        
        // Add semantic results
        for doc in semantic {
            combined[doc.id] = doc
        }
        
        // Merge keyword results (boost score if already present)
        for doc in keyword {
            if let existing = combined[doc.id] {
                // Boost similarity score
                let boostedSimilarity = (existing.similarity + doc.similarity) / 2
                combined[doc.id] = RetrievedDocument(
                    id: doc.id,
                    content: doc.content,
                    similarity: boostedSimilarity,
                    metadata: doc.metadata,
                    memoryLayer: doc.memoryLayer,
                    embedding: doc.embedding
                )
            } else {
                combined[doc.id] = doc
            }
        }
        
        return combined.values.sorted { $0.similarity > $1.similarity }
    }
    
    private func formatContent(from entry: VectorEntry) -> String {
        var parts: [String] = []
        
        // Add description
        parts.append(entry.metadata.description)
        
        // Add object type
        if !entry.metadata.objectType.isEmpty {
            parts.append("Type: \(entry.metadata.objectType)")
        }
        
        // Add tags
        if !entry.metadata.tags.isEmpty {
            parts.append("Tags: \(entry.metadata.tags.joined(separator: ", "))")
        }
        
        // Add spatial info if available
        if let spatial = entry.metadata.spatialData {
            parts.append("Distance: \(String(format: "%.1f", spatial.depth))m")
        }
        
        // Add temporal info
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        parts.append("Seen: \(formatter.string(from: entry.metadata.timestamp))")
        
        return parts.joined(separator: " | ")
    }
    
    // MARK: - Advanced Retrieval
    
    /// Retrieve with diversity (avoid too similar results)
    func retrieveWithDiversity(
        query: String,
        config: RetrievalConfig = .default,
        diversityThreshold: Float = 0.85
    ) async throws -> [RetrievedDocument] {
        // Get more results initially
        var extendedConfig = config
        extendedConfig = RetrievalConfig(
            topK: config.topK * 3,
            similarityThreshold: config.similarityThreshold,
            layers: config.layers,
            reranking: config.reranking
        )
        
        let allResults = try await retrieve(query: query, config: extendedConfig)
        
        // Diversify results
        var diverseResults: [RetrievedDocument] = []
        
        for result in allResults {
            var isDiverse = true
            
            // Check if too similar to already selected results
            for selected in diverseResults {
                let similarity = cosineSimilarity(result.embedding, selected.embedding)
                if similarity > diversityThreshold {
                    isDiverse = false
                    break
                }
            }
            
            if isDiverse {
                diverseResults.append(result)
            }
            
            if diverseResults.count >= config.topK {
                break
            }
        }
        
        return diverseResults
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        guard magnitudeA > 0, magnitudeB > 0 else { return 0.0 }
        return dotProduct / (magnitudeA * magnitudeB)
    }
}
