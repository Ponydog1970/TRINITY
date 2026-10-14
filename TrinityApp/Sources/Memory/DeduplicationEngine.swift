//
//  DeduplicationEngine.swift
//  TRINITY Vision Aid
//
//  Handles deduplication of observations and memory consolidation
//

import Foundation
import CoreLocation

/// Engine for detecting and merging duplicate memories
class DeduplicationEngine {
    private var baseSimilarityThreshold: Float
    
    // Dynamic threshold adjustment based on context
    private var contextualThresholds: [String: Float] = [:]
    
    init(similarityThreshold: Float = 0.95) {
        self.baseSimilarityThreshold = similarityThreshold
        initializeContextualThresholds()
    }
    
    private func initializeContextualThresholds() {
        // Different thresholds for different data types
        contextualThresholds = [
            "person": 0.98,      // Higher threshold for people (more precision)
            "object": 0.95,      // Standard for objects
            "place": 0.92,       // Lower for places (more tolerance)
            "scene": 0.90,       // Even lower for general scenes
            "text": 0.97,        // High for text (must be accurate)
            "unknown": 0.95      // Default
        ]
    }
    
    /// Dynamically adjust similarity threshold based on context
    func adjustThreshold(for objectType: String, confidence: Float) -> Float {
        // Get base threshold for object type
        let baseThreshold = contextualThresholds[objectType.lowercased()] ?? baseSimilarityThreshold
        
        // Adjust based on confidence level
        // High confidence: can use lower threshold (more tolerance)
        // Low confidence: need higher threshold (more strict)
        let confidenceAdjustment = (1.0 - confidence) * 0.05
        let adjustedThreshold = baseThreshold + confidenceAdjustment
        
        return min(adjustedThreshold, 0.99) // Cap at 0.99
    }
    
    /// Update contextual thresholds based on observed patterns
    func updateContextualThreshold(for objectType: String, newThreshold: Float) {
        contextualThresholds[objectType.lowercased()] = newThreshold
    }

    /// Find a duplicate entry in the given memory array with metadata-based checks
    func findDuplicate(
        _ entry: VectorEntry,
        in memory: [VectorEntry]
    ) async throws -> VectorEntry? {
        // Get dynamic threshold based on context
        let threshold = adjustThreshold(
            for: entry.metadata.objectType,
            confidence: entry.metadata.confidence
        )
        
        for existingEntry in memory {
            let similarity = entry.similarity(to: existingEntry.embedding)

            if similarity >= threshold {
                // Enhanced metadata-based deduplication checks
                let metadataScore = calculateMetadataSimilarity(entry, to: existingEntry)
                
                // Require both embedding similarity and metadata similarity
                if metadataScore >= 0.7 {
                    // Additional spatial and temporal checks
                    if isSpatiallyClose(entry, to: existingEntry) &&
                       isTemporallyClose(entry, to: existingEntry) {
                        return existingEntry
                    }
                }
            }
        }
        return nil
    }
    
    /// Calculate metadata similarity incorporating spatial and temporal tags
    private func calculateMetadataSimilarity(
        _ a: VectorEntry,
        to b: VectorEntry
    ) -> Float {
        var similarityScore: Float = 0.0
        var totalWeight: Float = 0.0
        
        // 1. Object type similarity (weight: 0.3)
        if a.metadata.objectType == b.metadata.objectType {
            similarityScore += 1.0 * 0.3
        }
        totalWeight += 0.3
        
        // 2. Tag overlap (weight: 0.2)
        let tagsA = Set(a.metadata.tags)
        let tagsB = Set(b.metadata.tags)
        if !tagsA.isEmpty && !tagsB.isEmpty {
            let intersection = tagsA.intersection(tagsB)
            let union = tagsA.union(tagsB)
            let tagSimilarity = Float(intersection.count) / Float(union.count)
            similarityScore += tagSimilarity * 0.2
        }
        totalWeight += 0.2
        
        // 3. Spatial similarity (weight: 0.25)
        if let spatialA = a.metadata.spatialData,
           let spatialB = b.metadata.spatialData {
            let spatialSim = boundingBoxSimilarity(
                spatialA.boundingBox,
                spatialB.boundingBox
            )
            similarityScore += spatialSim * 0.25
            totalWeight += 0.25
        }
        
        // 4. Temporal similarity (weight: 0.15)
        let temporalSim = calculateTemporalSimilarity(a.metadata.timestamp, b.metadata.timestamp)
        similarityScore += temporalSim * 0.15
        totalWeight += 0.15
        
        // 5. Location similarity if available (weight: 0.1)
        if let locA = a.metadata.location,
           let locB = b.metadata.location {
            let locationSim = calculateLocationSimilarity(locA, locB)
            similarityScore += locationSim * 0.1
            totalWeight += 0.1
        }
        
        return totalWeight > 0 ? similarityScore / totalWeight : 0.0
    }
    
    /// Calculate temporal similarity (returns 1.0 if very close, decays with time)
    private func calculateTemporalSimilarity(_ time1: Date, _ time2: Date) -> Float {
        let timeInterval = abs(time1.timeIntervalSince(time2))
        
        // Exponential decay: similar if within minutes, less similar as hours pass
        let hoursApart = timeInterval / 3600.0
        let similarity = Float(exp(-hoursApart / 24.0)) // 24-hour decay constant
        
        return similarity
    }
    
    /// Calculate location similarity based on distance
    private func calculateLocationSimilarity(
        _ loc1: CLLocationCoordinate2D,
        _ loc2: CLLocationCoordinate2D
    ) -> Float {
        // Calculate haversine distance
        let lat1 = loc1.latitude * .pi / 180
        let lat2 = loc2.latitude * .pi / 180
        let lon1 = loc1.longitude * .pi / 180
        let lon2 = loc2.longitude * .pi / 180
        
        let dLat = lat2 - lat1
        let dLon = lon2 - lon1
        
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1) * cos(lat2) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        let distance = 6371000 * c // Earth radius in meters
        
        // Similar if within 100 meters
        if distance < 10 {
            return 1.0
        } else if distance < 100 {
            return Float(1.0 - (distance - 10) / 90.0)
        } else {
            return 0.0
        }
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

    /// Check if two entries are temporally close (with adaptive threshold)
    private func isTemporallyClose(_ a: VectorEntry, to b: VectorEntry) -> Bool {
        let timeInterval = abs(
            a.metadata.timestamp.timeIntervalSince(b.metadata.timestamp)
        )
        
        // Adaptive temporal threshold based on memory layer
        let threshold: TimeInterval
        switch a.memoryLayer {
        case .working:
            threshold = 60  // 1 minute for working memory
        case .episodic:
            threshold = 300 // 5 minutes for episodic
        case .semantic:
            threshold = 3600 // 1 hour for semantic
        }

        return timeInterval < threshold
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
