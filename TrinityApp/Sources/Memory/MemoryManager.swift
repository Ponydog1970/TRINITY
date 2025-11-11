//
//  MemoryManager.swift
//  TRINITY Vision Aid
//
//  Manages the three-layer memory architecture
//

import Foundation
import Combine

/// Manages all three layers of memory with intelligent routing
@MainActor
class MemoryManager: ObservableObject {
    // MARK: - Published Properties
    @Published var workingMemory: [VectorEntry] = []
    @Published var episodicMemory: [VectorEntry] = []
    @Published var semanticMemory: [VectorEntry] = []

    // MARK: - Configuration
    private let maxWorkingMemorySize = 100  // Max objects in working memory
    private let episodicMemoryWindow: TimeInterval = 30 * 24 * 60 * 60  // 30 days
    private let similarityThreshold: Float = 0.95  // For deduplication

    private let deduplicationEngine: DeduplicationEngine
    let vectorDatabase: VectorDatabase  // Made internal for RAG system access

    init(vectorDatabase: VectorDatabase) {
        self.vectorDatabase = vectorDatabase
        self.deduplicationEngine = DeduplicationEngine(
            similarityThreshold: similarityThreshold
        )
    }

    // MARK: - Memory Operations

    /// Add a new observation to the appropriate memory layer
    func addObservation(_ observation: Observation, embedding: [Float]) async throws {
        let metadata = MemoryMetadata(
            objectType: observation.detectedObjects.first?.label ?? "unknown",
            description: generateDescription(for: observation),
            confidence: observation.detectedObjects.first?.confidence ?? 0.0,
            tags: observation.detectedObjects.map { $0.label },
            spatialData: observation.detectedObjects.first?.spatialData,
            timestamp: observation.timestamp,
            location: observation.location?.coordinate
        )

        let newEntry = VectorEntry(
            embedding: embedding,
            metadata: metadata,
            memoryLayer: .working
        )

        // Check for duplicates
        if let existingEntry = try await deduplicationEngine.findDuplicate(
            newEntry,
            in: workingMemory
        ) {
            // Merge with existing entry
            let merged = deduplicationEngine.merge(existing: existingEntry, new: newEntry)
            updateEntry(merged)
        } else {
            // Add to working memory
            addToWorkingMemory(newEntry)
        }
    }

    /// Add entry to working memory with size management
    private func addToWorkingMemory(_ entry: VectorEntry) {
        workingMemory.append(entry)

        // Manage memory size
        if workingMemory.count > maxWorkingMemorySize {
            // Move least recently accessed to episodic memory
            consolidateWorkingMemory()
        }
    }

    /// Move entries from working to episodic memory
    private func consolidateWorkingMemory() {
        // Sort by last accessed time
        let sorted = workingMemory.sorted { $0.lastAccessed < $1.lastAccessed }

        // Move oldest 20% to episodic memory
        let moveCount = maxWorkingMemorySize / 5
        let toMove = sorted.prefix(moveCount)

        for entry in toMove {
            var episodicEntry = entry
            episodicEntry = VectorEntry(
                id: entry.id,
                embedding: entry.embedding,
                metadata: entry.metadata,
                memoryLayer: .episodic,
                accessCount: entry.accessCount,
                lastAccessed: entry.lastAccessed
            )
            episodicMemory.append(episodicEntry)
        }

        // Remove from working memory
        workingMemory.removeAll { entry in
            toMove.contains { $0.id == entry.id }
        }
    }

    /// Promote frequently accessed episodic memories to semantic
    func consolidateEpisodicMemory() async {
        // Find patterns and frequently accessed items
        let candidates = episodicMemory
            .filter { $0.accessCount > 10 }
            .sorted { $0.accessCount > $1.accessCount }

        for candidate in candidates.prefix(20) {
            // Check if similar concept already exists in semantic memory
            if let similar = try? await findSimilar(
                to: candidate.embedding,
                in: semanticMemory,
                threshold: 0.85
            ) {
                // Update existing semantic memory
                var updated = similar
                updated = VectorEntry(
                    id: similar.id,
                    embedding: similar.embedding,
                    metadata: similar.metadata,
                    memoryLayer: .semantic,
                    accessCount: similar.accessCount + candidate.accessCount,
                    lastAccessed: Date()
                )
                updateEntry(updated)
            } else {
                // Create new semantic memory
                var semanticEntry = candidate
                semanticEntry = VectorEntry(
                    id: candidate.id,
                    embedding: candidate.embedding,
                    metadata: candidate.metadata,
                    memoryLayer: .semantic,
                    accessCount: candidate.accessCount,
                    lastAccessed: candidate.lastAccessed
                )
                semanticMemory.append(semanticEntry)
            }
        }

        // Clean up old episodic memories
        cleanupEpisodicMemory()
    }

