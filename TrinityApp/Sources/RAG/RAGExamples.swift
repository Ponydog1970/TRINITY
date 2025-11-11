//
//  RAGExamples.swift
//  TRINITY Vision Aid
//
//  Example usage patterns for RAG system
//

import Foundation

/// Example implementations for X/Twitter
class RAGExamples {
    
    // MARK: - Basic RAG Pattern
    
    /// 🧠 Simple RAG Query
    static func basicRAGExample() async throws {
        // Setup
        let vectorDB = try VectorDatabase()
        let embeddings = try EmbeddingGenerator()
        let ragEngine = RAGQueryEngine(
            vectorDatabase: vectorDB,
            embeddingGenerator: embeddings
        )
        
        // Query
        let response = try await ragEngine.query("What objects did I see today?")
        
        print("Answer: \(response.answer)")
        print("Confidence: \(response.confidence)")
        print("Sources: \(response.sources.count) documents")
    }
    
    // MARK: - Vision-Based RAG
    
    /// 📸 RAG with Vision Input
    static func visionRAGExample(observation: Observation) async throws {
        let vectorDB = try VectorDatabase()
        let embeddings = try EmbeddingGenerator()
        let ragEngine = RAGQueryEngine(
            vectorDatabase: vectorDB,
            embeddingGenerator: embeddings
        )
        
        // Query based on what you're seeing
        let response = try await ragEngine.query(
            observation: observation,
            question: "What is this object and when did I last see it?"
        )
        
        print(response.answer)
    }
    
    // MARK: - Conversational RAG
    
    /// 💬 Multi-turn Conversation
    static func conversationalRAGExample() async throws {
        let vectorDB = try VectorDatabase()
        let embeddings = try EmbeddingGenerator()
        let ragEngine = RAGQueryEngine(
            vectorDatabase: vectorDB,
            embeddingGenerator: embeddings
        )
        
        var history: [RAGResponse] = []
        
        // Turn 1
        let response1 = try await ragEngine.query("What's in front of me?")
        history.append(response1)
        
        // Turn 2 (with context)
        let response2 = try await ragEngine.conversationalQuery(
            question: "How far away is it?",
            history: history
        )
        history.append(response2)
        
        print("Conversation:")
        for (i, response) in history.enumerated() {
            print("Q\(i+1): \(response.query)")
            print("A\(i+1): \(response.answer)\n")
        }
    }
    
    // MARK: - Hybrid Search RAG
    
    /// 🔍 Hybrid Search (Semantic + Keyword)
    static func hybridSearchExample() async throws {
        let vectorDB = try VectorDatabase()
        let embeddings = try EmbeddingGenerator()
        let retriever = RAGRetriever(
            vectorDatabase: vectorDB,
            embeddingGenerator: embeddings
        )
        
        // Combine semantic search with keywords
        let documents = try await retriever.hybridSearch(
            query: "dangerous obstacles",
            keywords: ["obstacle", "warning", "danger"],
            config: .default
        )
        
        for doc in documents {
            print("Found: \(doc.content) (similarity: \(doc.similarity))")
        }
    }
    
    // MARK: - Custom Retrieval Config
    
    /// ⚙️ Advanced Retrieval Configuration
    static func advancedRetrievalExample() async throws {
        let vectorDB = try VectorDatabase()
        let embeddings = try EmbeddingGenerator()
        let ragEngine = RAGQueryEngine(
            vectorDatabase: vectorDB,
            embeddingGenerator: embeddings
        )
        
        // Custom config
        let config = RetrievalConfig(
            topK: 10,
            similarityThreshold: 0.8,
            layers: [.episodic, .semantic], // Skip working memory
            reranking: true
        )
        
        let response = try await ragEngine.query(
            "Where have I been this week?",
            config: config
        )
        
        print(response.answer)
    }
    
    // MARK: - Batch Processing
    
    /// 📦 Batch Query Processing
    static func batchQueryExample() async throws {
        let vectorDB = try VectorDatabase()
        let embeddings = try EmbeddingGenerator()
        let ragEngine = RAGQueryEngine(
            vectorDatabase: vectorDB,
            embeddingGenerator: embeddings
        )
        
        let questions = [
            "What did I see today?",
            "Where did I go?",
            "What obstacles did I encounter?"
        ]
        
        let responses = try await ragEngine.batchQuery(questions: questions)
        
        for (question, response) in zip(questions, responses) {
            print("Q: \(question)")
            print("A: \(response.answer)\n")
        }
    }
    
