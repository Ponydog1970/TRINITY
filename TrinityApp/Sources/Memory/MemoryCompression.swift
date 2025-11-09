//
//  MemoryCompression.swift
//  TRINITY Vision Aid
//
//  Memory compression for efficient long-term storage
//

import Foundation

/// Compression strategies for semantic memory
enum CompressionStrategy {
    case cluster      // Cluster similar memories
    case prune        // Remove low-value memories
    case archive      // Move old memories to compressed archive
    case quantize     // Reduce embedding precision
}

/// Memory compression engine
class MemoryCompressionEngine {
    private let config: TrinityConfiguration

    init(config: TrinityConfiguration = .default) {
        self.config = config
    }

    // MARK: - Compression Methods

    /// Compress semantic memory when it exceeds threshold
    func compressIfNeeded(
        _ memories: [VectorEntry]
    ) async throws -> [VectorEntry] {
        guard memories.count > config.memory.maxSemanticMemorySize else {
            return memories
        }

        print("🗜️ Compressing semantic memory (\(memories.count) entries)...")

        var compressed = memories

        // Strategy 1: Cluster similar memories
        compressed = try await clusterAndMerge(compressed)

        // Strategy 2: Prune low-value entries
        if compressed.count > config.memory.maxSemanticMemorySize {
            compressed = pruneLowValueEntries(compressed)
        }

        // Strategy 3: Archive old entries
        if compressed.count > config.memory.maxSemanticMemorySize {
            compressed = try await archiveOldEntries(compressed)
        }

        print("✅ Compression complete: \(memories.count) → \(compressed.count) entries")

        return compressed
    }

    // MARK: - Clustering

    private func clusterAndMerge(
        _ memories: [VectorEntry]
    ) async throws -> [VectorEntry] {
        let deduplicationEngine = DeduplicationEngine(
            similarityThreshold: 0.85 // Lower threshold for clustering
        )

        // Cluster similar memories
        let clusters = deduplicationEngine.clusterSimilarMemories(
            memories,
            threshold: 0.85
        )

        // Create representative for each cluster
        var compressed: [VectorEntry] = []
        for cluster in clusters {
            let representative = deduplicationEngine.createRepresentative(from: cluster)
            compressed.append(representative)
        }

        return compressed
    }

    // MARK: - Pruning

    private func pruneLowValueEntries(
        _ memories: [VectorEntry]
    ) -> [VectorEntry] {
        // Calculate value score for each memory
        let scoredMemories = memories.map { entry -> (entry: VectorEntry, score: Double) in
            let score = calculateValueScore(entry)
            return (entry, score)
        }

        // Sort by score
        let sorted = scoredMemories.sorted { $0.score > $1.score }

        // Keep top entries up to max size
        let targetSize = Int(Double(config.memory.maxSemanticMemorySize) * 0.8) // Keep 80%
        let pruned = sorted.prefix(targetSize).map { $0.entry }

        print("✂️ Pruned \(memories.count - pruned.count) low-value entries")

        return pruned
    }

    /// Calculate value score for a memory entry
    private func calculateValueScore(_ entry: VectorEntry) -> Double {
        var score = 0.0

        // Factor 1: Access frequency (40%)
        score += Double(entry.accessCount) * 0.4

        // Factor 2: Confidence (30%)
        score += Double(entry.metadata.confidence) * 30.0

        // Factor 3: Recency (20%)
        let ageInDays = -entry.metadata.timestamp.timeIntervalSinceNow / (24 * 3600)
        let recencyScore = max(0, 20 - ageInDays) // Newer is better
        score += recencyScore * 0.2

        // Factor 4: Tag richness (10%)
        score += Double(entry.metadata.tags.count) * 1.0

        return score
    }

    // MARK: - Archiving

    private func archiveOldEntries(
        _ memories: [VectorEntry]
    ) async throws -> [VectorEntry] {
        let archiveThreshold = Date().addingTimeInterval(-365 * 24 * 60 * 60) // 1 year

        // Separate into active and archivable
        var active: [VectorEntry] = []
        var toArchive: [VectorEntry] = []

        for entry in memories {
            if entry.metadata.timestamp < archiveThreshold &&
               entry.accessCount < 5 { // Rarely accessed
                toArchive.append(entry)
            } else {
                active.append(entry)
            }
        }

        // Archive old entries
        if !toArchive.isEmpty {
            try await saveToArchive(toArchive)
            print("📦 Archived \(toArchive.count) old entries")
        }

        return active
    }

