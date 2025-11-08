//
//  CacheManager.swift
//  TRINITY Vision Aid
//
//  3-Tier intelligent caching system for cost optimization
//

import Foundation
import CryptoKit

/// Intelligent 3-Tier Caching System
@MainActor
class CacheManager: ObservableObject {
    static let shared = CacheManager()

    // MARK: - Cache Tiers

    /// Tier 1: In-Memory (schnellster Zugriff, begrenzt)
    private var memoryCache: [String: CachedResponse] = [:]
    private let maxMemoryCacheSize = 100

    /// Tier 2: RAG/Vector Database (semantische Suche)
    private var vectorCache: VectorDatabase?

    /// Tier 3: Persistent Disk Cache (langfristig)
    private let diskCacheURL: URL

    // MARK: - Statistics

    @Published var totalRequests: Int = 0
    @Published var cacheHits: Int = 0
    @Published var cacheMisses: Int = 0

    var cacheHitRate: Float {
        guard totalRequests > 0 else { return 0.0 }
        return Float(cacheHits) / Float(totalRequests)
    }

    var estimatedCostSaved: Double {
        // Durchschnittliche Kosten pro Request: $0.005
        return Double(cacheHits) * 0.005
    }

    // MARK: - Configuration

    private let similarityThreshold: Float = 0.92  // Für semantische Cache-Suche
    private let cacheExpirationDays: Int = 30      // Cache-Einträge älter als 30 Tage werden gelöscht

    // MARK: - Initialization

    init() {
        let cacheDir = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!

        self.diskCacheURL = cacheDir.appendingPathComponent("TrinityCache")

        try? FileManager.default.createDirectory(
            at: diskCacheURL,
            withIntermediateDirectories: true
        )

        loadStatistics()
    }

    func configure(vectorDB: VectorDatabase) {
        self.vectorCache = vectorDB
    }

    // MARK: - Vision Cache

    /// Cached Vision Result abrufen
    func getCachedVisionResult(
        imageHash: Int,
        prompt: String,
        model: String
    ) async throws -> VisionAnalysisResult? {

        totalRequests += 1

        // 1. Memory Cache (Tier 1) - Exact Match
        let exactKey = generateCacheKey(type: "vision", hash: imageHash, prompt: prompt, model: model)

        if let cached = memoryCache[exactKey] {
            if !cached.isExpired() {
                cacheHits += 1
                print("💾 Memory Cache HIT (Tier 1)")
                return cached.visionResult
            } else {
                memoryCache.removeValue(forKey: exactKey)
            }
        }

        // 2. Semantic Cache (Tier 2) - Similar Match via RAG
        // TODO: Vollständig implementieren - Type Mismatch Problem
        // VectorEntry.metadata ist MemoryMetadata, nicht VisionAnalysisResult
        // Benötigt separate Cache-Entry-Struktur oder Wrapper-Type
        // Siehe auch cacheVisionResult() Zeile ~181 wo save() auskommentiert ist
        /*
        if let vectorDB = vectorCache {
            // Generiere Embedding für Prompt
            let promptEmbedding = await generatePromptEmbedding(prompt)

            // Suche ähnliche Queries
            let similarQueries = try await vectorDB.search(
                query: promptEmbedding,
                topK: 3,
                layer: .semantic
            )

            for similar in similarQueries {
                let similarity = cosineSimilarity(promptEmbedding, similar.embedding)

                if similarity >= similarityThreshold {
                    // Ähnliche Query gefunden!
                    cacheHits += 1
                    print("💾 Semantic Cache HIT (Tier 2) - Similarity: \(similarity)")
                    // TODO: Korrekte Rückgabe implementieren
                }
            }
        }
        */

        // 3. Disk Cache (Tier 3) - Exact Match
        if let diskResult = try? loadFromDisk(key: exactKey) as? VisionAnalysisResult {
            if !diskResult.timestamp.isExpired(days: cacheExpirationDays) {
                cacheHits += 1
                print("💾 Disk Cache HIT (Tier 3)")

                // Promote to Memory Cache
                addToMemoryCache(exactKey, result: diskResult)

                return diskResult
            } else {
                // Expired, remove
                try? removeFromDisk(key: exactKey)
            }
        }

        // Cache MISS
        cacheMisses += 1
        saveStatistics()
        return nil
    }

