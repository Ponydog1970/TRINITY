//
//  RAGQueryEngine.swift
//  TRINITY Vision Aid
//
//  Query engine that orchestrates the RAG pipeline
//

import Foundation

/// Context for RAG generation
struct RAGContext {
    let query: String
    let retrievedDocuments: [RetrievedDocument]
    let timestamp: Date
    let totalDocuments: Int
    let averageSimilarity: Float
    
    var formattedContext: String {
        var context = "# Relevant Context\n\n"
        
        for (index, doc) in retrievedDocuments.enumerated() {
            context += "## Document \(index + 1) (Similarity: \(String(format: "%.2f", doc.similarity)))\n"
            context += "Layer: \(doc.memoryLayer.rawValue)\n"
            context += doc.content + "\n\n"
        }
        
        return context
    }
}

/// Response from RAG query
struct RAGResponse {
    let query: String
    let answer: String
    let context: RAGContext
    let sources: [RetrievedDocument]
    let processingTime: TimeInterval
    let confidence: Float
}

/// Main RAG Query Engine
class RAGQueryEngine {
    private let retriever: RAGRetriever
    private let vectorDatabase: VectorDatabase
    private let embeddingGenerator: EmbeddingGenerator
    
    init(
        vectorDatabase: VectorDatabase,
        embeddingGenerator: EmbeddingGenerator
    ) {
        self.vectorDatabase = vectorDatabase
        self.embeddingGenerator = embeddingGenerator
        self.retriever = RAGRetriever(
            vectorDatabase: vectorDatabase,
            embeddingGenerator: embeddingGenerator
        )
    }
    
    // MARK: - Query Methods
    
    /// Execute RAG query with text input
    func query(
        _ question: String,
        config: RetrievalConfig = .default
    ) async throws -> RAGResponse {
        let startTime = Date()
        
        // 1. Retrieve relevant documents
        let documents = try await retriever.retrieve(query: question, config: config)
        
        // 2. Build context
        let context = buildContext(query: question, documents: documents)
        
        // 3. Generate answer (simplified - in production use LLM)
        let answer = generateAnswer(question: question, context: context)
        
        // 4. Calculate confidence
        let confidence = calculateConfidence(documents: documents)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return RAGResponse(
            query: question,
            answer: answer,
            context: context,
            sources: documents,
            processingTime: processingTime,
            confidence: confidence
        )
    }
    
    /// Execute RAG query with observation input
    func query(
        observation: Observation,
        question: String,
        config: RetrievalConfig = .default
    ) async throws -> RAGResponse {
        let startTime = Date()
        
        // 1. Retrieve documents based on observation
        let documents = try await retriever.retrieve(observation: observation, config: config)
        
        // 2. Build context with observation data
        let context = buildContext(
            query: question,
            documents: documents,
            observation: observation
        )
        
        // 3. Generate answer
        let answer = generateAnswer(question: question, context: context)
        
        // 4. Calculate confidence
        let confidence = calculateConfidence(documents: documents)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return RAGResponse(
            query: question,
            answer: answer,
            context: context,
            sources: documents,
            processingTime: processingTime,
            confidence: confidence
        )
    }
    
    /// Multi-turn conversation with context
    func conversationalQuery(
        question: String,
        history: [RAGResponse],
        config: RetrievalConfig = .default
    ) async throws -> RAGResponse {
        // Combine current question with conversation history
        let contextualQuery = buildContextualQuery(question: question, history: history)
        
        // Execute query with enhanced context
        return try await query(contextualQuery, config: config)
    }
    
    // MARK: - Context Building
    
    private func buildContext(
        query: String,
        documents: [RetrievedDocument],
        observation: Observation? = nil
    ) -> RAGContext {
        let avgSimilarity = documents.isEmpty
            ? 0.0
            : documents.map { $0.similarity }.reduce(0, +) / Float(documents.count)
        
        return RAGContext(
            query: query,
            retrievedDocuments: documents,
            timestamp: Date(),
            totalDocuments: documents.count,
            averageSimilarity: avgSimilarity
        )
    }
    
    private func buildContextualQuery(
        question: String,
        history: [RAGResponse]
    ) -> String {
        var contextualQuery = question
        
        // Add relevant information from recent history
        if let lastResponse = history.last {
            contextualQuery += "\n\nPrevious context: \(lastResponse.answer.prefix(100))"
        }
        
        return contextualQuery
    }
    
    // MARK: - Answer Generation
    
    private func generateAnswer(
        question: String,
        context: RAGContext
    ) -> String {
        // Simple rule-based answer generation
        // In production, this would call a LLM like GPT or Claude
        
        if context.retrievedDocuments.isEmpty {
            return "I don't have enough information to answer that question."
        }
        
        // Extract key information from documents
        var answer = "Based on the available information:\n\n"
        
        // Analyze question type
        if question.lowercased().contains("what") {
            answer += generateWhatAnswer(context: context)
        } else if question.lowercased().contains("where") {
            answer += generateWhereAnswer(context: context)
        } else if question.lowercased().contains("when") {
            answer += generateWhenAnswer(context: context)
        } else if question.lowercased().contains("how many") {
            answer += generateHowManyAnswer(context: context)
        } else {
            answer += generateGeneralAnswer(context: context)
        }
        
        // Add confidence indicator
        if context.averageSimilarity < 0.5 {
            answer += "\n\n⚠️ Note: Low confidence answer. Information may not be directly relevant."
        }
        
        return answer
    }
    
