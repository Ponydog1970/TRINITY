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
    private var maxWorkingMemorySize = 100  // Max objects in working memory (adaptive)
    private let baseWorkingMemorySize = 100  // Base size for adaptive scaling
    private let episodicMemoryWindow: TimeInterval = 30 * 24 * 60 * 60  // 30 days
    private let similarityThreshold: Float = 0.95  // For deduplication

    private let deduplicationEngine: DeduplicationEngine
    private let vectorDatabase: VectorDatabase
    private let resourceMonitor: ResourceMonitor
    private let consolidationPredictor: ConsolidationPredictor
    
    // MARK: - Usage Metrics
    private var routingMetrics: RoutingMetrics = RoutingMetrics()
    
    struct RoutingMetrics {
        var workingToEpisodicTransitions: Int = 0
        var episodicToSemanticTransitions: Int = 0
        var totalSearches: Int = 0
        var averageSearchLatency: TimeInterval = 0.0
    }

    init(vectorDatabase: VectorDatabase) {
        self.vectorDatabase = vectorDatabase
        self.deduplicationEngine = DeduplicationEngine(
            similarityThreshold: similarityThreshold
        )
        self.resourceMonitor = ResourceMonitor()
        self.consolidationPredictor = ConsolidationPredictor()
        
        // Start adaptive resource monitoring
        Task {
            await startAdaptiveResourceManagement()
        }
    }
    
    // MARK: - Adaptive Resource Management
    
    /// Continuously monitor and adjust memory limits based on system resources
    private func startAdaptiveResourceManagement() async {
        // Adjust working memory size based on available resources
        let recommendedSize = resourceMonitor.getRecommendedWorkingMemorySize(
            baseSize: baseWorkingMemorySize
        )
        maxWorkingMemorySize = recommendedSize
        
        // Check if aggressive consolidation is needed
        if resourceMonitor.shouldConsolidateAggressively() {
            await performAggressiveConsolidation()
        }
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

        // Manage memory size with adaptive limits
        if workingMemory.count > maxWorkingMemorySize {
            // Move least recently accessed to episodic memory using LRU strategy
            consolidateWorkingMemoryWithLRU()
        }
    }

    /// Move entries from working to episodic memory using LRU with priority
    private func consolidateWorkingMemoryWithLRU() {
        // Calculate priority scores for each entry (higher = more important to keep)
        let scoredEntries = workingMemory.map { entry -> (entry: VectorEntry, priority: Double) in
            let priority = calculatePriority(for: entry)
            return (entry, priority)
        }
        
        // Sort by priority (ascending) - lowest priority will be evicted first
        let sorted = scoredEntries.sorted { $0.priority < $1.priority }
        
        // Determine how many to move based on resource constraints
        let targetSize = Int(Double(maxWorkingMemorySize) * 0.8) // Target 80% capacity
        let moveCount = max(workingMemory.count - targetSize, maxWorkingMemorySize / 5)
        let toMove = sorted.prefix(moveCount)
        
        // Use ML predictor to decide consolidation for each entry
        for (entry, _) in toMove {
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
            routingMetrics.workingToEpisodicTransitions += 1
            
            // Train predictor with this consolidation decision
            consolidationPredictor.train(entry: entry, shouldConsolidate: true)
        }

        // Remove from working memory
        workingMemory.removeAll { entry in
            toMove.contains { $0.entry.id == entry.id }
        }
    }
    
    /// Calculate priority score for LRU eviction (higher = keep in memory)
    private func calculatePriority(for entry: VectorEntry) -> Double {
        let now = Date()
        
        // Recency score (0-1, higher if accessed recently)
        let timeSinceAccess = now.timeIntervalSince(entry.lastAccessed)
        let recencyScore = exp(-timeSinceAccess / 300.0) // 5-minute decay
        
        // Frequency score (normalized)
        let frequencyScore = min(Double(entry.accessCount) / 20.0, 1.0)
        
        // Confidence score
        let confidenceScore = Double(entry.metadata.confidence)
        
        // Weighted combination
        let priority = (recencyScore * 0.4) + (frequencyScore * 0.4) + (confidenceScore * 0.2)
        
        return priority
    }
    
    /// Perform aggressive consolidation when resources are constrained
    private func performAggressiveConsolidation() async {
        // Reduce working memory to minimum
        let minSize = maxWorkingMemorySize / 2
        
        if workingMemory.count > minSize {
            let scoredEntries = workingMemory.map { entry -> (entry: VectorEntry, priority: Double) in
                let priority = calculatePriority(for: entry)
                return (entry, priority)
            }
            
            let sorted = scoredEntries.sorted { $0.priority < $1.priority }
            let moveCount = workingMemory.count - minSize
            let toMove = sorted.prefix(moveCount)
            
            for (entry, _) in toMove {
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
            
            workingMemory.removeAll { entry in
                toMove.contains { $0.entry.id == entry.id }
            }
        }
        
        // Also consolidate episodic to semantic more aggressively
        await consolidateEpisodicMemory()
    }

    /// Promote frequently accessed episodic memories to semantic with ML prediction
    func consolidateEpisodicMemory() async {
        // Cluster episodic events before consolidation
        let clusters = deduplicationEngine.clusterSimilarMemories(
            episodicMemory,
            threshold: 0.85
        )
        
        // Process each cluster
        for cluster in clusters {
            guard !cluster.isEmpty else { continue }
            
            // Use ML predictor to determine if cluster should be consolidated
            let predictions = consolidationPredictor.predictBatch(
                cluster,
                threshold: 0.7
            )
            
            // Get entries that should be consolidated
            let toConsolidate = predictions.filter { $0.shouldConsolidate }.map { $0.entry }
            
            if toConsolidate.isEmpty {
                continue
            }
            
            // Create representative entry from cluster
            let representative = deduplicationEngine.createRepresentative(from: toConsolidate)
            
            // Check if similar concept already exists in semantic memory
            if let similar = try? await findSimilar(
                to: representative.embedding,
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
                    accessCount: similar.accessCount + representative.accessCount,
                    lastAccessed: Date()
                )
                updateEntry(updated)
            } else {
                // Create new semantic memory
                var semanticEntry = representative
                semanticEntry = VectorEntry(
                    id: representative.id,
                    embedding: representative.embedding,
                    metadata: representative.metadata,
                    memoryLayer: .semantic,
                    accessCount: representative.accessCount,
                    lastAccessed: representative.lastAccessed
                )
                semanticMemory.append(semanticEntry)
                routingMetrics.episodicToSemanticTransitions += 1
            }
            
            // Train predictor with consolidation outcomes
            for entry in toConsolidate {
                consolidationPredictor.train(entry: entry, shouldConsolidate: true)
            }
            
            // Remove consolidated entries from episodic memory
            episodicMemory.removeAll { entry in
                toConsolidate.contains { $0.id == entry.id }
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

    /// Search across all memory layers with flexible routing
    func search(embedding: [Float], topK: Int = 5) async throws -> [VectorEntry] {
        let startTime = Date()
        var results: [VectorEntry] = []
        
        // Intelligently determine search strategy based on resource availability
        let resourceLevel = resourceMonitor.getMemoryLevel()
        let searchDepth: SearchDepth = determineSearchDepth(resourceLevel: resourceLevel)

        // Search working memory first (most relevant)
        let workingResults = workingMemory
            .map { entry in (entry, entry.similarity(to: embedding)) }
            .sorted { $0.1 > $1.1 }
            .prefix(searchDepth.workingK)
            .map { $0.0 }
        results.append(contentsOf: workingResults)

        // Search episodic memory
        let episodicResults = episodicMemory
            .map { entry in (entry, entry.similarity(to: embedding)) }
            .sorted { $0.1 > $1.1 }
            .prefix(searchDepth.episodicK)
            .map { $0.0 }
        results.append(contentsOf: episodicResults)

        // Search semantic memory
        let semanticResults = semanticMemory
            .map { entry in (entry, entry.similarity(to: embedding)) }
            .sorted { $0.1 > $1.1 }
            .prefix(searchDepth.semanticK)
            .map { $0.0 }
        results.append(contentsOf: semanticResults)

        // Apply relevance weighting based on memory layer
        let weightedResults = results.map { entry -> (entry: VectorEntry, score: Float) in
            let similarity = entry.similarity(to: embedding)
            let layerWeight = getLayerWeight(for: entry.memoryLayer)
            let recencyBoost = getRecencyBoost(for: entry)
            let weightedScore = similarity * layerWeight + recencyBoost
            return (entry, weightedScore)
        }
        
        // Sort all results by weighted score and return top K
        let allResults = weightedResults
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0.entry }

        // Update access counts and usage metrics
        for entry in allResults {
            incrementAccessCount(for: entry.id)
        }
        
        // Update routing metrics
        let searchLatency = Date().timeIntervalSince(startTime)
        routingMetrics.totalSearches += 1
        routingMetrics.averageSearchLatency = (
            routingMetrics.averageSearchLatency * Double(routingMetrics.totalSearches - 1) +
            searchLatency
        ) / Double(routingMetrics.totalSearches)

        return Array(allResults)
    }
    
    struct SearchDepth {
        let workingK: Int
        let episodicK: Int
        let semanticK: Int
    }
    
    private func determineSearchDepth(resourceLevel: ResourceMonitor.ResourceLevel) -> SearchDepth {
        switch resourceLevel {
        case .abundant:
            return SearchDepth(workingK: 10, episodicK: 10, semanticK: 10)
        case .normal:
            return SearchDepth(workingK: 7, episodicK: 7, semanticK: 7)
        case .constrained:
            return SearchDepth(workingK: 5, episodicK: 5, semanticK: 3)
        case .critical:
            return SearchDepth(workingK: 3, episodicK: 2, semanticK: 1)
        }
    }
    
    private func getLayerWeight(for layer: MemoryLayerType) -> Float {
        switch layer {
        case .working:
            return 1.2  // Boost working memory (most recent)
        case .episodic:
            return 1.0  // Normal weight
        case .semantic:
            return 0.9  // Slightly lower (more general)
        }
    }
    
    private func getRecencyBoost(for entry: VectorEntry) -> Float {
        let hoursSinceAccess = Date().timeIntervalSince(entry.lastAccessed) / 3600.0
        
        // Exponential decay: boost recent accesses
        let boost = Float(exp(-hoursSinceAccess / 24.0)) * 0.1
        return boost
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
    
    // MARK: - Metrics & Monitoring
    
    /// Get current routing metrics
    func getRoutingMetrics() -> RoutingMetrics {
        return routingMetrics
    }
    
    /// Get current memory statistics
    func getMemoryStatistics() -> MemoryStatistics {
        return MemoryStatistics(
            workingMemoryCount: workingMemory.count,
            workingMemoryCapacity: maxWorkingMemorySize,
            episodicMemoryCount: episodicMemory.count,
            semanticMemoryCount: semanticMemory.count,
            totalMemoryCount: workingMemory.count + episodicMemory.count + semanticMemory.count,
            averageAccessCount: calculateAverageAccessCount(),
            resourceLevel: resourceMonitor.getMemoryLevel()
        )
    }
    
    struct MemoryStatistics {
        let workingMemoryCount: Int
        let workingMemoryCapacity: Int
        let episodicMemoryCount: Int
        let semanticMemoryCount: Int
        let totalMemoryCount: Int
        let averageAccessCount: Double
        let resourceLevel: ResourceMonitor.ResourceLevel
    }
    
    private func calculateAverageAccessCount() -> Double {
        let allEntries = workingMemory + episodicMemory + semanticMemory
        guard !allEntries.isEmpty else { return 0.0 }
        
        let totalAccess = allEntries.reduce(0) { $0 + $1.accessCount }
        return Double(totalAccess) / Double(allEntries.count)
    }
    
    /// Trigger periodic maintenance tasks
    func performPeriodicMaintenance() async {
        // Adjust memory limits based on current resources
        await startAdaptiveResourceManagement()
        
        // Consolidate episodic memories if needed
        if episodicMemory.count > 500 {
            await consolidateEpisodicMemory()
        }
        
        // Clean up old episodic memories
        cleanupEpisodicMemory()
    }
}
