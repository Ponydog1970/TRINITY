//
//  RAGDemo.swift
//  TRINITY Vision Aid
//
//  Live Demo und Testing für RAG System
//

import Foundation

/// Demo class für RAG System Testing
class RAGDemo {
    
    private let ragEngine: RAGQueryEngine
    private let vectorDB: VectorDatabase
    private let embeddings: EmbeddingGenerator
    
    init() throws {
        self.vectorDB = try VectorDatabase()
        self.embeddings = try EmbeddingGenerator()
        self.ragEngine = RAGQueryEngine(
            vectorDatabase: vectorDB,
            embeddingGenerator: embeddings
        )
    }
    
    // MARK: - Demo 1: Basic RAG
    
    func demoBasicRAG() async throws {
        print("=== Demo 1: Basic RAG Query ===\n")
        
        let query = "What objects did I see today?"
        print("Query: \(query)")
        
        let startTime = Date()
        let response = try await ragEngine.query(query)
        let elapsed = Date().timeIntervalSince(startTime)
        
        print("\nAnswer: \(response.answer)")
        print("Confidence: \(String(format: "%.2f", response.confidence))")
        print("Sources: \(response.sources.count)")
        print("Time: \(String(format: "%.0f", elapsed * 1000))ms")
        print("\n" + String(repeating: "-", count: 50) + "\n")
    }
    
    // MARK: - Demo 2: Vision-based RAG
    
    func demoVisionRAG() async throws {
        print("=== Demo 2: Vision-based RAG ===\n")
        
        // Create mock observation
        let observation = createMockObservation()
        
        let query = "What is this object?"
        print("Query: \(query)")
        print("Observation: \(observation.detectedObjects.count) objects detected")
        
        let response = try await ragEngine.query(
            observation: observation,
            question: query
        )
        
        print("\nAnswer: \(response.answer)")
        print("Confidence: \(String(format: "%.2f", response.confidence))")
        
        print("\nDetected Objects:")
        for obj in observation.detectedObjects {
            print("  • \(obj.label) (confidence: \(String(format: "%.2f", obj.confidence)))")
        }
        
        print("\n" + String(repeating: "-", count: 50) + "\n")
    }
    
    // MARK: - Demo 3: Conversational RAG
    
    func demoConversationalRAG() async throws {
        print("=== Demo 3: Conversational RAG ===\n")
        
        var history: [RAGResponse] = []
        
        // Turn 1
        print("User: What's in front of me?")
        let response1 = try await ragEngine.query("What's in front of me?")
        history.append(response1)
        print("Assistant: \(response1.answer)\n")
        
        // Turn 2
        print("User: How far away is it?")
        let response2 = try await ragEngine.conversationalQuery(
            question: "How far away is it?",
            history: history
        )
        history.append(response2)
        print("Assistant: \(response2.answer)\n")
        
        // Turn 3
        print("User: Is it safe to approach?")
        let response3 = try await ragEngine.conversationalQuery(
            question: "Is it safe to approach?",
            history: history
        )
        print("Assistant: \(response3.answer)\n")
        
        print("\n" + String(repeating: "-", count: 50) + "\n")
    }
    
    // MARK: - Demo 4: Hybrid Search
    
    func demoHybridSearch() async throws {
        print("=== Demo 4: Hybrid Search ===\n")
        
        let retriever = RAGRetriever(
            vectorDatabase: vectorDB,
            embeddingGenerator: embeddings
        )
        
        let query = "dangerous obstacles"
        let keywords = ["obstacle", "danger", "warning"]
        
        print("Query: \(query)")
        print("Keywords: \(keywords.joined(separator: ", "))")
        
        let documents = try await retriever.hybridSearch(
            query: query,
            keywords: keywords,
            config: .default
        )
        
        print("\nResults (\(documents.count)):")
        for (index, doc) in documents.enumerated() {
            print("\n\(index + 1). Similarity: \(String(format: "%.2f", doc.similarity))")
            print("   Content: \(doc.content)")
            print("   Layer: \(doc.memoryLayer.rawValue)")
        }
        
        print("\n" + String(repeating: "-", count: 50) + "\n")
    }
    
    // MARK: - Demo 5: Performance Benchmark
    
    func demoPerformance() async throws {
        print("=== Demo 5: Performance Benchmark ===\n")
        
        let queries = [
            "What's around me?",
            "Where am I?",
            "What obstacles?",
            "Have I been here?",
            "What's that sound?"
        ]
        
        var totalTime: TimeInterval = 0
        var results: [(String, TimeInterval, Float)] = []
        
        for query in queries {
            let start = Date()
            let response = try await ragEngine.query(query)
            let elapsed = Date().timeIntervalSince(start)
            
            totalTime += elapsed
            results.append((query, elapsed, response.confidence))
        }
        
        print("Queries: \(queries.count)")
        print("Total Time: \(String(format: "%.0f", totalTime * 1000))ms")
        print("Avg Time: \(String(format: "%.0f", (totalTime / Double(queries.count)) * 1000))ms\n")
        
        print("Individual Results:")
        for (query, time, confidence) in results {
            print("  • \(query)")
            print("    Time: \(String(format: "%.0f", time * 1000))ms | Confidence: \(String(format: "%.2f", confidence))")
        }
        
        print("\n" + String(repeating: "-", count: 50) + "\n")
    }
    
    // MARK: - Demo 6: Advanced Configuration
    