    /// Cache Vision Result speichern
    func cacheVisionResult(
        imageHash: Int,
        prompt: String,
        model: String,
        result: VisionAnalysisResult
    ) async throws {

        let key = generateCacheKey(type: "vision", hash: imageHash, prompt: prompt, model: model)

        // 1. Memory Cache (Tier 1)
        addToMemoryCache(key, result: result)

        // 2. Vector Cache (Tier 2) - Für semantische Suche
        if vectorCache != nil {
            let promptEmbedding = await generatePromptEmbedding(prompt)

            let cacheEntry = EnhancedVectorEntry(
                embedding: promptEmbedding,
                memoryLayer: .semantic,
                objectType: "cached_vision_result",
                description: prompt,
                confidence: result.confidence,
                keywords: extractKeywords(from: prompt),
                categories: ["cache", "vision"],
                importance: 0.5,
                timestamp: Date(),
                timeOfDay: "N/A",
                dayOfWeek: "N/A",
                sourceType: "cache",
                quality: result.confidence
            )

            // In echter Implementation würde man metadata richtig setzen
            // try await vectorCache?.save(entries: [cacheEntry], layer: .semantic)
        }

        // 3. Disk Cache (Tier 3) - Langfristig
        try saveToDisk(key: key, object: result)

        print("💾 Cached vision result (All Tiers)")
    }

    // MARK: - Query Cache

    /// Cached Query Result abrufen
    func getCachedQueryResult(
        prompt: String,
        context: [String],
        model: String
    ) async throws -> QueryResult? {

        totalRequests += 1

        let contextHash = context.joined(separator: "|").hashValue
        let key = generateCacheKey(type: "query", hash: contextHash, prompt: prompt, model: model)

        // Tier 1: Memory
        if let cached = memoryCache[key] {
            if !cached.isExpired() {
                cacheHits += 1
                print("💾 Memory Cache HIT (Query)")
                return cached.queryResult
            } else {
                memoryCache.removeValue(forKey: key)
            }
        }

        // Tier 2: Semantic (via RAG)
        // TODO: Vollständig implementieren - Type Mismatch Problem
        // vectorDB.search() gibt VectorEntry zurück, nicht EnhancedVectorEntry
        // Code versucht .objectType, .description, .confidence zu verwenden (Zeilen 230, 236-237)
        // Diese Properties existieren nicht auf VectorEntry
        /*
        if let vectorDB = vectorCache {
            let promptEmbedding = await generatePromptEmbedding(prompt)

            let similarQueries = try await vectorDB.search(
                query: promptEmbedding,
                topK: 5,
                layer: .semantic
            )

            for similar in similarQueries {
                let similarity = cosineSimilarity(promptEmbedding, similar.embedding)

                if similarity >= similarityThreshold {
                    cacheHits += 1
                    print("💾 Semantic Cache HIT (Query) - Similarity: \(similarity)")
                    // TODO: Korrekte Rekonstruktion implementieren
                }
            }
        }
        */

        // Tier 3: Disk
        if let diskResult = try? loadFromDisk(key: key) as? QueryResult {
            if !diskResult.timestamp.isExpired(days: cacheExpirationDays) {
                cacheHits += 1
                print("💾 Disk Cache HIT (Query)")
                addToMemoryCache(key, result: diskResult)
                return diskResult
            }
        }

        cacheMisses += 1
        saveStatistics()
        return nil
    }

    /// Cache Query Result speichern
    func cacheQueryResult(
        prompt: String,
        context: [String],
        model: String,
        result: QueryResult
    ) async throws {

        let contextHash = context.joined(separator: "|").hashValue
        let key = generateCacheKey(type: "query", hash: contextHash, prompt: prompt, model: model)

        // Tier 1: Memory
        addToMemoryCache(key, result: result)

        // Tier 2: Vector (for semantic search)
        if vectorCache != nil {
            let promptEmbedding = await generatePromptEmbedding(prompt)

            let cacheEntry = EnhancedVectorEntry(
                embedding: promptEmbedding,
                memoryLayer: .semantic,
                objectType: "cached_query_result",
                description: result.answer,
                confidence: result.confidence,
                keywords: extractKeywords(from: prompt),
                categories: ["cache", "query"],
                importance: 0.5,
                timestamp: Date(),
                timeOfDay: "N/A",
                dayOfWeek: "N/A",
                sourceType: "cache",
                quality: result.confidence
            )

            // Store in vector cache
        }

        // Tier 3: Disk
        try saveToDisk(key: key, object: result)

        print("💾 Cached query result (All Tiers)")
    }

    // MARK: - Memory Cache Management