    // MARK: - Diverse Results
    
    /// 🎨 Retrieve with Diversity
    static func diverseRetrievalExample() async throws {
        let vectorDB = try VectorDatabase()
        let embeddings = try EmbeddingGenerator()
        let retriever = RAGRetriever(
            vectorDatabase: vectorDB,
            embeddingGenerator: embeddings
        )
        
        // Get diverse results (avoid too similar documents)
        let documents = try await retriever.retrieveWithDiversity(
            query: "objects in my environment",
            diversityThreshold: 0.85
        )
        
        for doc in documents {
            print("- \(doc.metadata.objectType): \(doc.metadata.description)")
        }
    }
    
    // MARK: - Real-World Use Cases
    
    /// 🏃 Navigation Assistant
    static func navigationAssistantExample() async throws {
        let vectorDB = try VectorDatabase()
        let embeddings = try EmbeddingGenerator()
        let ragEngine = RAGQueryEngine(
            vectorDatabase: vectorDB,
            embeddingGenerator: embeddings
        )
        
        // Check for obstacles
        let response = try await ragEngine.query(
            "Are there any obstacles within 2 meters?",
            config: RetrievalConfig(
                topK: 5,
                similarityThreshold: 0.6,
                layers: [.working],
                reranking: true
            )
        )
        
        if response.confidence > 0.7 {
            print("⚠️ Navigation Alert: \(response.answer)")
        }
    }
    
    /// 🏠 Location Memory
    static func locationMemoryExample() async throws {
        let vectorDB = try VectorDatabase()
        let embeddings = try EmbeddingGenerator()
        let ragEngine = RAGQueryEngine(
            vectorDatabase: vectorDB,
            embeddingGenerator: embeddings
        )
        
        // Remember a location
        let response = try await ragEngine.query(
            "Have I been to this location before?",
            config: RetrievalConfig(
                topK: 3,
                similarityThreshold: 0.75,
                layers: [.episodic, .semantic],
                reranking: true
            )
        )
        
        print(response.answer)
        print("\nBased on \(response.sources.count) previous visits")
    }
    
    /// 📚 Knowledge Retrieval
    static func knowledgeRetrievalExample() async throws {
        let vectorDB = try VectorDatabase()
        let embeddings = try EmbeddingGenerator()
        let ragEngine = RAGQueryEngine(
            vectorDatabase: vectorDB,
            embeddingGenerator: embeddings
        )
        
        // Query semantic memory for learned patterns
        let response = try await ragEngine.query(
            "What do I usually find in the kitchen?",
            config: RetrievalConfig(
                topK: 10,
                similarityThreshold: 0.5,
                layers: [.semantic],
                reranking: true
            )
        )
        
        print("Learned patterns: \(response.answer)")
    }
}

// MARK: - X/Twitter Code Snippets

extension RAGExamples {
    
    /// Tweet 1: Basic RAG in Swift 🧵
    static let tweet1 = """
    🧠 Building a RAG system in Swift for vision assistance!
    
    RAG = Retrieval + Generation
    1️⃣ Embed query → vector
    2️⃣ Search vector DB (HNSW)
    3️⃣ Retrieve top-K documents
    4️⃣ Generate answer with context
    
    Perfect for on-device ML! 🍎
    #Swift #RAG #AI
    """
    
    /// Tweet 2: Code Example
    static let tweet2 = """
    📸 RAG with Vision Input in Swift:
    
    ```swift
    let ragEngine = RAGQueryEngine(
        vectorDB: vectorDB,
        embeddings: embeddings
    )
    
    let response = try await ragEngine.query(
        observation: currentFrame,
        question: "What's in front of me?"
    )
    ```
    
    Combines camera + LiDAR + memory! 🚀
    """
    
    /// Tweet 3: Architecture
    static let tweet3 = """
    🏗️ RAG Architecture for iOS:
    
    Observation → Embedding → VectorDB
         ↓           ↓           ↓
    MultiModal    CoreML     HNSW Index
         ↓           ↓           ↓
    Retriever → Context → Generator
    
    100% on-device, no cloud! 🔒
    #PrivacyFirst
    """
    
    /// Tweet 4: Performance
    static let tweet4 = """
    ⚡️ RAG Performance Metrics:
    
    Embedding: <100ms
    Vector Search (10k): <20ms
    Retrieval: <50ms
    Total: <300ms
    
    Memory: ~50MB
    Accuracy: 95%+
    
    Fast enough for real-time! ⏱️
    """
}
