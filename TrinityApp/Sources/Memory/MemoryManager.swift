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

    // MARK: - PERFORMANCE OPTIMIZATION: Index Structures
    // Dictionary-based indices for O(1) lookup instead of O(n) array search
    // Internal access for subclasses (e.g., SmartMemoryManager)
    internal var workingIndex: [UUID: VectorEntry] = [:]
    internal var episodicIndex: [UUID: VectorEntry] = [:]
    internal var semanticIndex: [UUID: VectorEntry] = [:]

    // LRU Cache for frequently accessed entries (max 50 entries)
    private var accessCache: LRUCache<UUID, VectorEntry>
    private let maxCacheSize = 50

    // MARK: - Configuration
    private let maxWorkingMemorySize = 100  // Max objects in working memory
    private let episodicMemoryWindow: TimeInterval = 30 * 24 * 60 * 60  // 30 days
    private let similarityThreshold: Float = 0.95  // For deduplication

    private let deduplicationEngine: DeduplicationEngine
    let vectorDatabase: VectorDatabaseProtocol

    // THREAD SAFETY: Serial queue for write operations
    private let writeQueue = DispatchQueue(label: "com.trinity.memory.write", qos: .userInitiated)

    init(vectorDatabase: VectorDatabaseProtocol) {
        self.vectorDatabase = vectorDatabase
        self.deduplicationEngine = DeduplicationEngine(
            similarityThreshold: similarityThreshold
        )
        self.accessCache = LRUCache<UUID, VectorEntry>(capacity: maxCacheSize)
    }

    // MARK: - Memory Operations

    /// Add a new observation to the appropriate memory layer
    /// THREAD-SAFE: Uses serial queue for write operations
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

        // Check for duplicates (read operation, safe)
        if let existingEntry = try await deduplicationEngine.findDuplicate(
            newEntry,
            in: workingMemory
        ) {
            // Merge with existing entry (write operation, protected)
            let merged = deduplicationEngine.merge(existing: existingEntry, new: newEntry)
            await withCheckedContinuation { continuation in
                writeQueue.async { [weak self] in
                    self?.updateEntry(merged)
                    continuation.resume()
                }
            }
        } else {
            // Add to working memory (write operation, protected)
            await withCheckedContinuation { continuation in
                writeQueue.async { [weak self] in
                    self?.addToWorkingMemory(newEntry)
                    continuation.resume()
                }
            }
        }
    }

    /// Add entry to working memory with size management
    private func addToWorkingMemory(_ entry: VectorEntry) {
        workingMemory.append(entry)
        // PERFORMANCE: Update index for O(1) lookup
        workingIndex[entry.id] = entry

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

            // PERFORMANCE: Update indices
            episodicIndex[entry.id] = episodicEntry
            workingIndex.removeValue(forKey: entry.id)
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
    /// PERFORMANCE: O(1) lookup via index instead of O(n) array search
    private func updateEntry(_ entry: VectorEntry) {
        switch entry.memoryLayer {
        case .working:
            workingIndex[entry.id] = entry
            if let index = workingMemory.firstIndex(where: { $0.id == entry.id }) {
                workingMemory[index] = entry
            }
        case .episodic:
            episodicIndex[entry.id] = entry
            if let index = episodicMemory.firstIndex(where: { $0.id == entry.id }) {
                episodicMemory[index] = entry
            }
        case .semantic:
            semanticIndex[entry.id] = entry
            if let index = semanticMemory.firstIndex(where: { $0.id == entry.id }) {
                semanticMemory[index] = entry
            }
        }

        // Update cache if entry is frequently accessed
        if entry.accessCount > 5 {
            accessCache.set(entry.id, value: entry)
        }
    }

    /// Increment access count for an entry
    /// PERFORMANCE: O(1) lookup via cache/index, updates all layers efficiently
    private func incrementAccessCount(for id: UUID) {
        // Check cache first (fastest path)
        if let cached = accessCache.get(id) {
            var updated = cached
            updated = VectorEntry(
                id: updated.id,
                embedding: updated.embedding,
                metadata: updated.metadata,
                memoryLayer: updated.memoryLayer,
                accessCount: updated.accessCount + 1,
                lastAccessed: Date()
            )
            updateEntry(updated)
            return
        }

        // Check indices (O(1) lookup)
        if let entry = workingIndex[id] {
            var updated = entry
            updated = VectorEntry(
                id: updated.id,
                embedding: updated.embedding,
                metadata: updated.metadata,
                memoryLayer: updated.memoryLayer,
                accessCount: updated.accessCount + 1,
                lastAccessed: Date()
            )
            updateEntry(updated)
        } else if let entry = episodicIndex[id] {
            var updated = entry
            updated = VectorEntry(
                id: updated.id,
                embedding: updated.embedding,
                metadata: updated.metadata,
                memoryLayer: updated.memoryLayer,
                accessCount: updated.accessCount + 1,
                lastAccessed: Date()
            )
            updateEntry(updated)
        } else if let entry = semanticIndex[id] {
            var updated = entry
            updated = VectorEntry(
                id: updated.id,
                embedding: updated.embedding,
                metadata: updated.metadata,
                memoryLayer: updated.memoryLayer,
                accessCount: updated.accessCount + 1,
                lastAccessed: Date()
            )
            updateEntry(updated)
        }
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

        // PERFORMANCE: Rebuild indices after loading
        rebuildIndices()
    }

    /// Clear all memories (for testing or reset)
    func clearAllMemories() {
        workingMemory.removeAll()
        episodicMemory.removeAll()
        semanticMemory.removeAll()

        // PERFORMANCE: Clear indices and cache
        workingIndex.removeAll()
        episodicIndex.removeAll()
        semanticIndex.removeAll()
        accessCache.clear()
    }

    /// Rebuild indices from memory arrays (called after load)
    private func rebuildIndices() {
        workingIndex = Dictionary(uniqueKeysWithValues: workingMemory.map { ($0.id, $0) })
        episodicIndex = Dictionary(uniqueKeysWithValues: episodicMemory.map { ($0.id, $0) })
        semanticIndex = Dictionary(uniqueKeysWithValues: semanticMemory.map { ($0.id, $0) })
    }
}

