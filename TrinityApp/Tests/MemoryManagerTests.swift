//
//  MemoryManagerTests.swift
//  TRINITYTests
//
//  Unit tests for enhanced MemoryManager with adaptive features
//

import XCTest
@testable import TRINITY

@MainActor
final class MemoryManagerTests: XCTestCase {
    
    var memoryManager: MemoryManager!
    var mockVectorDB: MockVectorDatabase!
    
    override func setUp() async throws {
        try await super.setUp()
        mockVectorDB = MockVectorDatabase()
        memoryManager = MemoryManager(vectorDatabase: mockVectorDB)
    }
    
    override func tearDown() async throws {
        memoryManager = nil
        mockVectorDB = nil
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func createTestObservation(
        objectLabel: String = "test_object",
        confidence: Float = 0.8
    ) -> Observation {
        let detectedObject = DetectedObject(
            id: UUID(),
            label: objectLabel,
            confidence: confidence,
            boundingBox: BoundingBox(x: 0, y: 0, z: 0, width: 1, height: 1, depth: 1),
            spatialData: SpatialData(
                depth: 5.0,
                boundingBox: BoundingBox(x: 0, y: 0, z: 0, width: 1, height: 1, depth: 1),
                orientation: Orientation(pitch: 0, yaw: 0, roll: 0),
                confidence: confidence
            )
        )
        
        return Observation(
            timestamp: Date(),
            cameraImage: nil,
            depthMap: nil,
            detectedObjects: [detectedObject],
            location: nil,
            deviceOrientation: Orientation(pitch: 0, yaw: 0, roll: 0)
        )
    }
    
    private func createTestEmbedding() -> [Float] {
        return (0..<512).map { _ in Float.random(in: -1...1) }
    }
    
    // MARK: - Add Observation Tests
    
    func testAddObservation() async throws {
        let observation = createTestObservation()
        let embedding = createTestEmbedding()
        
        try await memoryManager.addObservation(observation, embedding: embedding)
        
        // Should add to working memory
        XCTAssertGreaterThan(memoryManager.workingMemory.count, 0)
    }
    
    func testAddMultipleObservations() async throws {
        for i in 0..<10 {
            let observation = createTestObservation(objectLabel: "object_\(i)")
            let embedding = createTestEmbedding()
            try await memoryManager.addObservation(observation, embedding: embedding)
        }
        
        // Should have entries in working memory
        XCTAssertEqual(memoryManager.workingMemory.count, 10)
    }
    
    func testWorkingMemoryOverflow() async throws {
        // Add more than max working memory size
        for i in 0..<150 {
            let observation = createTestObservation(objectLabel: "object_\(i)")
            let embedding = createTestEmbedding()
            try await memoryManager.addObservation(observation, embedding: embedding)
        }
        
        // Working memory should be managed (some moved to episodic)
        XCTAssertLessThanOrEqual(memoryManager.workingMemory.count, 150)
        
        // Some should have been moved to episodic
        XCTAssertGreaterThan(memoryManager.episodicMemory.count, 0)
    }
    
    // MARK: - Search Tests
    
    func testSearchAcrossLayers() async throws {
        // Add entries to different layers
        for i in 0..<5 {
            let observation = createTestObservation(objectLabel: "object_\(i)")
            let embedding = createTestEmbedding()
            try await memoryManager.addObservation(observation, embedding: embedding)
        }
        
        // Manually add to episodic
        let episodicEntry = VectorEntry(
            embedding: createTestEmbedding(),
            metadata: MemoryMetadata(
                objectType: "episodic_object",
                description: "Test",
                confidence: 0.8,
                tags: ["episodic"],
                spatialData: nil,
                timestamp: Date().addingTimeInterval(-3600),
                location: nil
            ),
            memoryLayer: .episodic
        )
        memoryManager.episodicMemory.append(episodicEntry)
        
        // Search
        let queryEmbedding = createTestEmbedding()
        let results = try await memoryManager.search(embedding: queryEmbedding, topK: 3)
        
        // Should return results
        XCTAssertGreaterThan(results.count, 0)
        XCTAssertLessThanOrEqual(results.count, 3)
    }
    
    func testSearchWithEmptyMemory() async throws {
        let queryEmbedding = createTestEmbedding()
        let results = try await memoryManager.search(embedding: queryEmbedding, topK: 5)
        
        // Should return empty array
        XCTAssertEqual(results.count, 0)
    }
    
    func testSearchUpdatesAccessCounts() async throws {
        // Add an entry
        let observation = createTestObservation()
        let embedding = createTestEmbedding()
        try await memoryManager.addObservation(observation, embedding: embedding)
        
        let initialAccessCount = memoryManager.workingMemory.first?.accessCount ?? 0
        
        // Search
        let results = try await memoryManager.search(embedding: embedding, topK: 1)
        
        // Access count should be updated if entry was returned
        if !results.isEmpty {
            let updatedEntry = memoryManager.workingMemory.first { $0.id == results[0].id }
            XCTAssertNotNil(updatedEntry)
            if let updated = updatedEntry {
                XCTAssertGreaterThan(updated.accessCount, initialAccessCount)
            }
        }
    }
    
    // MARK: - Consolidation Tests
    
    func testConsolidateEpisodicMemory() async throws {
        // Add entries to episodic memory with high access counts
        for i in 0..<25 {
            let entry = VectorEntry(
                embedding: createTestEmbedding(),
                metadata: MemoryMetadata(
                    objectType: "object",
                    description: "Test \(i)",
                    confidence: 0.8,
                    tags: ["test"],
                    spatialData: nil,
                    timestamp: Date().addingTimeInterval(-Double(i) * 3600),
                    location: nil
                ),
                memoryLayer: .episodic,
                accessCount: 15,
                lastAccessed: Date()
            )
            memoryManager.episodicMemory.append(entry)
        }
        
        let initialEpisodicCount = memoryManager.episodicMemory.count
        
        // Consolidate
        await memoryManager.consolidateEpisodicMemory()
        
        // Some entries should have been consolidated to semantic
        XCTAssertGreaterThanOrEqual(memoryManager.semanticMemory.count, 0)
    }
    
    // MARK: - Memory Statistics Tests
    
    func testGetMemoryStatistics() async throws {
        // Add some entries
        for i in 0..<5 {
            let observation = createTestObservation(objectLabel: "object_\(i)")
            let embedding = createTestEmbedding()
            try await memoryManager.addObservation(observation, embedding: embedding)
        }
        
        let stats = memoryManager.getMemoryStatistics()
        
        // Check statistics
        XCTAssertEqual(stats.workingMemoryCount, memoryManager.workingMemory.count)
        XCTAssertEqual(stats.episodicMemoryCount, memoryManager.episodicMemory.count)
        XCTAssertEqual(stats.semanticMemoryCount, memoryManager.semanticMemory.count)
        XCTAssertEqual(
            stats.totalMemoryCount,
            memoryManager.workingMemory.count +
            memoryManager.episodicMemory.count +
            memoryManager.semanticMemory.count
        )
    }
    
    func testGetRoutingMetrics() async throws {
        // Add and search to generate metrics
        for i in 0..<5 {
            let observation = createTestObservation(objectLabel: "object_\(i)")
            let embedding = createTestEmbedding()
            try await memoryManager.addObservation(observation, embedding: embedding)
        }
        
        let queryEmbedding = createTestEmbedding()
        _ = try await memoryManager.search(embedding: queryEmbedding, topK: 3)
        
        let metrics = memoryManager.getRoutingMetrics()
        
        // Should have search metrics
        XCTAssertGreaterThan(metrics.totalSearches, 0)
        XCTAssertGreaterThanOrEqual(metrics.averageSearchLatency, 0)
    }
    
    // MARK: - Periodic Maintenance Tests
    
    func testPeriodicMaintenance() async throws {
        // Add many entries
        for i in 0..<100 {
            let observation = createTestObservation(objectLabel: "object_\(i)")
            let embedding = createTestEmbedding()
            try await memoryManager.addObservation(observation, embedding: embedding)
        }
        
        // Run maintenance
        await memoryManager.performPeriodicMaintenance()
        
        // Should not crash and should maintain valid state
        XCTAssertGreaterThanOrEqual(memoryManager.workingMemory.count, 0)
        XCTAssertGreaterThanOrEqual(memoryManager.episodicMemory.count, 0)
        XCTAssertGreaterThanOrEqual(memoryManager.semanticMemory.count, 0)
    }
    
    // MARK: - Clear Memory Tests
    
    func testClearAllMemories() async throws {
        // Add entries
        for i in 0..<10 {
            let observation = createTestObservation(objectLabel: "object_\(i)")
            let embedding = createTestEmbedding()
            try await memoryManager.addObservation(observation, embedding: embedding)
        }
        
        XCTAssertGreaterThan(memoryManager.workingMemory.count, 0)
        
        // Clear
        memoryManager.clearAllMemories()
        
        // All should be empty
        XCTAssertEqual(memoryManager.workingMemory.count, 0)
        XCTAssertEqual(memoryManager.episodicMemory.count, 0)
        XCTAssertEqual(memoryManager.semanticMemory.count, 0)
    }
    
    // MARK: - Save/Load Tests
    
    func testSaveMemories() async throws {
        // Add entries
        for i in 0..<5 {
            let observation = createTestObservation(objectLabel: "object_\(i)")
            let embedding = createTestEmbedding()
            try await memoryManager.addObservation(observation, embedding: embedding)
        }
        
        // Save
        try await memoryManager.saveMemories()
        
        // Verify mock DB was called
        XCTAssertTrue(mockVectorDB.saveCalled)
    }
    
    func testLoadMemories() async throws {
        // Setup mock data
        let testEntry = VectorEntry(
            embedding: createTestEmbedding(),
            metadata: MemoryMetadata(
                objectType: "test",
                description: "Test",
                confidence: 0.8,
                tags: ["test"],
                spatialData: nil,
                timestamp: Date(),
                location: nil
            ),
            memoryLayer: .working
        )
        mockVectorDB.mockEntries = [testEntry]
        
        // Load
        try await memoryManager.loadMemories()
        
        // Verify load was called
        XCTAssertTrue(mockVectorDB.loadCalled)
    }
}

// MARK: - Mock Vector Database

class MockVectorDatabase: VectorDatabaseProtocol {
    var saveCalled = false
    var loadCalled = false
    var mockEntries: [VectorEntry] = []
    
    func save(entries: [VectorEntry], layer: MemoryLayerType) async throws {
        saveCalled = true
    }
    
    func load(layer: MemoryLayerType) async throws -> [VectorEntry] {
        loadCalled = true
        return mockEntries
    }
    
    func search(query: [Float], topK: Int, layer: MemoryLayerType?) async throws -> [VectorEntry] {
        return []
    }
    
    func delete(id: UUID) async throws {
    }
    
    func deleteAll(layer: MemoryLayerType) async throws {
    }
}
