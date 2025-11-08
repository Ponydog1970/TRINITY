//
//  MemoryLayer.swift
//  TRINITY Vision Aid
//
//  Three-layer memory architecture for contextual awareness
//

import Foundation
import CoreLocation

/// Represents the three layers of memory in the TRINITY system
enum MemoryLayerType: String, Codable {
    case working    // Kurzzeitgedächtnis - current scene, active objects
    case episodic   // Episodisches Gedächtnis - visited places, temporal events
    case semantic   // Semantisches Gedächtnis - learned objects, long-term patterns
}

/// Spatial data captured from LiDAR and camera
struct SpatialData: Codable {
    let depth: Float              // Distance in meters
    let boundingBox: BoundingBox  // 3D bounding box
    let orientation: Orientation  // Object orientation
    let confidence: Float         // Detection confidence
}

struct BoundingBox: Codable {
    let x: Float
    let y: Float
    let z: Float
    let width: Float
    let height: Float
    let depth: Float
}

struct Orientation: Codable {
    let pitch: Float
    let yaw: Float
    let roll: Float
}

/// Metadata associated with each memory entry
struct MemoryMetadata: Codable, Identifiable {
    let id: UUID
    let objectType: String
    let description: String
    let confidence: Float
    let tags: [String]
    let spatialData: SpatialData?
    let timestamp: Date
    let location: CLLocationCoordinate2D?

    init(
        id: UUID = UUID(),
        objectType: String,
        description: String,
        confidence: Float,
        tags: [String] = [],
        spatialData: SpatialData? = nil,
        timestamp: Date = Date(),
        location: CLLocationCoordinate2D? = nil
    ) {
        self.id = id
        self.objectType = objectType
        self.description = description
        self.confidence = confidence
        self.tags = tags
        self.spatialData = spatialData
        self.timestamp = timestamp
        self.location = location
    }
}

/// Vector entry in the memory system
struct VectorEntry: Codable, Identifiable {
    let id: UUID
    let embedding: [Float]         // 512 or 768 dimensions
    let metadata: MemoryMetadata
    let memoryLayer: MemoryLayerType
    var accessCount: Int           // Frequency of access
    var lastAccessed: Date

    init(
        id: UUID = UUID(),
        embedding: [Float],
        metadata: MemoryMetadata,
        memoryLayer: MemoryLayerType,
        accessCount: Int = 0,
        lastAccessed: Date = Date()
    ) {
        self.id = id
        self.embedding = embedding
        self.metadata = metadata
        self.memoryLayer = memoryLayer
        self.accessCount = accessCount
        self.lastAccessed = lastAccessed
    }

    /// Calculate cosine similarity with another embedding
    func similarity(to other: [Float]) -> Float {
        guard embedding.count == other.count else { return 0.0 }

        let dotProduct = zip(embedding, other).map(*).reduce(0, +)
        let magnitudeA = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(other.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0, magnitudeB > 0 else { return 0.0 }
        return dotProduct / (magnitudeA * magnitudeB)
    }
}

/// Observation from sensors that will be converted to memory entries
struct Observation {
    let timestamp: Date
    let cameraImage: Data?
    let depthMap: Data?
    let detectedObjects: [DetectedObject]
    let location: CLLocation?
    let deviceOrientation: Orientation
}

struct DetectedObject: Identifiable {
    let id: UUID
    let label: String
    let confidence: Float
    let boundingBox: BoundingBox
    let spatialData: SpatialData?
}

extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}