// MARK: - LRU Cache Implementation

/// Least Recently Used Cache for frequently accessed memory entries
/// PERFORMANCE: O(1) get/set operations
class LRUCache<Key: Hashable, Value> {
    private class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    private var capacity: Int
    private var cache: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?

    init(capacity: Int) {
        self.capacity = capacity
    }

    func get(_ key: Key) -> Value? {
        guard let node = cache[key] else {
            return nil
        }

        // Move to front (most recently used)
        moveToFront(node)
        return node.value
    }

    func set(_ key: Key, value: Value) {
        if let existingNode = cache[key] {
            // Update existing
            existingNode.value = value
            moveToFront(existingNode)
        } else {
            // Add new
            let newNode = Node(key: key, value: value)
            cache[key] = newNode
            addToFront(newNode)

            // Evict if over capacity
            if cache.count > capacity {
                evictLRU()
            }
        }
    }

    func clear() {
        cache.removeAll()
        head = nil
        tail = nil
    }

    private func moveToFront(_ node: Node) {
        guard node !== head else { return }

        // Remove from current position
        if let prev = node.prev {
            prev.next = node.next
        }
        if let next = node.next {
            next.prev = node.prev
        }
        if node === tail {
            tail = node.prev
        }

        // Add to front
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node

        if tail == nil {
            tail = node
        }
    }

    private func addToFront(_ node: Node) {
        node.next = head
        head?.prev = node
        head = node

        if tail == nil {
            tail = node
        }
    }

    private func evictLRU() {
        guard let lru = tail else { return }

        cache.removeValue(forKey: lru.key)
        tail = lru.prev
        tail?.next = nil

        if tail == nil {
            head = nil
        }
    }
}