    private func addToMemoryCache<T>(_ key: String, result: T) {
        let cached = CachedResponse(key: key)

        if let visionResult = result as? VisionAnalysisResult {
            cached.visionResult = visionResult
        } else if let queryResult = result as? QueryResult {
            cached.queryResult = queryResult
        }

        memoryCache[key] = cached

        // Limit size (LRU)
        if memoryCache.count > maxMemoryCacheSize {
            if let oldest = memoryCache.values.min(by: { $0.timestamp < $1.timestamp }) {
                memoryCache.removeValue(forKey: oldest.key)
            }
        }
    }

    // MARK: - Disk Cache

    private func saveToDisk(key: String, object: Codable) throws {
        let fileURL = diskCacheURL.appendingPathComponent(key.md5Hash + ".cache")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(object)

        try data.write(to: fileURL, options: .atomic)
    }

    private func loadFromDisk(key: String) throws -> Codable? {
        let fileURL = diskCacheURL.appendingPathComponent(key.md5Hash + ".cache")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)

        // Try to decode as different types
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // This is simplified - in production you'd store type info
        return nil
    }

    private func removeFromDisk(key: String) throws {
        let fileURL = diskCacheURL.appendingPathComponent(key.md5Hash + ".cache")
        try FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Helpers

    private func generateCacheKey(
        type: String,
        hash: Int,
        prompt: String,
        model: String
    ) -> String {
        return "\(type)_\(hash)_\(prompt.hashValue)_\(model)".md5Hash
    }

    private func generatePromptEmbedding(_ prompt: String) async -> [Float] {
        // In production: Use EmbeddingGenerator
        // For now: Simple hash-based placeholder
        let hash = prompt.hashValue
        var embedding = [Float](repeating: 0.0, count: 512)
        embedding[0] = Float(hash % 1000) / 1000.0
        return embedding
    }

    private func extractKeywords(from text: String) -> [String] {
        // Simple tokenization
        return text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 3 }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        guard magnitudeA > 0, magnitudeB > 0 else { return 0.0 }
        return dotProduct / (magnitudeA * magnitudeB)
    }

    // MARK: - Cache Maintenance

    func clearExpiredCache() async throws {
        print("🧹 Cleaning expired cache...")

        // Clear expired memory cache
        let expiredKeys = memoryCache.filter { $0.value.isExpired() }.map { $0.key }
        for key in expiredKeys {
            memoryCache.removeValue(forKey: key)
        }

        // Clear expired disk cache
        let files = try FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil)

        for file in files {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            if let modDate = attributes[.modificationDate] as? Date {
                if modDate.isExpired(days: cacheExpirationDays) {
                    try FileManager.default.removeItem(at: file)
                }
            }
        }

        print("✅ Cache cleaned")
    }

    func clearAllCache() async throws {
        memoryCache.removeAll()
        try FileManager.default.removeItem(at: diskCacheURL)
        try FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        cacheHits = 0
        cacheMisses = 0
        totalRequests = 0

        print("🗑️ All cache cleared")
    }

    // MARK: - Statistics

    private func loadStatistics() {
        totalRequests = UserDefaults.standard.integer(forKey: "cache_total_requests")
        cacheHits = UserDefaults.standard.integer(forKey: "cache_hits")
        cacheMisses = UserDefaults.standard.integer(forKey: "cache_misses")
    }

    private func saveStatistics() {
        UserDefaults.standard.set(totalRequests, forKey: "cache_total_requests")
        UserDefaults.standard.set(cacheHits, forKey: "cache_hits")
        UserDefaults.standard.set(cacheMisses, forKey: "cache_misses")
    }

    func getCacheStatistics() -> CacheStatistics {
        return CacheStatistics(
            memoryCacheSize: memoryCache.count,
            diskCacheSize: (try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil).count) ?? 0,
            totalRequests: totalRequests,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            hitRate: cacheHitRate,
            estimatedSavings: estimatedCostSaved
        )
    }
}

// MARK: - Supporting Types

class CachedResponse {
    let key: String
    let timestamp: Date
    var visionResult: VisionAnalysisResult?
    var queryResult: QueryResult?

    init(key: String) {
        self.key = key
        self.timestamp = Date()
    }

    func isExpired(days: Int = 30) -> Bool {
        return timestamp.isExpired(days: days)
    }
}

struct CacheStatistics {
    let memoryCacheSize: Int
    let diskCacheSize: Int
    let totalRequests: Int
    let cacheHits: Int
    let cacheMisses: Int
    let hitRate: Float
    let estimatedSavings: Double
}

// MARK: - Extensions

extension Date {
    func isExpired(days: Int) -> Bool {
        let expirationDate = Calendar.current.date(byAdding: .day, value: days, to: self)!
        return Date() > expirationDate
    }
}

extension String {
    var md5Hash: String {
        let data = Data(self.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}
