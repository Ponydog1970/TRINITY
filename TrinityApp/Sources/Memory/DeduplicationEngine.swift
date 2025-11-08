//
//  DeduplicationEngine.swift
//  TRINITY Vision Aid
//
//  Handles deduplication of observations and memory consolidation
//

import Foundation

/// Engine for detecting and merging duplicate memories
class DeduplicationEngine {
    private let similarityThreshold: Float

    init(similarityThreshold: Float = 0.95) {
        self.similarityThreshold = similarityThreshold
    }

    /// Find a duplicate entry in the given memory array
    func findDuplicate(
        _ entry: VectorEntry,
        in memory: [VectorEntry]
    ) async throws -> VectorEntry? {
        for existingEntry in memory {
            let similarity = entry.similarity(to: existingEntry.embedding)

            if similarity >= similarityThreshold {
                // Additional checks for true duplicates
                if isSpatiallyClose(entry, to: existingEntry) &&
                   isTemporallyClose(entry, to: existingEntry) {
                    return existingEntry
                }
            }
        }
        return nil
    }

    /// Merge two memory entries (existing and new observation)
    func merge(existing: VectorEntry, new: VectorEntry) -> VectorEntry {
        // Update confidence (weighted average)
        let totalCount = Float(existing.accessCount + 1)
        let existingWeight = Float(existing.accessCount) / totalCount
        let newWeight = 1.0 / totalCount

        let mergedConfidence = (
            existing.metadata.confidence * existingWeight +
            new.metadata.confidence * newWeight
        )

        // Merge embeddings (weighted average)
        let mergedEmbedding = zip(existing.embedding, new.embedding).map { e, n in
            e * existingWeight + n * newWeight
        }

        // Merge tags (union)
        let mergedTags = Array(Set(existing.metadata.tags + new.metadata.tags))

        // Create merged metadata
        let mergedMetadata = MemoryMetadata(
            id: existing.metadata.id,
            objectType: existing.metadata.objectType,
            description: existing.metadata.description,
            confidence: mergedConfidence,
            tags: mergedTags,
            spatialData: new.metadata.spatialData ?? existing.metadata.spatialData,
            timestamp: existing.metadata.timestamp,
            location: existing.metadata.location
        )

        return VectorEntry(
            id: existing.id,
            embedding: mergedEmbedding,
            metadata: mergedMetadata,
            memoryLayer: existing.memoryLayer,
            accessCount: existing.accessCount + 1,
            lastAccessed: Date()
        )
    }

    /// Check if two entries are spatially close
    private func isSpatiallyClose(_ a: VectorEntry, to b: VectorEntry) -> Bool {
        guard let spatialA = a.metadata.spatialData,
              let spatialB = b.metadata.spatialData else {
            return false
        }

        // Calculate 3D distance between centroids
        let dx = spatialA.boundingBox.x - spatialB.boundingBox.x
        let dy = spatialA.boundingBox.y - spatialB.boundingBox.y
        let dz = spatialA.boundingBox.z - spatialB.boundingBox.z

        let distance = sqrt(dx*dx + dy*dy + dz*dz)

        // Consider close if within 0.5 meters
        return distance < 0.5
    }

    /// Check if two entries are temporally close
    private func isTemporallyClose(_ a: VectorEntry, to b: VectorEntry) -> Bool {
        let timeInterval = abs(
            a.metadata.timestamp.timeIntervalSince(b.metadata.timestamp)
        )

        // Consider close if within 60 seconds
        return timeInterval < 60
    }

    /// Calculate spatial similarity between bounding boxes
    private func boundingBoxSimilarity(
        _ a: BoundingBox,
        _ b: BoundingBox
    ) -> Float {
        // Calculate IoU (Intersection over Union)
        let intersectionVolume = calculateIntersectionVolume(a, b)
        let unionVolume = volumeOf(a) + volumeOf(b) - intersectionVolume

        guard unionVolume > 0 else { return 0.0 }
        return intersectionVolume / unionVolume
    }

    private func calculateIntersectionVolume(
        _ a: BoundingBox,
        _ b: BoundingBox
    ) -> Float {
        let xOverlap = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
        let yOverlap = max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
        let zOverlap = max(0, min(a.z + a.depth, b.z + b.depth) - max(a.z, b.z))

        return xOverlap * yOverlap * zOverlap
    }

    private func volumeOf(_ box: BoundingBox) -> Float {
        return box.width * box.height * box.depth
    }

    /// Cluster similar memories for consolidation
    func clusterSimilarMemories(
        _ memories: [VectorEntry],
        threshold: Float = 0.85
    ) -> [[VectorEntry]] {
        var clusters: [[VectorEntry]] = []
        var processed: Set<UUID> = []

        for entry in memories {
            if processed.contains(entry.id) {
                continue
            }

            var cluster = [entry]
            processed.insert(entry.id)

            // Find all similar entries
            for other in memories {
                if processed.contains(other.id) {
                    continue
                }

                let similarity = entry.similarity(to: other.embedding)
                if similarity >= threshold {
                    cluster.append(other)
                    processed.insert(other.id)
                }
            }

            clusters.append(cluster)
        }

        return clusters
    }

    /// Create a representative entry from a cluster
    func createRepresentative(from cluster: [VectorEntry]) -> VectorEntry {
        guard !cluster.isEmpty else {
            fatalError("Cannot create representative from empty cluster")
        }

        if cluster.count == 1 {
            return cluster[0]
        }

        // Average embeddings
        let embeddingDim = cluster[0].embedding.count
        var avgEmbedding = [Float](repeating: 0.0, count: embeddingDim)

        for entry in cluster {
            for (i, value) in entry.embedding.enumerated() {
                avgEmbedding[i] += value / Float(cluster.count)
            }
        }

        // Normalize embedding
        let magnitude = sqrt(avgEmbedding.map { $0 * $0 }.reduce(0, +))
        if magnitude > 0 {
            avgEmbedding = avgEmbedding.map { $0 / magnitude }
        }

        // Use metadata from most confident entry
        let mostConfident = cluster.max { a, b in
            a.metadata.confidence < b.metadata.confidence
        }!

        // Merge all tags
        let allTags = cluster.flatMap { $0.metadata.tags }
        let uniqueTags = Array(Set(allTags))

        // Sum access counts
        let totalAccessCount = cluster.reduce(0) { $0 + $1.accessCount }

        let mergedMetadata = MemoryMetadata(
            id: mostConfident.metadata.id,
            objectType: mostConfident.metadata.objectType,
            description: mostConfident.metadata.description,
            confidence: mostConfident.metadata.confidence,
            tags: uniqueTags,
            spatialData: mostConfident.metadata.spatialData,
            timestamp: mostConfident.metadata.timestamp,
            location: mostConfident.metadata.location
        )

        return VectorEntry(
            id: mostConfident.id,
            embedding: avgEmbedding,
            metadata: mergedMetadata,
            memoryLayer: mostConfident.memoryLayer,
            accessCount: totalAccessCount,
            lastAccessed: Date()
        )
    }
}
