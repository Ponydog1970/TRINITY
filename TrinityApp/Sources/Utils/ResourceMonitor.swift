//
//  ResourceMonitor.swift
//  TRINITY Vision Aid
//
//  Monitors system resources for adaptive memory management
//

import Foundation
import os

/// Monitors system resources (CPU, memory, battery) for adaptive optimization
class ResourceMonitor {
    
    // MARK: - Properties
    
    private var lastMemoryCheck: Date = Date()
    private let checkInterval: TimeInterval = 2.0 // Check every 2 seconds
    
    // MARK: - Resource Levels
    
    enum ResourceLevel {
        case abundant   // > 80% available
        case normal     // 50-80% available
        case constrained // 20-50% available
        case critical   // < 20% available
    }
    
    // MARK: - Public Methods
    
    /// Get current memory availability level
    func getMemoryLevel() -> ResourceLevel {
        let memoryInfo = getMemoryUsage()
        let availablePercentage = memoryInfo.availablePercentage
        
        switch availablePercentage {
        case 0.8...1.0:
            return .abundant
        case 0.5..<0.8:
            return .normal
        case 0.2..<0.5:
            return .constrained
        default:
            return .critical
        }
    }
    
    /// Get current CPU usage level
    func getCPULevel() -> ResourceLevel {
        let cpuUsage = getCPUUsage()
        
        switch cpuUsage {
        case 0.0..<0.2:
            return .abundant
        case 0.2..<0.5:
            return .normal
        case 0.5..<0.8:
            return .constrained
        default:
            return .critical
        }
    }
    
    /// Get recommended working memory size based on available resources
    func getRecommendedWorkingMemorySize(baseSize: Int = 100) -> Int {
        let memoryLevel = getMemoryLevel()
        let cpuLevel = getCPULevel()
        
        // Adjust based on worst resource constraint
        let effectiveLevel = [memoryLevel, cpuLevel].min { level1, level2 in
            levelToValue(level1) < levelToValue(level2)
        } ?? .normal
        
        switch effectiveLevel {
        case .abundant:
            return Int(Double(baseSize) * 1.5) // 150% of base
        case .normal:
            return baseSize // 100% of base
        case .constrained:
            return Int(Double(baseSize) * 0.7) // 70% of base
        case .critical:
            return Int(Double(baseSize) * 0.4) // 40% of base
        }
    }
    
    /// Check if system should trigger aggressive memory consolidation
    func shouldConsolidateAggressively() -> Bool {
        let memoryLevel = getMemoryLevel()
        return memoryLevel == .critical || memoryLevel == .constrained
    }
    
    // MARK: - Private Methods
    
    private func getMemoryUsage() -> (used: UInt64, total: UInt64, availablePercentage: Double) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMemory = info.resident_size
            
            // Get total physical memory
            var size: UInt64 = 0
            var sizeLength = MemoryLayout<UInt64>.size
            sysctlbyname("hw.memsize", &size, &sizeLength, nil, 0)
            
            let availablePercentage = Double(size - usedMemory) / Double(size)
            return (usedMemory, size, availablePercentage)
        }
        
        // Return safe defaults if unable to get actual values
        return (0, 0, 0.5)
    }
    
    private func getCPUUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        
        let threadsResult = task_threads(mach_task_self_, &threadsList, &threadsCount)
        
        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)],
                                   thread_flavor_t(THREAD_BASIC_INFO),
                                   $0,
                                   &threadInfoCount)
                    }
                }
                
                guard infoResult == KERN_SUCCESS else {
                    continue
                }
                
                let threadBasicInfo = threadInfo
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU += (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
                }
            }
            
            vm_deallocate(mach_task_self_,
                         vm_address_t(UInt(bitPattern: threadsList)),
                         vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        }
        
        return totalUsageOfCPU
    }
    
    private func levelToValue(_ level: ResourceLevel) -> Int {
        switch level {
        case .abundant: return 4
        case .normal: return 3
        case .constrained: return 2
        case .critical: return 1
        }
    }
}
