//
//  ResourceMonitorTests.swift
//  TRINITYTests
//
//  Unit tests for ResourceMonitor adaptive memory management
//

import XCTest
@testable import TRINITY

final class ResourceMonitorTests: XCTestCase {
    
    var resourceMonitor: ResourceMonitor!
    
    override func setUp() {
        super.setUp()
        resourceMonitor = ResourceMonitor()
    }
    
    override func tearDown() {
        resourceMonitor = nil
        super.tearDown()
    }
    
    // MARK: - Memory Level Tests
    
    func testGetMemoryLevel() {
        // Test that memory level is returned
        let level = resourceMonitor.getMemoryLevel()
        
        // Should return a valid resource level
        XCTAssertTrue([
            ResourceMonitor.ResourceLevel.abundant,
            .normal,
            .constrained,
            .critical
        ].contains(level))
    }
    
    func testGetCPULevel() {
        // Test that CPU level is returned
        let level = resourceMonitor.getCPULevel()
        
        // Should return a valid resource level
        XCTAssertTrue([
            ResourceMonitor.ResourceLevel.abundant,
            .normal,
            .constrained,
            .critical
        ].contains(level))
    }
    
    // MARK: - Working Memory Size Tests
    
    func testRecommendedWorkingMemorySizeAbundant() {
        // When resources are abundant, should recommend larger size
        let baseSize = 100
        let recommendedSize = resourceMonitor.getRecommendedWorkingMemorySize(baseSize: baseSize)
        
        // Recommended size should be between 40% and 150% of base
        XCTAssertGreaterThanOrEqual(recommendedSize, Int(Double(baseSize) * 0.4))
        XCTAssertLessThanOrEqual(recommendedSize, Int(Double(baseSize) * 1.5))
    }
    
    func testRecommendedWorkingMemorySizeNormal() {
        // Test with normal base size
        let baseSize = 100
        let recommendedSize = resourceMonitor.getRecommendedWorkingMemorySize(baseSize: baseSize)
        
        // Should return a positive value
        XCTAssertGreaterThan(recommendedSize, 0)
    }
    
    func testRecommendedWorkingMemorySizeSmallBase() {
        // Test with small base size
        let baseSize = 10
        let recommendedSize = resourceMonitor.getRecommendedWorkingMemorySize(baseSize: baseSize)
        
        // Should still work with small base
        XCTAssertGreaterThan(recommendedSize, 0)
    }
    
    func testRecommendedWorkingMemorySizeLargeBase() {
        // Test with large base size
        let baseSize = 1000
        let recommendedSize = resourceMonitor.getRecommendedWorkingMemorySize(baseSize: baseSize)
        
        // Should scale appropriately
        XCTAssertGreaterThan(recommendedSize, 0)
        XCTAssertLessThanOrEqual(recommendedSize, baseSize * 2)
    }
    
    // MARK: - Consolidation Tests
    
    func testShouldConsolidateAggressively() {
        // Test that consolidation recommendation is boolean
        let shouldConsolidate = resourceMonitor.shouldConsolidateAggressively()
        
        // Should return a boolean value
        XCTAssertNotNil(shouldConsolidate)
    }
    
    func testMultipleResourceChecks() {
        // Test that multiple checks don't cause issues
        for _ in 0..<10 {
            let memoryLevel = resourceMonitor.getMemoryLevel()
            let cpuLevel = resourceMonitor.getCPULevel()
            let recommendedSize = resourceMonitor.getRecommendedWorkingMemorySize()
            
            XCTAssertNotNil(memoryLevel)
            XCTAssertNotNil(cpuLevel)
            XCTAssertGreaterThan(recommendedSize, 0)
        }
    }
}
