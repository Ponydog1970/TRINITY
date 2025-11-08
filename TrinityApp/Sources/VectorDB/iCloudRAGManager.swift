//
//  iCloudRAGManager.swift
//  TRINITY Vision Aid
//
//  iCloud-basiertes RAG-Offloading für Speicherplatzoptimierung
//

import Foundation
import CloudKit
import Combine

/// Verwaltet RAG-Daten zwischen lokalem Speicher und iCloud
@MainActor
class iCloudRAGManager: ObservableObject {

    // MARK: - Configuration

    /// Speicher-Strategie
    enum StorageStrategy {
        case localOnly                  // Alles lokal (Standard)
        case hybridSmart               // Smart: Wichtige lokal, Rest iCloud
        case cloudFirst                // Meiste Daten in iCloud
        case autoOptimize              // Automatisch basierend auf Speicher
    }

    @Published var strategy: StorageStrategy = .hybridSmart
    @Published var localStorageUsage: Int64 = 0      // Bytes
    @Published var iCloudStorageUsage: Int64 = 0     // Bytes

    // MARK: - Thresholds

    private let maxLocalStorageMB: Int64 = 500       // Max 500 MB lokal
    private let minImportanceForLocal: Float = 0.7   // Nur wichtige Daten lokal
    private let maxAgeForLocalDays: Int = 30         // Alte Daten → iCloud

    private let container: CKContainer
    private let privateDatabase: CKDatabase

    // Cache für kürzlich abgerufene iCloud-Daten
    private var iCloudCache: [UUID: EnhancedVectorEntry] = [:]
    private let maxCacheSize = 100

    init() {
        self.container = CKContainer.default()
        self.privateDatabase = container.privateCloudDatabase
    }

    // MARK: - Storage Decision

    /// Entscheidet wo Memory gespeichert werden soll
    func determineStorage(for memory: EnhancedVectorEntry) -> StorageLocation {
        switch strategy {
        case .localOnly:
            return .local

        case .hybridSmart:
            return determineSmartStorage(for: memory)

        case .cloudFirst:
            // Nur sehr wichtige lokal
            return memory.importance > 0.9 ? .local : .iCloud

        case .autoOptimize:
            return determineAutoOptimizedStorage(for: memory)
        }
    }

    private func determineSmartStorage(for memory: EnhancedVectorEntry) -> StorageLocation {
        // Wichtigkeit prüfen
        if memory.importance >= minImportanceForLocal {
            return .local
        }

        // Alter prüfen
        let age = Date().timeIntervalSince(memory.timestamp) / (24 * 60 * 60) // Tage
        if age > Double(maxAgeForLocalDays) {
            return .iCloud
        }

        // Häufigkeit prüfen
        if memory.accessCount > 10 {
            return .local // Häufig genutzt → lokal
        }

        // Memory Layer prüfen
        if memory.memoryLayer == .working {
            return .local // Working Memory immer lokal
        }

        // Standard: iCloud
        return .iCloud
    }

    private func determineAutoOptimizedStorage(for memory: EnhancedVectorEntry) -> StorageLocation {
        // Prüfe aktuellen Speicherverbrauch
        let localUsageMB = localStorageUsage / (1024 * 1024)

        if localUsageMB < maxLocalStorageMB / 2 {
            // Viel Platz → großzügig lokal speichern
            return memory.importance > 0.5 ? .local : .iCloud
        } else if localUsageMB < maxLocalStorageMB {
            // Moderater Platz → nur wichtige lokal
            return memory.importance > 0.7 ? .local : .iCloud
        } else {
            // Wenig Platz → nur kritische lokal
            return memory.importance > 0.9 ? .local : .iCloud
        }
    }

    // MARK: - Save to iCloud

    /// Speichert Memory in iCloud
    func saveToiCloud(_ memory: EnhancedVectorEntry) async throws {
        // Erstelle CloudKit Record
        let record = createCKRecord(from: memory)

        // Speichere in iCloud
        let _ = try await privateDatabase.save(record)

        // Update Usage
        await updateStorageUsage()

        print("☁️ Saved to iCloud: \(memory.id)")
    }

    /// Speichert mehrere Memories in iCloud (Batch)
    func batchSaveToiCloud(_ memories: [EnhancedVectorEntry]) async throws {
        let records = memories.map { createCKRecord(from: $0) }

        // CloudKit Batch-Operation
        let operation = CKModifyRecordsOperation(recordsToSave: records)
        operation.savePolicy = .changedKeys

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            privateDatabase.add(operation)
        }

        await updateStorageUsage()