    func demoAdvancedConfig() async throws {
        print("=== Demo 6: Advanced Configuration ===\n")
        
        // Fast Config (Real-time)
        print("Config 1: FAST (Real-time)")
        let fastConfig = RetrievalConfig(
            topK: 3,
            similarityThreshold: 0.8,
            layers: [.working],
            reranking: false
        )
        
        let start1 = Date()
        let response1 = try await ragEngine.query("What's ahead?", config: fastConfig)
        let time1 = Date().timeIntervalSince(start1)
        
        print("  Time: \(String(format: "%.0f", time1 * 1000))ms")
        print("  Sources: \(response1.sources.count)")
        print("  Confidence: \(String(format: "%.2f", response1.confidence))\n")
        
        // Accurate Config (Complex queries)
        print("Config 2: ACCURATE (Complex)")
        let accurateConfig = RetrievalConfig(
            topK: 10,
            similarityThreshold: 0.5,
            layers: [.working, .episodic, .semantic],
            reranking: true
        )
        
        let start2 = Date()
        let response2 = try await ragEngine.query("What's ahead?", config: accurateConfig)
        let time2 = Date().timeIntervalSince(start2)
        
        print("  Time: \(String(format: "%.0f", time2 * 1000))ms")
        print("  Sources: \(response2.sources.count)")
        print("  Confidence: \(String(format: "%.2f", response2.confidence))\n")
        
        print("Speed Improvement: \(String(format: "%.1fx", time2 / time1))")
        print("\n" + String(repeating: "-", count: 50) + "\n")
    }
    
    // MARK: - Demo 7: Batch Processing
    
    func demoBatchProcessing() async throws {
        print("=== Demo 7: Batch Processing ===\n")
        
        let questions = [
            "What did I see today?",
            "Where did I go?",
            "What obstacles did I encounter?",
            "Have I been to this location?",
            "What's the weather like?"
        ]
        
        print("Processing \(questions.count) queries in parallel...\n")
        
        let start = Date()
        let responses = try await ragEngine.batchQuery(questions: questions)
        let elapsed = Date().timeIntervalSince(start)
        
        print("Total Time: \(String(format: "%.0f", elapsed * 1000))ms")
        print("Avg per Query: \(String(format: "%.0f", (elapsed / Double(questions.count)) * 1000))ms\n")
        
        print("Results:")
        for (question, response) in zip(questions, responses) {
            print("\nQ: \(question)")
            print("A: \(response.answer)")
            print("Confidence: \(String(format: "%.2f", response.confidence))")
        }
        
        print("\n" + String(repeating: "-", count: 50) + "\n")
    }
    
    // MARK: - Run All Demos
    
    func runAllDemos() async throws {
        print("\n")
        print(String(repeating: "=", count: 50))
        print("          RAG SYSTEM DEMO SUITE")
        print(String(repeating: "=", count: 50))
        print("\n")
        
        try await demoBasicRAG()
        try await demoVisionRAG()
        try await demoConversationalRAG()
        try await demoHybridSearch()
        try await demoPerformance()
        try await demoAdvancedConfig()
        try await demoBatchProcessing()
        
        print(String(repeating: "=", count: 50))
        print("          ALL DEMOS COMPLETED ✅")
        print(String(repeating: "=", count: 50))
        print("\n")
    }
    
    // MARK: - Helper Methods
    
    private func createMockObservation() -> Observation {
        let spatialData = SpatialData(
            depth: 2.5,
            boundingBox: BoundingBox(x: 0, y: 0, z: 0, width: 1, height: 1, depth: 0.5),
            orientation: Orientation(pitch: 0, yaw: 0, roll: 0),
            confidence: 0.85
        )
        
        let detectedObject = DetectedObject(
            id: UUID(),
            label: "chair",
            confidence: 0.85,
            boundingBox: BoundingBox(x: 0, y: 0, z: 0, width: 1, height: 1, depth: 0.5),
            spatialData: spatialData
        )
        
        return Observation(
            timestamp: Date(),
            cameraImage: Data(),
            depthMap: Data(),
            detectedObjects: [detectedObject],
            location: nil,
            deviceOrientation: Orientation(pitch: 0, yaw: 0, roll: 0)
        )
    }
}

// MARK: - Command Line Demo

extension RAGDemo {
    
    /// Interactive CLI demo
    static func runInteractiveDemo() async throws {
        print("\n🧠 RAG System Interactive Demo\n")
        print("Commands:")
        print("  1 - Basic RAG")
        print("  2 - Vision RAG")
        print("  3 - Conversational RAG")
        print("  4 - Hybrid Search")
        print("  5 - Performance Test")
        print("  6 - Advanced Config")
        print("  7 - Batch Processing")
        print("  all - Run all demos")
        print("  q - Quit\n")
        
        let demo = try RAGDemo()
        
        while true {
            print("> ", terminator: "")
            guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else {
                continue
            }
            
            if input == "q" {
                print("Goodbye! 👋\n")
                break
            }
            
            do {
                switch input {
                case "1":
                    try await demo.demoBasicRAG()
                case "2":
                    try await demo.demoVisionRAG()
                case "3":
                    try await demo.demoConversationalRAG()
                case "4":
                    try await demo.demoHybridSearch()
                case "5":
                    try await demo.demoPerformance()
                case "6":
                    try await demo.demoAdvancedConfig()
                case "7":
                    try await demo.demoBatchProcessing()
                case "all":
                    try await demo.runAllDemos()
                default:
                    print("Unknown command. Try 1-7, 'all', or 'q'\n")
                }
            } catch {
                print("Error: \(error.localizedDescription)\n")
            }
        }
    }
}
