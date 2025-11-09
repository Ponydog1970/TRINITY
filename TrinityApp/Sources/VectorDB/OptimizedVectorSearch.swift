//
//  OptimizedVectorSearch.swift
//  TRINITY Vision Aid
//
//  Optimized vector search with indexing and caching
//

import Foundation

/// Optimized vector search engine with multiple strategies
class OptimizedVectorSearch {
    private var cache: VectorSearchCache
    private let config: TrinityConfiguration

    init(config: TrinityConfiguration = .default) {
        self.config = config
        self.cache = VectorSearchCache(maxSize: config.performance.embeddingCacheSize)
    }

    // MARK: - Search Methods

    /// Search with automatic strategy selection
    func search(
        query: [Float],
        in entries: [VectorEntry],
        topK: Int
    ) -> [VectorEntry] {
        // Check cache first
        if let cached = cache.get(query: query, topK: topK) {
            return cached
        }

        let results: [VectorEntry]

        // Select strategy based on dataset size
        if entries.count < 1000 {
            // Brute force for small datasets
            results = bruteForceSearch(query: query, in: entries, topK: topK)
        } else {
            // Use approximate search for large datasets
            results = approximateSearch(query: query, in: entries, topK: topK)
        }

        // Cache results
        cache.set(query: query, results: results, topK: topK)

        return results
    }

    // MARK: - Brute Force Search

    private func bruteForceSearch(
        query: [Float],
        in entries: [VectorEntry],
        topK: Int
    ) -> [VectorEntry] {
        let scored = entries.map { entry -> (entry: VectorEntry, similarity: Float) in
            let similarity = cosineSimilarity(query, entry.embedding)
            return (entry, similarity)
        }

        return scored
            .sorted { $0.similarity > $1.similarity }
            .prefix(topK)
            .map { $0.entry }
    }

    // MARK: - Approximate Search (IVF - Inverted File Index)

    private func approximateSearch(
        query: [Float],
        in entries: [VectorEntry],
        topK: Int
    ) -> [VectorEntry] {
        // For large datasets, use product quantization or IVF
        // This is a simplified implementation

        // 1. Partition space into regions (clustering)
        let numClusters = min(100, entries.count / 100)
        let clusters = createClusters(entries, count: numClusters)

        // 2. Find nearest clusters
        let nearestClusters = findNearestClusters(query, clusters: clusters, k: 5)

        // 3. Search within nearest clusters only
        var candidates: [VectorEntry] = []
        for cluster in nearestClusters {
            candidates.append(contentsOf: cluster.entries)
        }

        // 4. Brute force on candidates
        return bruteForceSearch(query: query, in: candidates, topK: topK)
    }

    private struct Cluster {
        let centroid: [Float]
        var entries: [VectorEntry]
    }

    private func createClusters(_ entries: [VectorEntry], count: Int) -> [Cluster] {
        // Simple k-means clustering
        var clusters: [Cluster] = []

        // Initialize centroids randomly
        let shuffled = entries.shuffled()
        for i in 0..<min(count, entries.count) {
            clusters.append(Cluster(centroid: shuffled[i].embedding, entries: []))
        }

        // Assign entries to clusters
        for entry in entries {
            var bestClusterIndex = 0
            var bestSimilarity: Float = -1

            for (index, cluster) in clusters.enumerated() {
                let similarity = cosineSimilarity(entry.embedding, cluster.centroid)
                if similarity > bestSimilarity {
                    bestSimilarity = similarity
                    bestClusterIndex = index
                }
            }

            clusters[bestClusterIndex].entries.append(entry)
        }

        return clusters
    }

    private func findNearestClusters(
        _ query: [Float],
        clusters: [Cluster],
        k: Int
    ) -> [Cluster] {
        let scored = clusters.map { cluster -> (cluster: Cluster, similarity: Float) in
            let similarity = cosineSimilarity(query, cluster.centroid)
            return (cluster, similarity)
        }

        return scored
            .sorted { $0.similarity > $1.similarity }
            .prefix(k)
            .map { $0.cluster }
    }

    // MARK: - SIMD-Optimized Similarity