        print("☁️ Batch saved \(memories.count) memories to iCloud")
    }

    // MARK: - Load from iCloud

    /// Lädt Memory aus iCloud
    func loadFromiCloud(id: UUID) async throws -> EnhancedVectorEntry {
        // Prüfe Cache
        if let cached = iCloudCache[id] {
            print("💾 Cache hit for: \(id)")
            return cached
        }

        // Suche in iCloud
        let predicate = NSPredicate(format: "memoryID == %@", id.uuidString)
        let query = CKQuery(recordType: "EnhancedVectorEntry", predicate: predicate)

        let results = try await privateDatabase.records(matching: query)

        guard let (_, result) = results.matchResults.first else {
            throw iCloudError.notFound
        }

        let record = try result.get()
        let memory = try parseMemory(from: record)

        // Cache
        addToCache(memory)

        print("☁️ Loaded from iCloud: \(id)")
        return memory
    }

    /// Sucht Memories in iCloud
    func searchiCloud(
        query: String,
        limit: Int = 10
    ) async throws -> [EnhancedVectorEntry] {
        // Suche nach Keywords
        let predicate = NSPredicate(format: "keywords CONTAINS %@", query)
        let ckQuery = CKQuery(recordType: "EnhancedVectorEntry", predicate: predicate)

        let results = try await privateDatabase.records(matching: ckQuery)

        var memories: [EnhancedVectorEntry] = []

        for (_, result) in results.matchResults.prefix(limit) {
            if let record = try? result.get(),
               let memory = try? parseMemory(from: record) {
                memories.append(memory)
                addToCache(memory)
            }
        }

        return memories
    }

    // MARK: - Migration

    /// Migriert alte Memories von lokal zu iCloud
    func migrateOldMemoriesToiCloud(
        olderThan days: Int,
        minImportance: Float
    ) async throws -> Int {
        // Diese Funktion würde mit dem lokalen VectorDatabase koordinieren
        // Placeholder für die Logik

        var migratedCount = 0

        // 1. Finde alte, unwichtige Memories lokal
        // 2. Upload zu iCloud
        // 3. Lösche lokal
        // 4. Behalte Referenz (MemoryStub)

        print("☁️ Migrated \(migratedCount) memories to iCloud")
        return migratedCount
    }

    /// Optimiert Speichernutzung automatisch
    func optimizeStorage() async throws {
        let localUsageMB = localStorageUsage / (1024 * 1024)

        if localUsageMB > maxLocalStorageMB {
            print("⚠️ Speicher voll, optimiere...")

            // 1. Identifiziere Kandidaten für Migration
            // 2. Migriere zu iCloud
            // 3. Lösche lokal

            let freed = try await migrateOldMemoriesToiCloud(
                olderThan: 30,
                minImportance: 0.5
            )

            print("✅ \(freed) Memories migriert, Speicher freigegeben")
        }
    }

    // MARK: - Hybrid Retrieval

    /// Intelligente Suche über lokal + iCloud
    func hybridSearch(
        embedding: [Float],
        topK: Int = 10
    ) async throws -> [EnhancedVectorEntry] {

        // 1. Suche lokal (schnell)
        // let localResults = await localDB.search(embedding, topK: topK)

        // 2. Wenn nicht genug Ergebnisse, suche iCloud
        // if localResults.count < topK {
        //     let cloudResults = try await searchiCloudByEmbedding(embedding, topK: topK - localResults.count)
        //     return localResults + cloudResults
        // }

        // Placeholder
        return []
    }

    // MARK: - CloudKit Helpers

    private func createCKRecord(from memory: EnhancedVectorEntry) -> CKRecord {
        let record = CKRecord(recordType: "EnhancedVectorEntry")

        record["memoryID"] = memory.id.uuidString
        record["embedding"] = memory.embedding as [Double] // CloudKit nutzt Double
        record["objectType"] = memory.objectType
        record["description"] = memory.description
        record["confidence"] = memory.confidence as Double
        record["importance"] = memory.importance as Double
        record["keywords"] = memory.keywords
        record["categories"] = memory.categories
        record["timestamp"] = memory.timestamp
        record["timeOfDay"] = memory.timeOfDay
        record["accessCount"] = memory.accessCount
        record["quality"] = memory.quality as Double

        if let location = memory.location {
            record["location"] = CLLocation(
                latitude: location.latitude,
                longitude: location.longitude
            )
        }

        if let locationName = memory.locationName {
            record["locationName"] = locationName
        }

        // Metadata als JSON
        if let metadataJSON = try? JSONEncoder().encode(memory) {
            record["fullMetadata"] = String(data: metadataJSON, encoding: .utf8)
        }

        return record
    }

    private func parseMemory(from record: CKRecord) throws -> EnhancedVectorEntry {
        // Parse von CloudKit Record zurück zu EnhancedVectorEntry

        guard let memoryIDString = record["memoryID"] as? String,
              let memoryID = UUID(uuidString: memoryIDString),
              let embeddingDoubles = record["embedding"] as? [Double],
              let objectType = record["objectType"] as? String,
              let description = record["description"] as? String,
              let confidence = record["confidence"] as? Double,
              let importance = record["importance"] as? Double,
              let timestamp = record["timestamp"] as? Date,
              let timeOfDay = record["timeOfDay"] as? String,
              let quality = record["quality"] as? Double else {
            throw iCloudError.parseError
        }

        let embedding = embeddingDoubles.map { Float($0) }
        let keywords = record["keywords"] as? [String] ?? []
        let categories = record["categories"] as? [String] ?? []
        let accessCount = record["accessCount"] as? Int ?? 0

        var location: CLLocationCoordinate2D?
        if let clLocation = record["location"] as? CLLocation {
            location = clLocation.coordinate
        }

        let locationName = record["locationName"] as? String

        // Wenn fullMetadata vorhanden, nutze das
        if let metadataJSON = record["fullMetadata"] as? String,
           let data = metadataJSON.data(using: .utf8),
           let fullMemory = try? JSONDecoder().decode(EnhancedVectorEntry.self, from: data) {
            return fullMemory
        }

        // Sonst rekonstruiere minimal
        return EnhancedVectorEntry(
            id: memoryID,
            embedding: embedding,
            memoryLayer: .semantic, // Default
            objectType: objectType,
            description: description,
            confidence: Float(confidence),
            keywords: keywords,
            categories: categories,
            importance: Float(importance),
            timestamp: timestamp,
            timeOfDay: timeOfDay,
            dayOfWeek: "",
            location: location,
            locationName: locationName,
            sourceType: "iCloud",
            quality: Float(quality)
        )
    }

    // MARK: - Cache Management

    private func addToCache(_ memory: EnhancedVectorEntry) {
        iCloudCache[memory.id] = memory

        // Limit Cache-Größe
        if iCloudCache.count > maxCacheSize {
            // Entferne älteste
            if let oldest = iCloudCache.values.min(by: { $0.lastAccessed < $1.lastAccessed }) {
                iCloudCache.removeValue(forKey: oldest.id)
            }
        }
    }

    func clearCache() {
        iCloudCache.removeAll()
    }

    // MARK: - Storage Usage

    private func updateStorageUsage() async {
        // Berechne Speichernutzung
        // Placeholder
        self.localStorageUsage = 0
        self.iCloudStorageUsage = 0
    }

    func getStorageStatistics() async -> StorageStatistics {
        await updateStorageUsage()

        return StorageStatistics(
            localStorageMB: localStorageUsage / (1024 * 1024),
            iCloudStorageMB: iCloudStorageUsage / (1024 * 1024),
            totalMemories: 0,
            localMemories: 0,
            cloudMemories: 0,
            cacheHitRate: 0.0
        )
    }
}

