//
//  EnhancedPerceptionAgent.swift
//  TRINITY Vision Aid
//
//  Enhanced Version des PerceptionAgent mit optionaler API-Unterstützung
//

import Foundation
import CoreML
import Vision
import ARKit

/// Erweiterte Version mit Cloud-API Support
class EnhancedPerceptionAgent: PerceptionAgent {
    private let openAIClient: OpenAIClient?
    private let claudeClient: AnthropicClient?
    private let useCloudAPIs: Bool

    enum Mode {
        case localOnly          // Nur lokale Core ML Models
        case cloudEnhanced      // Lokal + Cloud für schwierige Fälle
        case cloudFirst         // Cloud bevorzugt, Lokal als Fallback
    }

    private let mode: Mode

    init(
        embeddingGenerator: EmbeddingGenerator,
        openAIKey: String? = nil,
        claudeKey: String? = nil,
        mode: Mode = .localOnly
    ) throws {
        self.mode = mode
        self.useCloudAPIs = openAIKey != nil || claudeKey != nil

        if let openAIKey = openAIKey {
            self.openAIClient = OpenAIClient(apiKey: openAIKey)
        } else {
            self.openAIClient = nil
        }

        if let claudeKey = claudeKey {
            self.claudeClient = AnthropicClient(apiKey: claudeKey)
        } else {
            self.claudeClient = nil
        }

        try super.init(embeddingGenerator: embeddingGenerator)
        self.name = "EnhancedPerceptionAgent"
    }

    // MARK: - Override Process

    override func process(_ input: PerceptionInput) async throws -> PerceptionOutput {
        switch mode {
        case .localOnly:
            // Nur lokale Verarbeitung
            return try await super.process(input)

        case .cloudEnhanced:
            // Lokal zuerst, bei niedriger Confidence → Cloud
            return try await processCloudEnhanced(input)

        case .cloudFirst:
            // Cloud bevorzugt, Lokal als Fallback
            return try await processCloudFirst(input)
        }
    }

    // MARK: - Cloud-Enhanced Processing

    private func processCloudEnhanced(_ input: PerceptionInput) async throws -> PerceptionOutput {
        // 1. Lokale Verarbeitung
        let localOutput = try await super.process(input)

        // 2. Prüfe Confidence
        if localOutput.confidence > 0.8 {
            // Hohe Confidence → lokales Ergebnis nutzen
            return localOutput
        }

        // 3. Niedrige Confidence → Cloud nutzen
        print("⚠️ Niedrige Confidence (\(localOutput.confidence)) → nutze Cloud-API")

        guard let imageData = input.cameraFrame else {
            return localOutput
        }

        // 4. Cloud-Analyse
        var enhancedDescription = localOutput.sceneDescription

        if let claude = claudeClient {
            // Claude für detaillierte Analyse
            let analysis = try await claude.analyzeScene(
                imageData,
                context: "Confidence war niedrig: \(localOutput.confidence)"
            )

            enhancedDescription = analysis.sceneDescription

            // Combine Cloud + Local Objects
            let cloudObjects = analysis.objects.map { cloudObj in
                DetectedObject(
                    id: UUID(),
                    label: cloudObj.name,
                    confidence: 0.95, // Cloud hat hohe Confidence
                    boundingBox: BoundingBox(x: 0, y: 0, z: 0, width: 1, height: 1, depth: 1),
                    spatialData: nil
                )
            }

            let combinedObjects = localOutput.detectedObjects + cloudObjects

            return PerceptionOutput(
                detectedObjects: combinedObjects,
                sceneDescription: enhancedDescription,
                spatialMap: localOutput.spatialMap,
                confidence: 0.95 // Cloud-enhanced
            )

        } else if let openAI = openAIClient {
            // OpenAI GPT-4 Vision
            enhancedDescription = try await openAI.describeImage(imageData)

            return PerceptionOutput(
                detectedObjects: localOutput.detectedObjects,
                sceneDescription: enhancedDescription,
                spatialMap: localOutput.spatialMap,
                confidence: 0.9
            )
        }

        return localOutput
    }

    // MARK: - Cloud-First Processing

    private func processCloudFirst(_ input: PerceptionInput) async throws -> PerceptionOutput {
        guard let imageData = input.cameraFrame else {
            return try await super.process(input)
        }

        do {
            // Versuche Cloud zuerst
            if let claude = claudeClient {
                let analysis = try await claude.analyzeScene(imageData)

                let objects = analysis.objects.map { cloudObj in
                    DetectedObject(
                        id: UUID(),
                        label: cloudObj.name,
                        confidence: 0.95,
                        boundingBox: BoundingBox(x: 0, y: 0, z: 0, width: 1, height: 1, depth: 1),
                        spatialData: nil
                    )
                }

                // Prozessiere auch lokal für LiDAR-Daten
                let localOutput = try await super.process(input)

                return PerceptionOutput(
                    detectedObjects: objects,
                    sceneDescription: analysis.sceneDescription,
                    spatialMap: localOutput.spatialMap, // LiDAR von lokal
                    confidence: 0.95
                )
            }

        } catch {
            print("⚠️ Cloud-API Fehler: \(error) → Fallback zu lokal")
        }

        // Fallback zu lokal
        return try await super.process(input)
    }
}

// MARK: - Integration in TrinityCoordinator

/*
 // In TrinityCoordinator.swift ersetzen:

 // Alte Version:
 self.perceptionAgent = try PerceptionAgent(embeddingGenerator: embeddingGenerator)

 // Neue Version mit Cloud-Support:
 self.perceptionAgent = try EnhancedPerceptionAgent(
     embeddingGenerator: embeddingGenerator,
     openAIKey: "sk-...",  // Optional
     claudeKey: "sk-ant-...",  // Optional
     mode: .cloudEnhanced  // oder .localOnly, .cloudFirst
 )
 */

// MARK: - Settings Integration

extension EnhancedPerceptionAgent {
    /// Ändere Mode zur Laufzeit
    func setMode(_ newMode: Mode) {
        // In echter Implementation: mode ist var
        print("Mode geändert zu: \(newMode)")
    }

    /// Prüfe ob Cloud verfügbar
    func isCloudAvailable() -> Bool {
        return openAIClient != nil || claudeClient != nil
    }

    /// Statistiken
    func getCloudUsageStats() -> (localCalls: Int, cloudCalls: Int) {
        // In echter Implementation: Counter hinzufügen
        return (0, 0)
    }
}
