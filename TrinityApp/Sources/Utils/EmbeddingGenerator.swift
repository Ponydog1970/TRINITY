//
//  EmbeddingGenerator.swift
//  TRINITY Vision Aid
//
//  Local embedding generation using Core ML models
//

import Foundation
import CoreML
import Vision
import NaturalLanguage

/// Protocol for embedding generation
protocol EmbeddingGeneratorProtocol {
    func generateEmbedding(from image: Data) async throws -> [Float]
    func generateEmbedding(from text: String) async throws -> [Float]
    func generateEmbedding(from observation: Observation) async throws -> [Float]
}

/// Generates embeddings locally using Core ML
class EmbeddingGenerator: EmbeddingGeneratorProtocol {
    // Core ML models (would be actual models in production)
    private var visionModel: VNCoreMLModel?
    private var textModel: NLEmbedding?

    private let embeddingDimension = 512

    init() throws {
        // Initialize text embedding model
        textModel = NLEmbedding.sentenceEmbedding(for: .english)

        // In production, load actual Core ML models:
        // self.visionModel = try VNCoreMLModel(for: MobileNetV3().model)
    }

    // MARK: - Image Embeddings

    func generateEmbedding(from image: Data) async throws -> [Float] {
        guard let cgImage = createCGImage(from: image) else {
            throw EmbeddingError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                    continuation.resume(throwing: EmbeddingError.noFeatures)
                    return
                }

                // Convert VNFeaturePrintObservation to Float array
                let embedding = self.convertFeaturePrint(observation)
                continuation.resume(returning: embedding)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func createCGImage(from data: Data) -> CGImage? {
        #if os(iOS)
        guard let uiImage = UIImage(data: data) else { return nil }
        return uiImage.cgImage
        #else
        guard let nsImage = NSImage(data: data) else { return nil }
        var rect = NSRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }

    private func convertFeaturePrint(_ observation: VNFeaturePrintObservation) -> [Float] {
        // Extract float array from feature print
        let dataPointer = UnsafeMutablePointer<Float>.allocate(capacity: observation.elementCount)
        defer { dataPointer.deallocate() }

        do {
            try observation.data.copyBytes(to: dataPointer, count: observation.elementCount)
            let array = Array(UnsafeBufferPointer(start: dataPointer, count: observation.elementCount))

            // Normalize to desired dimension
            return normalizeEmbedding(array, targetDimension: embeddingDimension)
        } catch {
            // Return zero vector on error
            return [Float](repeating: 0.0, count: embeddingDimension)
        }
    }

    // MARK: - Text Embeddings

    func generateEmbedding(from text: String) async throws -> [Float] {
        guard !text.isEmpty else {
            throw EmbeddingError.emptyText
        }

        // Use NLEmbedding for sentence embeddings
        if let textModel = textModel,
           let vector = textModel.vector(for: text) {
            // Convert to Float array and normalize
            let embedding = (0..<vector.count).map { Float(vector[$0]) }
            return normalizeEmbedding(embedding, targetDimension: embeddingDimension)
        }

        // Fallback: Use character-level embeddings
        return generateCharacterEmbedding(from: text)
    }

    private func generateCharacterEmbedding(from text: String) -> [Float] {
        // Simple character-based embedding (fallback)
        var embedding = [Float](repeating: 0.0, count: embeddingDimension)

        let normalized = text.lowercased()
        for (index, char) in normalized.enumerated() {
            let charValue = Float(char.asciiValue ?? 0) / 128.0
            let embeddingIndex = index % embeddingDimension
            embedding[embeddingIndex] += charValue
        }

        return normalizeVector(embedding)
    }

    // MARK: - Multimodal Embeddings

    func generateEmbedding(from observation: Observation) async throws -> [Float] {
        var embeddings: [[Float]] = []

        // Image embedding
        if let imageData = observation.cameraImage {
            let imageEmbedding = try await generateEmbedding(from: imageData)
            embeddings.append(imageEmbedding)
        }

        // Text embedding from detected objects
        if !observation.detectedObjects.isEmpty {
            let objectLabels = observation.detectedObjects
                .map { $0.label }
                .joined(separator: ", ")

            let textEmbedding = try await generateEmbedding(from: objectLabels)
            embeddings.append(textEmbedding)
        }

        // Spatial embedding from depth data
        if let depthData = observation.depthMap {
            let spatialEmbedding = generateSpatialEmbedding(from: depthData)
            embeddings.append(spatialEmbedding)
        }

        // Combine embeddings (weighted average)
        guard !embeddings.isEmpty else {
            throw EmbeddingError.noData
        }

        return combineEmbeddings(embeddings)
    }

    private func generateSpatialEmbedding(from depthData: Data) -> [Float] {
        // Generate embedding from depth map
        // This is a simplified version
        var embedding = [Float](repeating: 0.0, count: embeddingDimension)

        // Convert depth data to spatial features
        let depthBytes = [UInt8](depthData.prefix(1024))

        for (index, byte) in depthBytes.enumerated() {
            let embeddingIndex = index % embeddingDimension
            embedding[embeddingIndex] += Float(byte) / 255.0
        }

        return normalizeVector(embedding)
    }

    // MARK: - Embedding Operations

    private func combineEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard !embeddings.isEmpty else {
            return [Float](repeating: 0.0, count: embeddingDimension)
        }

        var combined = [Float](repeating: 0.0, count: embeddingDimension)
        let weight = 1.0 / Float(embeddings.count)

        for embedding in embeddings {
            for (index, value) in embedding.enumerated() {
                combined[index] += value * weight
            }
        }

        return normalizeVector(combined)
    }

    private func normalizeEmbedding(
        _ embedding: [Float],
        targetDimension: Int
    ) -> [Float] {
        if embedding.count == targetDimension {
            return normalizeVector(embedding)
        } else if embedding.count > targetDimension {
            // Truncate
            return normalizeVector(Array(embedding.prefix(targetDimension)))
        } else {
            // Pad with zeros
            var padded = embedding
            padded.append(contentsOf: [Float](repeating: 0.0, count: targetDimension - embedding.count))
            return normalizeVector(padded)
        }
    }

    private func normalizeVector(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.map { $0 * $0 }.reduce(0, +))

        guard magnitude > 0 else {
            return vector
        }

        return vector.map { $0 / magnitude }
    }

    // MARK: - Batch Processing

    func generateEmbeddings(from observations: [Observation]) async throws -> [[Float]] {
        return try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (index, observation) in observations.enumerated() {
                group.addTask {
                    let embedding = try await self.generateEmbedding(from: observation)
                    return (index, embedding)
                }
            }

            var results: [(Int, [Float])] = []
            for try await result in group {
                results.append(result)
            }

            return results
                .sorted { $0.0 < $1.0 }
                .map { $1 }
        }
    }
}

// MARK: - Errors

enum EmbeddingError: Error {
    case invalidImage
    case noFeatures
    case emptyText
    case noData
    case modelNotLoaded

    var localizedDescription: String {
        switch self {
        case .invalidImage:
            return "Invalid image data"
        case .noFeatures:
            return "No features extracted from image"
        case .emptyText:
            return "Text is empty"
        case .noData:
            return "No data provided for embedding"
        case .modelNotLoaded:
            return "ML model not loaded"
        }
    }
}

#if os(iOS)
import UIKit
#else
import AppKit
#endif