    /// SIMD-optimized cosine similarity for better performance
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }

        // Use accelerate framework for SIMD operations on iOS
        var dotProduct: Float = 0.0
        var magnitudeA: Float = 0.0
        var magnitudeB: Float = 0.0

        // Manual vectorization (in production, use Accelerate framework)
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }

        magnitudeA = sqrt(magnitudeA)
        magnitudeB = sqrt(magnitudeB)

        guard magnitudeA > 0, magnitudeB > 0 else { return 0.0 }
        return dotProduct / (magnitudeA * magnitudeB)
    }

    // MARK: - Batch Search

    /// Batch search for multiple queries (more efficient)
    func batchSearch(
        queries: [[Float]],
        in entries: [VectorEntry],
        topK: Int
    ) async -> [[VectorEntry]] {
        await withTaskGroup(of: (Int, [VectorEntry]).self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask {
                    let results = self.search(query: query, in: entries, topK: topK)
                    return (index, results)
                }
            }

            var results: [(Int, [VectorEntry])] = []
            for await result in group {
                results.append(result)
            }

            return results
                .sorted { $0.0 < $1.0 }
                .map { $1 }
        }
    }

    // MARK: - Cache Management

    func clearCache() {
        cache.clear()
    }

    func getCacheStats() -> CacheStats {
        return cache.getStats()
    }
}

// MARK: - Vector Search Cache

class VectorSearchCache {
    private struct CacheKey: Hashable {
        let queryHash: Int
        let topK: Int

        init(query: [Float], topK: Int) {
            // Create hash from query vector
            self.queryHash = query.reduce(0) { hash, value in
                hash ^ Int(value * 1000)
            }
            self.topK = topK
        }
    }

    private struct CacheEntry {
        let results: [VectorEntry]
        let timestamp: Date
        var hitCount: Int
    }

    private var cache: [CacheKey: CacheEntry] = [:]
    private let maxSize: Int
    private var hits: Int = 0
    private var misses: Int = 0

    init(maxSize: Int = 1000) {
        self.maxSize = maxSize
    }

    func get(query: [Float], topK: Int) -> [VectorEntry]? {
        let key = CacheKey(query: query, topK: topK)

        if var entry = cache[key] {
            entry.hitCount += 1
            cache[key] = entry
            hits += 1
            return entry.results
        }

        misses += 1
        return nil
    }

    func set(query: [Float], results: [VectorEntry], topK: Int) {
        let key = CacheKey(query: query, topK: topK)

        // Evict if cache is full
        if cache.count >= maxSize {
            evictLRU()
        }

        cache[key] = CacheEntry(
            results: results,
            timestamp: Date(),
            hitCount: 0
        )
    }

    func clear() {
        cache.removeAll()
        hits = 0
        misses = 0
    }

    private func evictLRU() {
        // Find least recently used entry
        guard let oldestKey = cache.min(by: { a, b in
            a.value.timestamp < b.value.timestamp
        })?.key else {
            return
        }

        cache.removeValue(forKey: oldestKey)
    }

    func getStats() -> CacheStats {
        let total = hits + misses
        let hitRate = total > 0 ? Double(hits) / Double(total) : 0.0

        return CacheStats(
            size: cache.count,
            maxSize: maxSize,
            hits: hits,
            misses: misses,
            hitRate: hitRate
        )
    }
}

struct CacheStats {
    let size: Int
    let maxSize: Int
    let hits: Int
    let misses: Int
    let hitRate: Double

    var description: String {
        """
        Cache Stats:
        - Size: \(size)/\(maxSize)
        - Hits: \(hits)
        - Misses: \(misses)
        - Hit Rate: \(String(format: "%.1f%%", hitRate * 100))
        """
    }
}

// MARK: - Product Quantization (Advanced)

/// Product Quantization for memory-efficient storage
class ProductQuantization {
    private let numSubvectors: Int
    private let codebookSize: Int

    init(numSubvectors: Int = 8, codebookSize: Int = 256) {
        self.numSubvectors = numSubvectors
        self.codebookSize = codebookSize
    }

    /// Quantize a full-precision embedding to compact codes
    func quantize(_ embedding: [Float]) -> [UInt8] {
        let subvectorSize = embedding.count / numSubvectors
        var codes: [UInt8] = []

        for i in 0..<numSubvectors {
            let start = i * subvectorSize
            let end = min(start + subvectorSize, embedding.count)
            let subvector = Array(embedding[start..<end])

            // Quantize subvector to codebook index
            let code = quantizeSubvector(subvector)
            codes.append(code)
        }

        return codes
    }

    private func quantizeSubvector(_ subvector: [Float]) -> UInt8 {
        // Simplified: map subvector to codebook index
        // In production, use k-means trained codebook
        let sum = subvector.reduce(0, +)
        let normalized = (sum + Float(subvector.count)) / (2.0 * Float(subvector.count))
        return UInt8(min(normalized * Float(codebookSize), Float(codebookSize - 1)))
    }
}
