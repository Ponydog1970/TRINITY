//
//  IntegrationTests.swift
//  TRINITY Vision Aid Tests
//
//  Integration tests for end-to-end workflows
//

import XCTest
@testable import TRINITY

@MainActor
final class IntegrationTests: XCTestCase {
    var coordinator: TrinityCoordinator!

    override func setUp() async throws {
        coordinator = try TrinityCoordinator()
    }

    override func tearDown() async throws {
        if coordinator.isRunning {
            await coordinator.stop()
        }
        coordinator = nil
    }

    // MARK: - End-to-End Flow Tests

    func testCompleteObservationPipeline() async throws {
        // Test the full pipeline from observation to output

        // Given: Start the system
        try await coordinator.start()
        XCTAssertTrue(coordinator.isRunning)

        // When: Process an observation
        await coordinator.describeCurrentScene()

        // Wait for processing
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Then: Should have generated output
        XCTAssertFalse(coordinator.lastSpokenMessage.isEmpty)

        // Cleanup
        await coordinator.stop()
    }

    func testMemoryConsolidationFlow() async throws {
        // Test memory flow through all layers

        // Given: Populate working memory
        let vectorDB = try VectorDatabase()
        let memoryManager = MemoryManager(vectorDatabase: vectorDB)

        for i in 0..<120 {
            let observation = createTestObservation(label: "object_\(i)")
            let embedding = createTestEmbedding(seed: i)
            try await memoryManager.addObservation(observation, embedding: embedding)
        }

        // Then: Verify consolidation
        XCTAssertLessThanOrEqual(memoryManager.workingMemory.count, 100)
        XCTAssertGreaterThan(memoryManager.episodicMemory.count, 0)

        // When: Consolidate episodic memory
        // First, manually set high access counts
        for i in 0..<min(15, memoryManager.episodicMemory.count) {
            var entry = memoryManager.episodicMemory[i]
            entry = VectorEntry(
                id: entry.id,
                embedding: entry.embedding,
                metadata: entry.metadata,
                memoryLayer: entry.memoryLayer,
                accessCount: 15,
                lastAccessed: entry.lastAccessed
            )
            memoryManager.episodicMemory[i] = entry
        }

        await memoryManager.consolidateEpisodicMemory()

        // Then: High-access entries should promote to semantic
        XCTAssertGreaterThan(memoryManager.semanticMemory.count, 0)
    }

    func testErrorRecoveryFlow() async throws {
        // Test error handling and recovery

        // Given: Operation that will fail
        let executor = RetryExecutor.self

        var attempts = 0
        let maxAttempts = 3

        do {
            let _ = try await executor.execute(
                maxAttempts: maxAttempts,
                backoff: .constant(0.1)
            ) {
                attempts += 1
                if attempts < maxAttempts {
                    throw NSError(domain: "Test", code: -1, userInfo: nil)
                }
                return "Success"
            }

            // Should succeed on 3rd attempt
            XCTAssertEqual(attempts, maxAttempts)

        } catch {
            XCTFail("Should have recovered after retries")
        }
    }

    func testCircuitBreakerFlow() async throws {
        // Test circuit breaker pattern

        let circuitBreaker = CircuitBreaker(
            failureThreshold: 3,
            successThreshold: 2,
            timeout: 1.0
        )

        // Cause failures to open circuit
        for _ in 0..<3 {
            do {
                try await circuitBreaker.execute {
                    throw NSError(domain: "Test", code: -1)
                }
            } catch {
                // Expected
            }
        }

        // Circuit should be open now
        do {
            try await circuitBreaker.execute {
                return "Should not execute"
            }
            XCTFail("Circuit breaker should be open")
        } catch {
            // Expected - circuit is open
        }

        // Wait for timeout
        try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds

        // Circuit should be half-open, allow test
        do {
            let _ = try await circuitBreaker.execute {
                return "Success"
            }
            // Should succeed
        } catch {
            XCTFail("Circuit should be half-open and allow operations")
        }
    }

    // MARK: - Agent Coordination Tests

