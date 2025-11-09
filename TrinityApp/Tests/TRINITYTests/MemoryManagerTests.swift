//
//  MemoryManagerTests.swift
//  TRINITY Vision Aid Tests
//
//  Unit tests for MemoryManager
//

import XCTest
@testable import TRINITY

@MainActor
final class MemoryManagerTests: XCTestCase {
    var memoryManager: MemoryManager!
    var vectorDatabase: VectorDatabase!

    override func setUp() async throws {
        vectorDatabase = try VectorDatabase()
        memoryManager = MemoryManager(vectorDatabase: vectorDatabase)

        // Clear any existing data
        memoryManager.clearAllMemories()
    }

    override func tearDown() async throws {
        memoryManager.clearAllMemories()
        memoryManager = nil
        vectorDatabase = nil
    }

    // MARK: - Working Memory Tests

    func testAddObservationToWorkingMemory() async throws {
        // Given
        let observation = createTestObservation(label: "table")
        let embedding = createTestEmbedding()

        // When
        try await memoryManager.addObservation(observation, embedding: embedding)

        // Then
        XCTAssertEqual(memoryManager.workingMemory.count, 1)
        XCTAssertEqual(memoryManager.workingMemory.first?.metadata.objectType, "table")
    }

    func testWorkingMemoryConsolidation() async throws {
        // Given: Fill working memory beyond capacity
        for i in 0..<120 {
            let observation = createTestObservation(label: "object_\(i)")
            let embedding = createTestEmbedding(seed: i)
            try await memoryManager.addObservation(observation, embedding: embedding)
        }

        // Then: Working memory should be capped at 100
        XCTAssertEqual(memoryManager.workingMemory.count, 100)
        // And some entries should have moved to episodic memory
        XCTAssertGreaterThan(memoryManager.episodicMemory.count, 0)
    }

    // MARK: - Deduplication Tests

    func testDeduplicationOfSimilarObservations() async throws {
        // Given: Same observation twice
        let observation = createTestObservation(label: "table")
        let embedding = createTestEmbedding()

        // When
        try await memoryManager.addObservation(observation, embedding: embedding)
        try await memoryManager.addObservation(observation, embedding: embedding)

        // Then: Should only have 1 entry (merged)
        XCTAssertEqual(memoryManager.workingMemory.count, 1)
        // And access count should be incremented
        XCTAssertGreaterThan(memoryManager.workingMemory.first?.accessCount ?? 0, 1)
    }

    func testNoDuplicationOfDifferentObservations() async throws {
        // Given: Different observations
        let observation1 = createTestObservation(label: "table")
        let observation2 = createTestObservation(label: "chair")
        let embedding1 = createTestEmbedding(seed: 1)
        let embedding2 = createTestEmbedding(seed: 100)

        // When
        try await memoryManager.addObservation(observation1, embedding: embedding1)
        try await memoryManager.addObservation(observation2, embedding: embedding2)

        // Then: Should have 2 separate entries
        XCTAssertEqual(memoryManager.workingMemory.count, 2)
    }

    // MARK: - Search Tests

    func testSearchReturnsRelevantResults() async throws {
        // Given: Multiple observations
        let labels = ["table", "chair", "lamp", "desk", "monitor"]
        for (i, label) in labels.enumerated() {
            let observation = createTestObservation(label: label)
            let embedding = createTestEmbedding(seed: i * 10)
            try await memoryManager.addObservation(observation, embedding: embedding)
        }

        // When: Search with specific embedding
        let queryEmbedding = createTestEmbedding(seed: 0)
        let results = try await memoryManager.search(embedding: queryEmbedding, topK: 3)

        // Then: Should return top 3 results
        XCTAssertEqual(results.count, 3)
    }

    func testSearchUpdatesAccessCount() async throws {
        // Given
        let observation = createTestObservation(label: "table")
        let embedding = createTestEmbedding()
        try await memoryManager.addObservation(observation, embedding: embedding)

        let initialAccessCount = memoryManager.workingMemory.first?.accessCount ?? 0

        // When: Search multiple times
        for _ in 0..<5 {
            _ = try await memoryManager.search(embedding: embedding, topK: 1)
        }

        // Then: Access count should increase
        let finalAccessCount = memoryManager.workingMemory.first?.accessCount ?? 0
        XCTAssertGreaterThan(finalAccessCount, initialAccessCount)
    }

    // MARK: - Episodic Memory Tests

    func testEpisodicMemoryConsolidation() async throws {
        // Given: Observations with high access counts
        for i in 0..<15 {
            let observation = createTestObservation(label: "frequent_object")
            let embedding = createTestEmbedding()
            try await memoryManager.addObservation(observation, embedding: embedding)
        }

        // Manually move to episodic and set high access count
        if let entry = memoryManager.workingMemory.first {
            var episodicEntry = entry
            episodicEntry = VectorEntry(
                id: entry.id,
                embedding: entry.embedding,
                metadata: entry.metadata,
                memoryLayer: .episodic,
                accessCount: 15,
                lastAccessed: entry.lastAccessed
            )
            memoryManager.episodicMemory.append(episodicEntry)
        }

        // When: Consolidate
        await memoryManager.consolidateEpisodicMemory()

        // Then: High-access entries should move to semantic memory
        XCTAssertGreaterThan(memoryManager.semanticMemory.count, 0)
    }

    // MARK: - Persistence Tests

    func testSaveAndLoadMemories() async throws {
        // Given: Populate memory
        let observation = createTestObservation(label: "table")
        let embedding = createTestEmbedding()
        try await memoryManager.addObservation(observation, embedding: embedding)

        // When: Save
        try await memoryManager.saveMemories()

        // Create new memory manager
        let newMemoryManager = MemoryManager(vectorDatabase: vectorDatabase)

        // And: Load
        try await newMemoryManager.loadMemories()

        // Then: Should have same data
        XCTAssertEqual(newMemoryManager.workingMemory.count, memoryManager.workingMemory.count)
    }

    // MARK: - Helper Methods

    private func createTestObservation(
        label: String,
        timestamp: Date = Date()
    ) -> Observation {
        let detectedObject = DetectedObject(
            id: UUID(),
            label: label,
            confidence: 0.9,
            boundingBox: BoundingBox(x: 0, y: 0, z: 0, width: 1, height: 1, depth: 1),
            spatialData: SpatialData(
                depth: 2.0,
                boundingBox: BoundingBox(x: 0, y: 0, z: 0, width: 1, height: 1, depth: 1),
                orientation: Orientation(pitch: 0, yaw: 0, roll: 0),
                confidence: 0.9
            )
        )

        return Observation(
            timestamp: timestamp,
            cameraImage: nil,
            depthMap: nil,
            detectedObjects: [detectedObject],
            location: nil,
            deviceOrientation: Orientation(pitch: 0, yaw: 0, roll: 0)
        )
    }

    private func createTestEmbedding(seed: Int = 0, dimension: Int = 512) -> [Float] {
        var embedding = [Float](repeating: 0.0, count: dimension)

        // Create deterministic embedding based on seed
        for i in 0..<dimension {
            embedding[i] = sin(Float(i + seed) * 0.1)
        }

        // Normalize
        let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        return embedding.map { $0 / magnitude }
    }
}
