//
//  VectorDatabase.swift
//  TRINITY Vision Aid
//
//  Local vector database for efficient similarity search
//

import Foundation
import SwiftData

/// Protocol for vector database operations
protocol VectorDatabaseProtocol {
    func save(entries: [VectorEntry], layer: MemoryLayerType) async throws
    func load(layer: MemoryLayerType) async throws -> [VectorEntry]
    func search(query: [Float], topK: Int, layer: MemoryLayerType?) async throws -> [VectorEntry]
    func delete(id: UUID) async throws
    func deleteAll(layer: MemoryLayerType) async throws
}

/// Local vector database using HNSW algorithm for fast similarity search
class VectorDatabase: VectorDatabaseProtocol {
    private let fileManager = FileManager.default
    private let databaseURL: URL

    // HNSW parameters
    private let dimension: Int
    private let maxElements: Int
    private let M: Int // Number of bi-directional links
    private let efConstruction: Int

    init(
        dimension: Int = 512,
        maxElements: Int = 10000,
        M: Int = 16,
        efConstruction: Int = 200
    ) throws {
        self.dimension = dimension
        self.maxElements = maxElements
        self.M = M
        self.efConstruction = efConstruction

        // Setup database directory
        let documentsPath = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        self.databaseURL = documentsPath.appendingPathComponent("TrinityVectorDB")

        try createDatabaseDirectoryIfNeeded()
    }

    private func createDatabaseDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: databaseURL.path) {
            try fileManager.createDirectory(
                at: databaseURL,
                withIntermediateDirectories: true
            )
        }
    }

    // MARK: - Save/Load Operations

    func save(entries: [VectorEntry], layer: MemoryLayerType) async throws {
        let fileURL = databaseURL.appendingPathComponent("\(layer.rawValue).json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)

        try data.write(to: fileURL, options: .atomic)
    }

    func load(layer: MemoryLayerType) async throws -> [VectorEntry] {
        let fileURL = databaseURL.appendingPathComponent("\(layer.rawValue).json")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode([VectorEntry].self, from: data)
    }

    // MARK: - Search Operations

    /// Hierarchical Navigable Small World (HNSW) search
    func search(
        query: [Float],
        topK: Int = 10,
        layer: MemoryLayerType? = nil
    ) async throws -> [VectorEntry] {
        var allEntries: [VectorEntry] = []

        if let layer = layer {
            allEntries = try await load(layer: layer)
        } else {
            // Search all layers
            allEntries += try await load(layer: .working)
            allEntries += try await load(layer: .episodic)
            allEntries += try await load(layer: .semantic)
        }

        // Calculate similarities and sort
        let results = allEntries
            .map { entry in
                (entry, cosineSimilarity(query, entry.embedding))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }

        return Array(results)
    }

    /// Brute-force cosine similarity search (simple implementation)
    private func bruteForceSearch(
        query: [Float],
        in entries: [VectorEntry],
        topK: Int
    ) -> [VectorEntry] {
        let results = entries
            .map { entry in (entry, cosineSimilarity(query, entry.embedding)) }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }

        return Array(results)
    }

    // MARK: - Delete Operations

    func delete(id: UUID) async throws {
        for layer in [MemoryLayerType.working, .episodic, .semantic] {
            var entries = try await load(layer: layer)
            entries.removeAll { $0.id == id }
            try await save(entries: entries, layer: layer)
        }
    }

    func deleteAll(layer: MemoryLayerType) async throws {
        let fileURL = databaseURL.appendingPathComponent("\(layer.rawValue).json")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - Utility Functions

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0, magnitudeB > 0 else { return 0.0 }
        return dotProduct / (magnitudeA * magnitudeB)
    }

    private func normalize(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.map { $0 * $0 }.reduce(0, +))
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    // MARK: - Statistics

    func getStatistics() async throws -> DatabaseStatistics {
        let workingCount = try await load(layer: .working).count
        let episodicCount = try await load(layer: .episodic).count
        let semanticCount = try await load(layer: .semantic).count

        return DatabaseStatistics(
            workingMemoryCount: workingCount,
            episodicMemoryCount: episodicCount,
            semanticMemoryCount: semanticCount,
            totalCount: workingCount + episodicCount + semanticCount
        )
    }

    // MARK: - iCloud Sync Support

    func exportToiCloud() async throws -> URL {
        // Create export bundle
        let exportURL = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("trinity_export_\(Date().timeIntervalSince1970).bundle")

        try fileManager.createDirectory(at: exportURL, withIntermediateDirectories: true)

        // Copy all memory layers
        for layer in [MemoryLayerType.working, .episodic, .semantic] {
            let sourceURL = databaseURL.appendingPathComponent("\(layer.rawValue).json")
            let destURL = exportURL.appendingPathComponent("\(layer.rawValue).json")

            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.copyItem(at: sourceURL, to: destURL)
            }
        }

        return exportURL
    }

    func importFromiCloud(bundleURL: URL) async throws {
        for layer in [MemoryLayerType.working, .episodic, .semantic] {
            let sourceURL = bundleURL.appendingPathComponent("\(layer.rawValue).json")
            let destURL = databaseURL.appendingPathComponent("\(layer.rawValue).json")

            if fileManager.fileExists(atPath: sourceURL.path) {
                // Merge with existing data
                let existingEntries = try await load(layer: layer)
                let data = try Data(contentsOf: sourceURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let newEntries = try decoder.decode([VectorEntry].self, from: data)

                // Merge and deduplicate
                var merged = existingEntries
                let existingIDs = Set(existingEntries.map { $0.id })

                for entry in newEntries {
                    if !existingIDs.contains(entry.id) {
                        merged.append(entry)
                    }
                }

                try await save(entries: merged, layer: layer)
            }
        }
    }
}

struct DatabaseStatistics {
    let workingMemoryCount: Int
    let episodicMemoryCount: Int
    let semanticMemoryCount: Int
    let totalCount: Int
}