    /// Remove episodic memories older than the retention window
    private func cleanupEpisodicMemory() {
        let cutoffDate = Date().addingTimeInterval(-episodicMemoryWindow)
        episodicMemory.removeAll { $0.metadata.timestamp < cutoffDate }
    }

    /// Search across all memory layers
    func search(embedding: [Float], topK: Int = 5) async throws -> [VectorEntry] {
        var results: [VectorEntry] = []

        // Search working memory first (most relevant)
        let workingResults = workingMemory
            .map { entry in (entry, entry.similarity(to: embedding)) }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }
        results.append(contentsOf: workingResults)

        // Search episodic memory
        let episodicResults = episodicMemory
            .map { entry in (entry, entry.similarity(to: embedding)) }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }
        results.append(contentsOf: episodicResults)

        // Search semantic memory
        let semanticResults = semanticMemory
            .map { entry in (entry, entry.similarity(to: embedding)) }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }
        results.append(contentsOf: semanticResults)

        // Sort all results by similarity and return top K
        let allResults = results
            .map { entry in (entry, entry.similarity(to: embedding)) }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }

        // Update access counts
        for entry in allResults {
            incrementAccessCount(for: entry.id)
        }

        return Array(allResults)
    }

    /// Find similar entries in a specific memory layer
    private func findSimilar(
        to embedding: [Float],
        in memory: [VectorEntry],
        threshold: Float
    ) async throws -> VectorEntry? {
        return memory
            .map { entry in (entry, entry.similarity(to: embedding)) }
            .filter { $0.1 >= threshold }
            .sorted { $0.1 > $1.1 }
            .first?.0
    }

    /// Update an existing memory entry
    private func updateEntry(_ entry: VectorEntry) {
        switch entry.memoryLayer {
        case .working:
            if let index = workingMemory.firstIndex(where: { $0.id == entry.id }) {
                workingMemory[index] = entry
            }
        case .episodic:
            if let index = episodicMemory.firstIndex(where: { $0.id == entry.id }) {
                episodicMemory[index] = entry
            }
        case .semantic:
            if let index = semanticMemory.firstIndex(where: { $0.id == entry.id }) {
                semanticMemory[index] = entry
            }
        }
    }

    /// Increment access count for an entry
    private func incrementAccessCount(for id: UUID) {
        if let index = workingMemory.firstIndex(where: { $0.id == id }) {
            var entry = workingMemory[index]
            entry = VectorEntry(
                id: entry.id,
                embedding: entry.embedding,
                metadata: entry.metadata,
                memoryLayer: entry.memoryLayer,
                accessCount: entry.accessCount + 1,
                lastAccessed: Date()
            )
            workingMemory[index] = entry
        }
        // Similar for episodic and semantic...
    }

    /// Generate natural language description from observation
    private func generateDescription(for observation: Observation) -> String {
        guard !observation.detectedObjects.isEmpty else {
            return "Unknown scene"
        }

        let objects = observation.detectedObjects.prefix(3).map { $0.label }
        return objects.joined(separator: ", ")
    }

    // MARK: - Persistence

    /// Save all memory layers to disk
    func saveMemories() async throws {
        try await vectorDatabase.save(entries: workingMemory, layer: .working)
        try await vectorDatabase.save(entries: episodicMemory, layer: .episodic)
        try await vectorDatabase.save(entries: semanticMemory, layer: .semantic)
    }

    /// Load all memory layers from disk
    func loadMemories() async throws {
        workingMemory = try await vectorDatabase.load(layer: .working)
        episodicMemory = try await vectorDatabase.load(layer: .episodic)
        semanticMemory = try await vectorDatabase.load(layer: .semantic)
    }

    /// Clear all memories (for testing or reset)
    func clearAllMemories() {
        workingMemory.removeAll()
        episodicMemory.removeAll()
        semanticMemory.removeAll()
    }
}