    private func saveToArchive(_ entries: [VectorEntry]) async throws {
        let archiveURL = getArchiveURL()

        // Load existing archive
        var archived: [VectorEntry] = []
        if FileManager.default.fileExists(atPath: archiveURL.path) {
            let data = try Data(contentsOf: archiveURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            archived = try decoder.decode([VectorEntry].self, from: data)
        }

        // Append new entries
        archived.append(contentsOf: entries)

        // Save
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archived)
        try data.write(to: archiveURL, options: .atomic)
    }

    private func getArchiveURL() -> URL {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsPath
            .appendingPathComponent("TrinityVectorDB")
            .appendingPathComponent("archive.json")
    }

    // MARK: - Quantization

    /// Reduce embedding precision to save space
    func quantizeEmbedding(
        _ embedding: [Float],
        bits: Int = 8
    ) -> [UInt8] {
        let maxValue = Float((1 << bits) - 1)

        return embedding.map { value in
            // Map from [-1, 1] to [0, maxValue]
            let normalized = (value + 1.0) / 2.0
            let quantized = min(max(normalized * maxValue, 0), maxValue)
            return UInt8(quantized)
        }
    }

    /// Dequantize embedding back to Float
    func dequantizeEmbedding(
        _ quantized: [UInt8],
        bits: Int = 8
    ) -> [Float] {
        let maxValue = Float((1 << bits) - 1)

        return quantized.map { value in
            // Map from [0, maxValue] to [-1, 1]
            let normalized = Float(value) / maxValue
            return (normalized * 2.0) - 1.0
        }
    }

    // MARK: - Statistics

    func getCompressionStats(
        original: [VectorEntry],
        compressed: [VectorEntry]
    ) -> CompressionStats {
        let originalSize = estimateSize(original)
        let compressedSize = estimateSize(compressed)
        let ratio = Double(originalSize) / Double(compressedSize)

        return CompressionStats(
            originalCount: original.count,
            compressedCount: compressed.count,
            originalSize: originalSize,
            compressedSize: compressedSize,
            compressionRatio: ratio,
            spaceSaved: originalSize - compressedSize
        )
    }

    private func estimateSize(_ entries: [VectorEntry]) -> Int {
        // Rough estimate: embedding (512 * 4 bytes) + metadata (~500 bytes)
        return entries.count * (512 * 4 + 500)
    }
}

// MARK: - Supporting Types

struct CompressionStats {
    let originalCount: Int
    let compressedCount: Int
    let originalSize: Int      // bytes
    let compressedSize: Int    // bytes
    let compressionRatio: Double
    let spaceSaved: Int        // bytes

    var humanReadableSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(compressedSize), countStyle: .file)
    }

    var humanReadableSaved: String {
        ByteCountFormatter.string(fromByteCount: Int64(spaceSaved), countStyle: .file)
    }
}

// MARK: - Background Compression Task

/// Background task for automatic memory compression
@MainActor
class MemoryCompressionTask {
    private var timer: Timer?
    private let compressionEngine: MemoryCompressionEngine
    private let memoryManager: MemoryManager

    init(
        memoryManager: MemoryManager,
        config: TrinityConfiguration = .default
    ) {
        self.memoryManager = memoryManager
        self.compressionEngine = MemoryCompressionEngine(config: config)
    }

    func start(interval: TimeInterval = 3600) { // Default: 1 hour
        stop() // Stop any existing timer

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performCompression()
            }
        }

        print("🔄 Memory compression task started (interval: \(interval)s)")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func performCompression() async {
        do {
            let semanticMemory = memoryManager.semanticMemory

            guard !semanticMemory.isEmpty else { return }

            let compressed = try await compressionEngine.compressIfNeeded(semanticMemory)

            let stats = compressionEngine.getCompressionStats(
                original: semanticMemory,
                compressed: compressed
            )

            if stats.originalCount != stats.compressedCount {
                print("📊 Compression stats:")
                print("   Entries: \(stats.originalCount) → \(stats.compressedCount)")
                print("   Size: \(stats.humanReadableSize)")
                print("   Saved: \(stats.humanReadableSaved)")
                print("   Ratio: \(String(format: "%.2f", stats.compressionRatio))x")

                // Update memory manager (this would need to be added to MemoryManager)
                // memoryManager.semanticMemory = compressed
            }

        } catch {
            print("❌ Compression failed: \(error.localizedDescription)")
        }
    }
}
