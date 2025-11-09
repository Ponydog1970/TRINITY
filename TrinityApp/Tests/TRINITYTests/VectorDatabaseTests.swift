//
//  VectorDatabaseTests.swift
//  TRINITY Vision Aid Tests
//
//  Unit tests for VectorDatabase
//

import XCTest
@testable import TRINITY

final class VectorDatabaseTests: XCTestCase {
    var database: VectorDatabase!

    override func setUp() throws {
        database = try VectorDatabase()

        // Clear all data
        try? database.deleteAll(layer: .working)
        try? database.deleteAll(layer: .episodic)
        try? database.deleteAll(layer: .semantic)
    }

    override func tearDown() async throws {
        try? await database.deleteAll(layer: .working)
        try? await database.deleteAll(layer: .episodic)
        try? await database.deleteAll(layer: .semantic)
        database = nil
    }

    // MARK: - Save/Load Tests

    func testSaveAndLoadEntries() async throws {
        // Given
        let entries = createTestEntries(count: 10)

        // When
        try await database.save(entries: entries, layer: .working)
        let loaded = try await database.load(layer: .working)

        // Then
        XCTAssertEqual(loaded.count, entries.count)
        XCTAssertEqual(loaded.first?.id, entries.first?.id)
    }

    func testLoadFromEmptyDatabase() async throws {
        // When
        let loaded = try await database.load(layer: .working)

        // Then
        XCTAssertEqual(loaded.count, 0)
    }

    // MARK: - Search Tests

    func testSearchReturnsTopKResults() async throws {
        // Given
        let entries = createTestEntries(count: 20)
        try await database.save(entries: entries, layer: .working)

        let queryEmbedding = createTestEmbedding(seed: 0)

        // When
        let results = try await database.search(query: queryEmbedding, topK: 5, layer: .working)

        // Then
        XCTAssertEqual(results.count, 5)
    }

    func testSearchOrdersBySimiliarity() async throws {
        // Given
        let entries = createTestEntries(count: 10)
        try await database.save(entries: entries, layer: .working)

        let queryEmbedding = createTestEmbedding(seed: 0)

        // When
        let results = try await database.search(query: queryEmbedding, topK: 10, layer: .working)

        // Then: Results should be ordered by similarity (descending)
        for i in 0..<(results.count - 1) {
            let similarity1 = cosineSimilarity(queryEmbedding, results[i].embedding)
            let similarity2 = cosineSimilarity(queryEmbedding, results[i + 1].embedding)
            XCTAssertGreaterThanOrEqual(similarity1, similarity2)
        }
    }

    func testSearchAcrossAllLayers() async throws {
        // Given: Entries in different layers
        let workingEntries = createTestEntries(count: 5, layer: .working)
        let episodicEntries = createTestEntries(count: 5, layer: .episodic)
        let semanticEntries = createTestEntries(count: 5, layer: .semantic)

        try await database.save(entries: workingEntries, layer: .working)
        try await database.save(entries: episodicEntries, layer: .episodic)
        try await database.save(entries: semanticEntries, layer: .semantic)

        let queryEmbedding = createTestEmbedding(seed: 0)

        // When: Search without specifying layer
        let results = try await database.search(query: queryEmbedding, topK: 10, layer: nil)

        // Then: Should find entries from all layers
        XCTAssertEqual(results.count, 10)
    }

    // MARK: - Delete Tests

    func testDeleteSpecificEntry() async throws {
        // Given
        let entries = createTestEntries(count: 5)
        try await database.save(entries: entries, layer: .working)

        let entryToDelete = entries[2]

        // When
        try await database.delete(id: entryToDelete.id)

        let remaining = try await database.load(layer: .working)

        // Then
        XCTAssertEqual(remaining.count, 4)
        XCTAssertFalse(remaining.contains(where: { $0.id == entryToDelete.id }))
    }

    func testDeleteAllInLayer() async throws {
        // Given
        let workingEntries = createTestEntries(count: 5, layer: .working)
        let episodicEntries = createTestEntries(count: 3, layer: .episodic)

        try await database.save(entries: workingEntries, layer: .working)
        try await database.save(entries: episodicEntries, layer: .episodic)

        // When
        try await database.deleteAll(layer: .working)

        // Then
        let working = try await database.load(layer: .working)
        let episodic = try await database.load(layer: .episodic)

        XCTAssertEqual(working.count, 0)
        XCTAssertEqual(episodic.count, 3)
    }

    // MARK: - Statistics Tests

    func testGetStatistics() async throws {
        // Given
        try await database.save(entries: createTestEntries(count: 10, layer: .working), layer: .working)
        try await database.save(entries: createTestEntries(count: 20, layer: .episodic), layer: .episodic)
        try await database.save(entries: createTestEntries(count: 30, layer: .semantic), layer: .semantic)

        // When
        let stats = try await database.getStatistics()

        // Then
        XCTAssertEqual(stats.workingMemoryCount, 10)
        XCTAssertEqual(stats.episodicMemoryCount, 20)
        XCTAssertEqual(stats.semanticMemoryCount, 30)
        XCTAssertEqual(stats.totalCount, 60)
    }

    // MARK: - Performance Tests

    func testLargeScaleSearch() async throws {
        // Given: Large dataset
        let entries = createTestEntries(count: 1000)
        try await database.save(entries: entries, layer: .semantic)

        let queryEmbedding = createTestEmbedding(seed: 0)

        // When
        let startTime = Date()
        let results = try await database.search(query: queryEmbedding, topK: 10, layer: .semantic)
        let duration = Date().timeIntervalSince(startTime)

        // Then: Should complete in reasonable time (< 100ms for 1000 vectors)
        XCTAssertLessThan(duration, 0.1)
        XCTAssertEqual(results.count, 10)
    }

    // MARK: - Helper Methods

    private func createTestEntries(
        count: Int,
        layer: MemoryLayerType = .working
    ) -> [VectorEntry] {
        return (0..<count).map { i in
            VectorEntry(
                id: UUID(),
                embedding: createTestEmbedding(seed: i),
                metadata: MemoryMetadata(
                    objectType: "object_\(i)",
                    description: "Test object \(i)",
                    confidence: 0.9,
                    tags: ["test"],
                    spatialData: nil,
                    timestamp: Date(),
                    location: nil
                ),
                memoryLayer: layer,
                accessCount: 0,
                lastAccessed: Date()
            )
        }
    }

    private func createTestEmbedding(seed: Int = 0, dimension: Int = 512) -> [Float] {
        var embedding = [Float](repeating: 0.0, count: dimension)

        for i in 0..<dimension {
            embedding[i] = sin(Float(i + seed) * 0.1)
        }

        let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        return embedding.map { $0 / magnitude }
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
