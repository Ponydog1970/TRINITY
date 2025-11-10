//
//  ConsolidationPredictor.swift
//  TRINITY Vision Aid
//
//  ML-based predictor for memory consolidation decisions
//

import Foundation

/// Uses machine learning to predict when memories should be consolidated
class ConsolidationPredictor {
    
    // MARK: - Properties
    
    private var trainingData: [(features: ConsolidationFeatures, shouldConsolidate: Bool)] = []
    private var weights: [Double] = []
    private let featureCount = 8
    private let learningRate = 0.01
    
    // MARK: - Feature Extraction
    
    struct ConsolidationFeatures {
        let accessFrequency: Double      // How often accessed (normalized)
        let timeSinceLastAccess: Double  // Time since last access (normalized hours)
        let averageConfidence: Double    // Average confidence score
        let spatialStability: Double     // How stable spatial position is
        let temporalCluster: Double      // Part of temporal cluster (0-1)
        let semanticRelevance: Double    // Semantic importance (0-1)
        let memoryAge: Double            // Age in hours (normalized)
        let accessPattern: Double        // Access pattern score (0-1)
        
        func toArray() -> [Double] {
            return [
                accessFrequency,
                timeSinceLastAccess,
                averageConfidence,
                spatialStability,
                temporalCluster,
                semanticRelevance,
                memoryAge,
                accessPattern
            ]
        }
    }
    
    // MARK: - Initialization
    
    init() {
        // Initialize weights with small random values
        weights = (0..<featureCount).map { _ in Double.random(in: -0.1...0.1) }
    }
    
    // MARK: - Prediction
    
    /// Predict consolidation score for a memory entry (0-1, higher means should consolidate)
    func predictConsolidationScore(for entry: VectorEntry, currentTime: Date = Date()) -> Double {
        let features = extractFeatures(from: entry, currentTime: currentTime)
        return sigmoid(predict(features: features.toArray()))
    }
    
    /// Determine if memory should be consolidated to next layer
    func shouldConsolidate(_ entry: VectorEntry, threshold: Double = 0.7) -> Bool {
        let score = predictConsolidationScore(for: entry)
        return score >= threshold
    }
    
    /// Predict consolidation for batch of entries
    func predictBatch(_ entries: [VectorEntry], threshold: Double = 0.7) -> [(entry: VectorEntry, score: Double, shouldConsolidate: Bool)] {
        return entries.map { entry in
            let score = predictConsolidationScore(for: entry)
            return (entry, score, score >= threshold)
        }
    }
    
    // MARK: - Training
    
    /// Train model with observed consolidation outcome
    func train(entry: VectorEntry, shouldConsolidate: Bool) {
        let features = extractFeatures(from: entry, currentTime: Date())
        let featureArray = features.toArray()
        
        // Store training data
        trainingData.append((features, shouldConsolidate))
        
        // Perform gradient descent update
        let prediction = sigmoid(predict(features: featureArray))
        let target = shouldConsolidate ? 1.0 : 0.0
        let error = target - prediction
        
        // Update weights
        for i in 0..<weights.count {
            let gradient = error * featureArray[i]
            weights[i] += learningRate * gradient
        }
    }
    
    /// Batch training for multiple observations
    func batchTrain(observations: [(entry: VectorEntry, shouldConsolidate: Bool)]) {
        for observation in observations {
            train(entry: observation.entry, shouldConsolidate: observation.shouldConsolidate)
        }
    }
    
    // MARK: - Feature Extraction
    
    private func extractFeatures(from entry: VectorEntry, currentTime: Date) -> ConsolidationFeatures {
        // Access frequency (normalized by typical max of 50 accesses)
        let accessFrequency = min(Double(entry.accessCount) / 50.0, 1.0)
        
        // Time since last access (normalized by typical max of 24 hours)
        let timeSinceLastAccess = min(
            currentTime.timeIntervalSince(entry.lastAccessed) / (24.0 * 3600.0),
            1.0
        )
        
        // Average confidence from metadata
        let averageConfidence = Double(entry.metadata.confidence)
        
        // Spatial stability (if has spatial data, otherwise 0.5)
        let spatialStability = entry.metadata.spatialData != nil ? 0.8 : 0.5
        
        // Temporal clustering - check if part of cluster (simplified)
        let temporalCluster = calculateTemporalCluster(entry: entry)
        
        // Semantic relevance based on number of tags
        let semanticRelevance = min(Double(entry.metadata.tags.count) / 10.0, 1.0)
        
        // Memory age (normalized by typical max of 7 days)
        let memoryAge = min(
            currentTime.timeIntervalSince(entry.metadata.timestamp) / (7.0 * 24.0 * 3600.0),
            1.0
        )
        
        // Access pattern score (higher access count + recent access = higher score)
        let recencyBoost = timeSinceLastAccess < 0.1 ? 0.3 : 0.0
        let accessPattern = min(accessFrequency + recencyBoost, 1.0)
        
        return ConsolidationFeatures(
            accessFrequency: accessFrequency,
            timeSinceLastAccess: timeSinceLastAccess,
            averageConfidence: averageConfidence,
            spatialStability: spatialStability,
            temporalCluster: temporalCluster,
            semanticRelevance: semanticRelevance,
            memoryAge: memoryAge,
            accessPattern: accessPattern
        )
    }
    
    private func calculateTemporalCluster(entry: VectorEntry) -> Double {
        // Simplified temporal clustering score
        // In a real implementation, this would check against other entries
        let daysSinceCreation = Date().timeIntervalSince(entry.metadata.timestamp) / (24.0 * 3600.0)
        
        // Higher score if created recently (suggesting it's part of active session)
        if daysSinceCreation < 1.0 {
            return 0.8
        } else if daysSinceCreation < 7.0 {
            return 0.5
        } else {
            return 0.2
        }
    }
    
    // MARK: - Model Functions
    
    private func predict(features: [Double]) -> Double {
        guard features.count == weights.count else {
            return 0.0
        }
        
        // Linear combination of features and weights
        return zip(features, weights).map(*).reduce(0, +)
    }
    
    private func sigmoid(_ x: Double) -> Double {
        return 1.0 / (1.0 + exp(-x))
    }
    
    // MARK: - Model Persistence
    
    func saveModel(to url: URL) throws {
        let modelData = ModelData(weights: weights, trainingDataCount: trainingData.count)
        let encoder = JSONEncoder()
        let data = try encoder.encode(modelData)
        try data.write(to: url)
    }
    
    func loadModel(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let modelData = try decoder.decode(ModelData.self, from: data)
        self.weights = modelData.weights
    }
    
    struct ModelData: Codable {
        let weights: [Double]
        let trainingDataCount: Int
    }
}
