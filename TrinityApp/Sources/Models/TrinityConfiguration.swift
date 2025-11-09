//
//  TrinityConfiguration.swift
//  TRINITY Vision Aid
//
//  Centralized configuration system for all components
//

import Foundation

/// Global configuration for TRINITY system
struct TrinityConfiguration: Codable {
    // MARK: - Memory Configuration
    var memory: MemoryConfiguration

    // MARK: - Performance Configuration
    var performance: PerformanceConfiguration

    // MARK: - Agent Configuration
    var agents: AgentConfiguration

    // MARK: - Default Configuration
    static let `default` = TrinityConfiguration(
        memory: .default,
        performance: .default,
        agents: .default
    )

    // MARK: - Persistence
    private static let configURL: URL = {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsPath.appendingPathComponent("trinity_config.json")
    }()

    static func load() throws -> TrinityConfiguration {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return .default
        }

        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        return try decoder.decode(TrinityConfiguration.self, from: data)
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: Self.configURL, options: .atomic)
    }
}

// MARK: - Memory Configuration

struct MemoryConfiguration: Codable {
    /// Maximum number of entries in working memory (default: 100)
    var maxWorkingMemorySize: Int

    /// Episodic memory retention window in seconds (default: 30 days)
    var episodicMemoryWindow: TimeInterval

    /// Similarity threshold for deduplication (default: 0.95)
    var similarityThreshold: Float

    /// Minimum access count for promotion to semantic memory (default: 10)
    var semanticPromotionThreshold: Int

    /// Maximum semantic memory entries before compression (default: 50000)
    var maxSemanticMemorySize: Int

    /// Enable automatic memory consolidation (default: true)
    var autoConsolidation: Bool

    /// Consolidation interval in seconds (default: 1 hour)
    var consolidationInterval: TimeInterval

    static let `default` = MemoryConfiguration(
        maxWorkingMemorySize: 100,
        episodicMemoryWindow: 30 * 24 * 60 * 60, // 30 days
        similarityThreshold: 0.95,
        semanticPromotionThreshold: 10,
        maxSemanticMemorySize: 50_000,
        autoConsolidation: true,
        consolidationInterval: 3600 // 1 hour
    )
}

// MARK: - Performance Configuration

struct PerformanceConfiguration: Codable {
    /// Target frame processing rate (default: 1.0 second)
    var processingInterval: TimeInterval

    /// Maximum concurrent embedding generations (default: 4)
    var maxConcurrentEmbeddings: Int

    /// Enable batch processing (default: true)
    var enableBatchProcessing: Bool

    /// Batch size for embedding generation (default: 10)
    var batchSize: Int

    /// Vector search top-K results (default: 10)
    var vectorSearchTopK: Int

    /// Enable LRU caching for embeddings (default: true)
    var enableEmbeddingCache: Bool

    /// Embedding cache size (default: 1000)
    var embeddingCacheSize: Int

    static let `default` = PerformanceConfiguration(
        processingInterval: 1.0,
        maxConcurrentEmbeddings: 4,
        enableBatchProcessing: true,
        batchSize: 10,
        vectorSearchTopK: 10,
        enableEmbeddingCache: true,
        embeddingCacheSize: 1000
    )
}

// MARK: - Agent Configuration

struct AgentConfiguration: Codable {
    /// Navigation agent configuration
    var navigation: NavigationAgentConfiguration

    /// Communication agent configuration
    var communication: CommunicationAgentConfiguration

    /// Perception agent configuration
    var perception: PerceptionAgentConfiguration

    static let `default` = AgentConfiguration(
        navigation: .default,
        communication: .default,
        perception: .default
    )
}

struct NavigationAgentConfiguration: Codable {
    /// Minimum safe distance in meters (default: 1.0)
    var minSafeDistance: Float

    /// Warning distance in meters (default: 2.0)
    var warningDistance: Float

    /// Critical distance in meters (default: 0.5)
    var criticalDistance: Float

    /// Enable route planning (default: true)
    var enableRoutePlanning: Bool

    static let `default` = NavigationAgentConfiguration(
        minSafeDistance: 1.0,
        warningDistance: 2.0,
        criticalDistance: 0.5,
        enableRoutePlanning: true
    )
}

struct CommunicationAgentConfiguration: Codable {
    /// Default verbosity level (0: minimal, 1: medium, 2: detailed)
    var defaultVerbosity: Int

    /// Speech rate multiplier (default: 1.0)
    var speechRateMultiplier: Float

    /// Enable haptic feedback (default: true)
    var enableHapticFeedback: Bool

    /// Enable spatial audio (default: true)
    var enableSpatialAudio: Bool

    /// Language code (default: "de-DE")
    var languageCode: String

    static let `default` = CommunicationAgentConfiguration(
        defaultVerbosity: 1,
        speechRateMultiplier: 1.0,
        enableHapticFeedback: true,
        enableSpatialAudio: true,
        languageCode: "de-DE"
    )
}

struct PerceptionAgentConfiguration: Codable {
    /// Minimum confidence threshold for detections (default: 0.7)
    var minConfidenceThreshold: Float

    /// Maximum objects to process per frame (default: 20)
    var maxObjectsPerFrame: Int

    /// Enable plane detection (default: true)
    var enablePlaneDetection: Bool

    /// Enable person segmentation (default: true)
    var enablePersonSegmentation: Bool

    static let `default` = PerceptionAgentConfiguration(
        minConfidenceThreshold: 0.7,
        maxObjectsPerFrame: 20,
        enablePlaneDetection: true,
        enablePersonSegmentation: true
    )
}