    func testAgentPipeline() async throws {
        // Test interaction between agents

        let vectorDB = try VectorDatabase()
        let memoryManager = MemoryManager(vectorDatabase: vectorDB)
        let embeddingGenerator = try EmbeddingGenerator()

        // 1. Perception Agent
        let perceptionAgent = try PerceptionAgent(embeddingGenerator: embeddingGenerator)

        let perceptionInput = PerceptionInput(
            cameraFrame: nil,
            depthData: nil,
            arFrame: nil,
            timestamp: Date()
        )

        let perceptionOutput = try await perceptionAgent.process(perceptionInput)

        XCTAssertNotNil(perceptionOutput.sceneDescription)

        // 2. Create observation and store in memory
        let observation = createTestObservation(label: "table")
        let embedding = createTestEmbedding()
        try await memoryManager.addObservation(observation, embedding: embedding)

        // 3. Context Agent
        let contextAgent = ContextAgent(memoryManager: memoryManager)
        let searchResults = try await memoryManager.search(embedding: embedding, topK: 5)

        let contextInput = ContextInput(
            currentObservation: observation,
            query: nil,
            memorySearchResults: searchResults
        )

        let contextOutput = try await contextAgent.process(contextInput)

        XCTAssertFalse(contextOutput.contextSummary.isEmpty)

        // 4. Navigation Agent
        let navigationAgent = NavigationAgent()

        let navigationInput = NavigationInput(
            currentLocation: nil,
            destination: nil,
            spatialMap: perceptionOutput.spatialMap,
            detectedObjects: observation.detectedObjects,
            userHeading: 0.0
        )

        let navigationOutput = try await navigationAgent.process(navigationInput)

        XCTAssertNotNil(navigationOutput.instructions)

        // 5. Communication Agent
        let communicationAgent = CommunicationAgent()

        let communicationInput = CommunicationInput(
            perceptionOutput: perceptionOutput,
            navigationOutput: navigationOutput,
            contextOutput: contextOutput,
            priority: .normal
        )

        let communicationOutput = try await communicationAgent.process(communicationInput)

        XCTAssertFalse(communicationOutput.spokenMessage.isEmpty)
    }

    // MARK: - Performance Tests

    func testSystemPerformance() async throws {
        // Test end-to-end performance

        let vectorDB = try VectorDatabase()
        let memoryManager = MemoryManager(vectorDatabase: vectorDB)
        let embeddingGenerator = try EmbeddingGenerator()

        // Populate memory with realistic dataset
        for i in 0..<100 {
            let observation = createTestObservation(label: "object_\(i)")
            let embedding = createTestEmbedding(seed: i)
            try await memoryManager.addObservation(observation, embedding: embedding)
        }

        // Measure search performance
        let queryEmbedding = createTestEmbedding()

        let startTime = Date()
        let results = try await memoryManager.search(embedding: queryEmbedding, topK: 10)
        let duration = Date().timeIntervalSince(startTime)

        // Should complete in < 50ms
        XCTAssertLessThan(duration, 0.05)
        XCTAssertEqual(results.count, 10)
    }

    func testMemoryCompressionPerformance() async throws {
        // Test compression with large dataset

        let config = TrinityConfiguration.default
        let compressionEngine = MemoryCompressionEngine(config: config)

        // Create large dataset
        var entries: [VectorEntry] = []
        for i in 0..<10_000 {
            entries.append(createVectorEntry(seed: i))
        }

        // Compress
        let startTime = Date()
        let compressed = try await compressionEngine.compressIfNeeded(entries)
        let duration = Date().timeIntervalSince(startTime)

        // Should complete in reasonable time (< 5s for 10k entries)
        XCTAssertLessThan(duration, 5.0)

        // Should reduce size
        XCTAssertLessThan(compressed.count, entries.count)

        let stats = compressionEngine.getCompressionStats(
            original: entries,
            compressed: compressed
        )

        print("Compression stats: \(stats.compressionRatio)x reduction")
    }

    // MARK: - Stress Tests

    func testConcurrentOperations() async throws {
        // Test system under concurrent load

        let vectorDB = try VectorDatabase()
        let memoryManager = MemoryManager(vectorDatabase: vectorDB)

        // Run concurrent operations
        await withTaskGroup(of: Void.self) { group in
            // Add observations concurrently
            for i in 0..<50 {
                group.addTask {
                    let observation = self.createTestObservation(label: "concurrent_\(i)")
                    let embedding = self.createTestEmbedding(seed: i)
                    try? await memoryManager.addObservation(observation, embedding: embedding)
                }
            }

            // Search concurrently
            for i in 0..<50 {
                group.addTask {
                    let embedding = self.createTestEmbedding(seed: i * 10)
                    _ = try? await memoryManager.search(embedding: embedding, topK: 5)
                }
            }
        }

        // Should handle concurrent operations without crashes
        XCTAssertGreaterThan(memoryManager.workingMemory.count, 0)
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

        for i in 0..<dimension {
            embedding[i] = sin(Float(i + seed) * 0.1)
        }

        let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        return embedding.map { $0 / magnitude }
    }

    private func createVectorEntry(seed: Int) -> VectorEntry {
        return VectorEntry(
            id: UUID(),
            embedding: createTestEmbedding(seed: seed),
            metadata: MemoryMetadata(
                objectType: "object_\(seed)",
                description: "Test object",
                confidence: 0.9,
                tags: ["test"],
                spatialData: nil,
                timestamp: Date(),
                location: nil
            ),
            memoryLayer: .semantic,
            accessCount: Int.random(in: 0...20),
            lastAccessed: Date()
        )
    }
}
