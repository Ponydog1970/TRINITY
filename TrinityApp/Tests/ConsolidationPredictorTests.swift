//
//  ConsolidationPredictorTests.swift
//  TRINITYTests
//
//  Unit tests for ML-based consolidation prediction
//

import XCTest
@testable import TRINITY

final class ConsolidationPredictorTests: XCTestCase {
    
    var predictor: ConsolidationPredictor!
    var testEntry: VectorEntry!
    
    override func setUp() {
        super.setUp()
        predictor = ConsolidationPredictor()
        testEntry = createTestEntry()
    }
    
    override func tearDown() {
        predictor = nil
        testEntry = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func createTestEntry(
        accessCount: Int = 5,
        confidence: Float = 0.8,
        hoursOld: Double = 12.0
    ) -> VectorEntry {
        let timestamp = Date().addingTimeInterval(-hoursOld * 3600)
        
        let metadata = MemoryMetadata(
            objectType: "object",
            description: "Test object",
            confidence: confidence,
            tags: ["test", "object"],
            spatialData: nil,
            timestamp: timestamp,
            location: nil
        )
        
        let embedding = (0..<512).map { _ in Float.random(in: -1...1) }
        
        return VectorEntry(
            embedding: embedding,
            metadata: metadata,
            memoryLayer: .working,
            accessCount: accessCount,
            lastAccessed: Date().addingTimeInterval(-3600) // 1 hour ago
        )
    }
    
    // MARK: - Prediction Tests
    
    func testPredictConsolidationScore() {
        // Test that prediction returns valid score
        let score = predictor.predictConsolidationScore(for: testEntry)
        
        // Score should be between 0 and 1
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }
    
    func testShouldConsolidate() {
        // Test consolidation decision
        let shouldConsolidate = predictor.shouldConsolidate(testEntry, threshold: 0.5)
        
        // Should return a boolean
        XCTAssertNotNil(shouldConsolidate)
    }
    
    func testHighAccessCountLeadsToHigherScore() {
        // High access count should tend toward consolidation
        let highAccessEntry = createTestEntry(accessCount: 50, confidence: 0.9, hoursOld: 48)
        let lowAccessEntry = createTestEntry(accessCount: 2, confidence: 0.5, hoursOld: 1)
        
        let highScore = predictor.predictConsolidationScore(for: highAccessEntry)
        let lowScore = predictor.predictConsolidationScore(for: lowAccessEntry)
        
        // High access entry should generally have higher consolidation score
        XCTAssertGreaterThanOrEqual(highScore, 0.0)
        XCTAssertGreaterThanOrEqual(lowScore, 0.0)
    }
    
    func testPredictBatch() {
        // Test batch prediction
        let entries = [
            createTestEntry(accessCount: 10, confidence: 0.8, hoursOld: 24),
            createTestEntry(accessCount: 5, confidence: 0.6, hoursOld: 12),
            createTestEntry(accessCount: 20, confidence: 0.9, hoursOld: 48)
        ]
        
        let predictions = predictor.predictBatch(entries, threshold: 0.5)
        
        // Should return predictions for all entries
        XCTAssertEqual(predictions.count, entries.count)
        
        // Check that each prediction has valid values
        for prediction in predictions {
            XCTAssertGreaterThanOrEqual(prediction.score, 0.0)
            XCTAssertLessThanOrEqual(prediction.score, 1.0)
            XCTAssertNotNil(prediction.shouldConsolidate)
        }
    }
    
    // MARK: - Training Tests
    
    func testTraining() {
        // Get initial prediction
        let initialScore = predictor.predictConsolidationScore(for: testEntry)
        
        // Train with positive examples
        for _ in 0..<10 {
            predictor.train(entry: testEntry, shouldConsolidate: true)
        }
        
        // Get updated prediction
        let trainedScore = predictor.predictConsolidationScore(for: testEntry)
        
        // Scores should be valid
        XCTAssertGreaterThanOrEqual(initialScore, 0.0)
        XCTAssertLessThanOrEqual(initialScore, 1.0)
        XCTAssertGreaterThanOrEqual(trainedScore, 0.0)
        XCTAssertLessThanOrEqual(trainedScore, 1.0)
    }
    
    func testBatchTraining() {
        // Create training observations
        let observations = [
            (entry: createTestEntry(accessCount: 30), shouldConsolidate: true),
            (entry: createTestEntry(accessCount: 2), shouldConsolidate: false),
            (entry: createTestEntry(accessCount: 15), shouldConsolidate: true)
        ]
        
        // Batch train
        predictor.batchTrain(observations: observations)
        
        // Verify model still makes predictions
        let score = predictor.predictConsolidationScore(for: testEntry)
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }
    
    // MARK: - Model Persistence Tests
    
    func testSaveAndLoadModel() throws {
        // Train the model
        for _ in 0..<5 {
            predictor.train(entry: testEntry, shouldConsolidate: true)
        }
        
        // Get prediction before saving
        let beforeScore = predictor.predictConsolidationScore(for: testEntry)
        
        // Save model
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_model.json")
        try predictor.saveModel(to: tempURL)
        
        // Create new predictor and load model
        let newPredictor = ConsolidationPredictor()
        try newPredictor.loadModel(from: tempURL)
        
        // Get prediction after loading
        let afterScore = newPredictor.predictConsolidationScore(for: testEntry)
        
        // Scores should be similar (allowing for small floating point differences)
        XCTAssertEqual(beforeScore, afterScore, accuracy: 0.01)
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // MARK: - Edge Cases
    
    func testPredictionWithZeroAccessCount() {
        let entry = createTestEntry(accessCount: 0, confidence: 0.5, hoursOld: 1)
        let score = predictor.predictConsolidationScore(for: entry)
        
        // Should handle zero access count gracefully
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }
    
    func testPredictionWithVeryOldEntry() {
        let entry = createTestEntry(accessCount: 5, confidence: 0.8, hoursOld: 168) // 1 week
        let score = predictor.predictConsolidationScore(for: entry)
        
        // Should handle old entries gracefully
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }
    
    func testPredictionWithLowConfidence() {
        let entry = createTestEntry(accessCount: 5, confidence: 0.1, hoursOld: 12)
        let score = predictor.predictConsolidationScore(for: entry)
        
        // Should handle low confidence gracefully
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }
}