// MARK: - Supporting Types

enum StorageLocation {
    case local
    case iCloud
    case both
}

enum iCloudError: Error {
    case notFound
    case parseError
    case networkError
    case quotaExceeded

    var localizedDescription: String {
        switch self {
        case .notFound: return "Memory nicht in iCloud gefunden"
        case .parseError: return "Fehler beim Parsen von iCloud-Daten"
        case .networkError: return "Netzwerkfehler bei iCloud-Zugriff"
        case .quotaExceeded: return "iCloud-Speicher voll"
        }
    }
}

struct StorageStatistics {
    let localStorageMB: Int64
    let iCloudStorageMB: Int64
    let totalMemories: Int
    let localMemories: Int
    let cloudMemories: Int
    let cacheHitRate: Float
}

// MARK: - Memory Stub (für migrierte Memories)

/// Leichtgewichtige Referenz zu iCloud-Memory
struct MemoryStub: Codable {
    let id: UUID
    let description: String
    let importance: Float
    let timestamp: Date
    let iCloudRecordID: String

    /// Lädt volles Memory bei Bedarf
    func loadFull(from manager: iCloudRAGManager) async throws -> EnhancedVectorEntry {
        return try await manager.loadFromiCloud(id: id)
    }
}

// MARK: - Usage Example

/*
 // iCloud RAG Manager erstellen:
 let iCloudManager = iCloudRAGManager()

 // Strategie setzen:
 iCloudManager.strategy = .hybridSmart

 // Memory speichern:
 let location = iCloudManager.determineStorage(for: memory)

 if location == .iCloud {
     try await iCloudManager.saveToiCloud(memory)
 }

 // Memory abrufen:
 let memory = try await iCloudManager.loadFromiCloud(id: memoryID)

 // Speicher optimieren:
 try await iCloudManager.optimizeStorage()

 // Statistiken:
 let stats = await iCloudManager.getStorageStatistics()
 print("Lokal: \(stats.localStorageMB) MB")
 print("iCloud: \(stats.iCloudStorageMB) MB")

 // Hybride Suche:
 let results = try await iCloudManager.hybridSearch(
     embedding: queryEmbedding,
     topK: 10
 )
 */