    private func generateWhatAnswer(context: RAGContext) -> String {
        let topDoc = context.retrievedDocuments.first!
        return "I found \(topDoc.metadata.objectType): \(topDoc.metadata.description)"
    }
    
    private func generateWhereAnswer(context: RAGContext) -> String {
        let docsWithLocation = context.retrievedDocuments.filter { $0.metadata.location != nil }
        
        if let doc = docsWithLocation.first,
           let location = doc.metadata.location {
            return "Located at coordinates: \(location.latitude), \(location.longitude)"
        }
        
        if let doc = context.retrievedDocuments.first,
           let spatial = doc.metadata.spatialData {
            return "Distance: \(String(format: "%.1f", spatial.depth)) meters away"
        }
        
        return "Location information not available."
    }
    
    private func generateWhenAnswer(context: RAGContext) -> String {
        let topDoc = context.retrievedDocuments.first!
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        return "Last seen: \(formatter.string(from: topDoc.metadata.timestamp))"
    }
    
    private func generateHowManyAnswer(context: RAGContext) -> String {
        // Group by object type
        let grouped = Dictionary(grouping: context.retrievedDocuments) { $0.metadata.objectType }
        
        var answer = ""
        for (type, docs) in grouped.sorted(by: { $0.value.count > $1.value.count }) {
            answer += "\(docs.count) \(type)\n"
        }
        
        return answer.isEmpty ? "No objects found." : answer
    }
    
    private func generateGeneralAnswer(context: RAGContext) -> String {
        let topDocs = context.retrievedDocuments.prefix(3)
        var answer = ""
        
        for (index, doc) in topDocs.enumerated() {
            answer += "\(index + 1). \(doc.content)\n"
        }
        
        return answer
    }
    
    // MARK: - Confidence Calculation
    
    private func calculateConfidence(documents: [RetrievedDocument]) -> Float {
        guard !documents.isEmpty else { return 0.0 }
        
        // Factors that affect confidence:
        // 1. Average similarity score
        let avgSimilarity = documents.map { $0.similarity }.reduce(0, +) / Float(documents.count)
        
        // 2. Number of documents
        let docCountFactor = min(Float(documents.count) / 5.0, 1.0)
        
        // 3. Consistency (how similar are top documents to each other)
        let consistency = calculateConsistency(documents: documents)
        
        // Weighted combination
        return avgSimilarity * 0.5 + docCountFactor * 0.2 + consistency * 0.3
    }
    
    private func calculateConsistency(documents: [RetrievedDocument]) -> Float {
        guard documents.count > 1 else { return 1.0 }
        
        let topDocs = Array(documents.prefix(3))
        var similarities: [Float] = []
        
        for i in 0..<topDocs.count {
            for j in (i+1)..<topDocs.count {
                let sim = cosineSimilarity(topDocs[i].embedding, topDocs[j].embedding)
                similarities.append(sim)
            }
        }
        
        return similarities.isEmpty ? 0.0 : similarities.reduce(0, +) / Float(similarities.count)
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        guard magnitudeA > 0, magnitudeB > 0 else { return 0.0 }
        return dotProduct / (magnitudeA * magnitudeB)
    }
    
    // MARK: - Advanced Features
    
    /// Query with custom prompt template
    func queryWithTemplate(
        question: String,
        template: String,
        config: RetrievalConfig = .default
    ) async throws -> RAGResponse {
        let documents = try await retriever.retrieve(query: question, config: config)
        let context = buildContext(query: question, documents: documents)
        
        // Replace placeholders in template
        var prompt = template
        prompt = prompt.replacingOccurrences(of: "{query}", with: question)
        prompt = prompt.replacingOccurrences(of: "{context}", with: context.formattedContext)
        
        let answer = generateAnswer(question: prompt, context: context)
        let confidence = calculateConfidence(documents: documents)
        
        return RAGResponse(
            query: question,
            answer: answer,
            context: context,
            sources: documents,
            processingTime: 0,
            confidence: confidence
        )
    }
    
    /// Batch query multiple questions
    func batchQuery(
        questions: [String],
        config: RetrievalConfig = .default
    ) async throws -> [RAGResponse] {
        return try await withThrowingTaskGroup(of: (Int, RAGResponse).self) { group in
            for (index, question) in questions.enumerated() {
                group.addTask {
                    let response = try await self.query(question, config: config)
                    return (index, response)
                }
            }
            
            var results: [(Int, RAGResponse)] = []
            for try await result in group {
                results.append(result)
            }
            
            return results
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
        }
    }
}
