//
//  UnifiedCloudManager.swift
//  TRINITY Vision Aid
//
//  Unified manager for all cloud APIs with model selection and intelligent caching
//

import Foundation
import UIKit

/// Manages all cloud APIs with unified interface
@MainActor
class UnifiedCloudManager: ObservableObject {

    // MARK: - API Clients

    private var openAIClient: OpenAIClient?
    private var claudeClient: AnthropicClient?
    private var perplexityClient: PerplexityClient?

    // MARK: - Configuration

    @Published var selectedProvider: APIProvider = .local
    @Published var selectedModel: String = ""

    enum APIProvider: String, CaseIterable, Identifiable {
        case local = "Lokal (On-Device)"
        case openAI = "OpenAI"
        case anthropic = "Anthropic Claude"
        case perplexity = "Perplexity"

        var id: String { rawValue }

        var displayName: String { rawValue }

        var icon: String {
            switch self {
            case .local: return "iphone"
            case .openAI: return "brain"
            case .anthropic: return "sparkles"
            case .perplexity: return "magnifyingglass"
            }
        }
    }

    // MARK: - Available Models per Provider

    func availableModels(for provider: APIProvider) -> [CloudModel] {
        switch provider {
        case .local:
            return [
                CloudModel(
                    id: "vision-framework",
                    name: "Vision Framework",
                    provider: .local,
                    capabilities: [.vision, .objectDetection],
                    costPer1kTokens: 0.0
                ),
                CloudModel(
                    id: "core-ml",
                    name: "Core ML",
                    provider: .local,
                    capabilities: [.embedding],
                    costPer1kTokens: 0.0
                )
            ]

        case .openAI:
            return [
                CloudModel(
                    id: "gpt-4-vision-preview",
                    name: "GPT-4 Vision",
                    provider: .openAI,
                    capabilities: [.vision, .chat, .reasoning],
                    costPer1kTokens: 0.01
                ),
                CloudModel(
                    id: "gpt-4",
                    name: "GPT-4",
                    provider: .openAI,
                    capabilities: [.chat, .reasoning],
                    costPer1kTokens: 0.03
                ),
                CloudModel(
                    id: "gpt-3.5-turbo",
                    name: "GPT-3.5 Turbo",
                    provider: .openAI,
                    capabilities: [.chat],
                    costPer1kTokens: 0.001
                )
            ]

        case .anthropic:
            return [
                CloudModel(
                    id: "claude-3-5-sonnet-20241022",
                    name: "Claude 3.5 Sonnet",
                    provider: .anthropic,
                    capabilities: [.vision, .chat, .reasoning, .longContext],
                    costPer1kTokens: 0.003
                ),
                CloudModel(
                    id: "claude-3-opus",
                    name: "Claude 3 Opus",
                    provider: .anthropic,
                    capabilities: [.vision, .chat, .reasoning],
                    costPer1kTokens: 0.015
                ),
                CloudModel(
                    id: "claude-3-haiku",
                    name: "Claude 3 Haiku",
                    provider: .anthropic,
                    capabilities: [.chat],
                    costPer1kTokens: 0.00025
                )
            ]

        case .perplexity:
            return [
                CloudModel(
                    id: "sonar-pro",
                    name: "Sonar Pro",
                    provider: .perplexity,
                    capabilities: [.webSearch, .chat, .citations],
                    costPer1kTokens: 0.001
                ),
                CloudModel(
                    id: "sonar",
                    name: "Sonar",
                    provider: .perplexity,
                    capabilities: [.webSearch, .chat],
                    costPer1kTokens: 0.0005
                ),
                CloudModel(
                    id: "sonar-small-online",
                    name: "Sonar Small",
                    provider: .perplexity,
                    capabilities: [.webSearch, .chat],
                    costPer1kTokens: 0.0002
                )
            ]
        }
    }

    // MARK: - Initialization

    init() {
        loadConfiguration()
    }

    func configure() {
        // Initialize API clients
        if let openAIKey = Configuration.shared.openAIKey {
            openAIClient = OpenAIClient(apiKey: openAIKey)
        }

        if let claudeKey = Configuration.shared.claudeKey {
            claudeClient = AnthropicClient(apiKey: claudeKey)
        }

        if let perplexityKey = Configuration.shared.perplexityKey {
            perplexityClient = PerplexityClient(apiKey: perplexityKey)
        }
    }

    private func loadConfiguration() {
        selectedProvider = APIProvider(
            rawValue: UserDefaults.standard.string(forKey: "selected_provider") ?? "Lokal (On-Device)"
        ) ?? .local

        selectedModel = UserDefaults.standard.string(forKey: "selected_model") ?? ""
    }

    func saveConfiguration() {
        UserDefaults.standard.set(selectedProvider.rawValue, forKey: "selected_provider")
        UserDefaults.standard.set(selectedModel, forKey: "selected_model")
    }

    // MARK: - Unified Vision Analysis

    /// Analysiert Bild mit gewähltem Provider/Model
    func analyzeImage(
        _ imageData: Data,
        prompt: String,
        useCache: Bool = true
    ) async throws -> VisionAnalysisResult {

        // 1. Check Cache first
        if useCache {
            if let cached = try await CacheManager.shared.getCachedVisionResult(
                imageHash: imageData.hashValue,
                prompt: prompt,
                model: selectedModel
            ) {
                print("💾 Cache HIT for vision analysis")
                return cached
            }
        }

        // 2. Perform analysis
        let result: VisionAnalysisResult

        switch selectedProvider {
        case .local:
            result = try await analyzeImageLocal(imageData, prompt: prompt)

        case .openAI:
            guard let client = openAIClient else {
                throw CloudError.clientNotConfigured
            }
            let description = try await client.describeImage(imageData, prompt: prompt)
            result = VisionAnalysisResult(
                description: description,
                confidence: 0.9,
                citations: [],
                provider: .openAI,
                model: selectedModel,
                cached: false
            )

        case .anthropic:
            guard let client = claudeClient else {
                throw CloudError.clientNotConfigured
            }
            let analysis = try await client.analyzeScene(imageData, context: prompt)
            result = VisionAnalysisResult(
                description: analysis.sceneDescription,
                confidence: 0.95,
                objects: analysis.objects.map { $0.name },
                citations: [],
                provider: .anthropic,
                model: selectedModel,
                cached: false
            )

        case .perplexity:
            // Perplexity kann keine Bilder direkt, aber wir können Text-Kontext nutzen
            throw CloudError.unsupportedOperation
        }

        // 3. Cache result
        if useCache {
            try await CacheManager.shared.cacheVisionResult(
                imageHash: imageData.hashValue,
                prompt: prompt,
                model: selectedModel,
                result: result
            )
        }

        return result
    }

    // MARK: - Unified Chat/Query

    /// Chat/Query mit gewähltem Provider
    func query(
        _ prompt: String,
        context: [String] = [],
        useCache: Bool = true,
        includeWebSearch: Bool = false
    ) async throws -> QueryResult {

        // 1. Check Cache
        if useCache {
            if let cached = try await CacheManager.shared.getCachedQueryResult(
                prompt: prompt,
                context: context,
                model: selectedModel
            ) {
                print("💾 Cache HIT for query")
                return cached
            }
        }

        // 2. Perform query
        let result: QueryResult

        switch selectedProvider {
        case .local:
            // Lokale Antwort basierend auf RAG
            result = try await queryLocal(prompt, context: context)

        case .openAI:
            guard let client = openAIClient else {
                throw CloudError.clientNotConfigured
            }

            let contextText = context.isEmpty ? "" : "\nKontext:\n" + context.joined(separator: "\n")
            let fullPrompt = prompt + contextText

            // Hier würde man den Chat nutzen
            let response = "OpenAI Response" // Placeholder
            result = QueryResult(
                answer: response,
                confidence: 0.85,
                citations: [],
                provider: .openAI,
                model: selectedModel,
                cached: false
            )

        case .anthropic:
            guard let client = claudeClient else {
                throw CloudError.clientNotConfigured
            }

            let response = try await client.generateContextualNavigation(
                currentObservation: prompt,
                recentHistory: context,
                knownLocation: nil
            )

            result = QueryResult(
                answer: response,
                confidence: 0.9,
                citations: [],
                provider: .anthropic,
                model: selectedModel,
                cached: false
            )

        case .perplexity:
            guard let client = perplexityClient else {
                throw CloudError.clientNotConfigured
            }

            let messages = [ChatMessage(role: .user, content: prompt)]
            let response = try await client.chat(messages: messages)

            result = QueryResult(
                answer: response.content,
                confidence: 0.95,
                citations: response.citations,
                provider: .perplexity,
                model: selectedModel,
                cached: false,
                webGrounded: true
            )
        }

        // 3. Cache result
        if useCache {
            try await CacheManager.shared.cacheQueryResult(
                prompt: prompt,
                context: context,
                model: selectedModel,
                result: result
            )
        }

        return result
    }

    // MARK: - Location-Specific

    /// Holt Informationen zu einem Ort
    func getLocationInfo(
        _ locationName: String,
        query: String = "Allgemeine Informationen, Barrierefreiheit, Navigation"
    ) async throws -> LocationInfoResult {

        // Bevorzuge Perplexity für aktuelle Web-Daten
        if selectedProvider == .perplexity, let client = perplexityClient {
            let response = try await client.searchLocation(
                locationName,
                query: query
            )

            return LocationInfoResult(
                locationName: locationName,
                information: response.content,
                citations: response.citations,
                provider: .perplexity
            )
        }

        // Fallback zu anderen Providern
        let prompt = "Informationen zu '\(locationName)': \(query)"
        let result = try await self.query(prompt)

        return LocationInfoResult(
            locationName: locationName,
            information: result.answer,
            citations: result.citations,
            provider: selectedProvider
        )
    }

    // MARK: - Local Processing

    private func analyzeImageLocal(
        _ imageData: Data,
        prompt: String
    ) async throws -> VisionAnalysisResult {
        // Nutze lokales Vision Framework
        // Placeholder - würde echte Vision-Analyse nutzen

        return VisionAnalysisResult(
            description: "Lokale Vision-Analyse (Placeholder)",
            confidence: 0.7,
            citations: [],
            provider: .local,
            model: "vision-framework",
            cached: false
        )
    }

    private func queryLocal(
        _ prompt: String,
        context: [String]
    ) async throws -> QueryResult {
        // Nutze RAG + lokale Memories
        // Placeholder

        return QueryResult(
            answer: "Lokale RAG Antwort (Placeholder)",
            confidence: 0.8,
            citations: [],
            provider: .local,
            model: "rag-system",
            cached: false
        )
    }

    // MARK: - Statistics

    func getUsageStatistics() -> APIUsageStatistics {
        return APIUsageStatistics(
            totalRequests: CacheManager.shared.totalRequests,
            cachedRequests: CacheManager.shared.cacheHits,
            cacheHitRate: CacheManager.shared.cacheHitRate,
            estimatedCostSaved: CacheManager.shared.estimatedCostSaved,
            providerBreakdown: [:] // TODO: Track per provider
        )
    }
}

// MARK: - Data Models

struct CloudModel {
    let id: String
    let name: String
    let provider: UnifiedCloudManager.APIProvider
    let capabilities: [Capability]
    let costPer1kTokens: Double

    enum Capability {
        case vision
        case chat
        case reasoning
        case webSearch
        case citations
        case embedding
        case objectDetection
        case longContext
    }

    var costDescription: String {
        if costPer1kTokens == 0 {
            return "Kostenlos"
        } else {
            return "$\(String(format: "%.4f", costPer1kTokens))/1k tokens"
        }
    }
}

struct VisionAnalysisResult {
    let description: String
    let confidence: Float
    var objects: [String] = []
    let citations: [String]
    let provider: UnifiedCloudManager.APIProvider
    let model: String
    let cached: Bool
    var timestamp: Date = Date()
}

struct QueryResult {
    let answer: String
    let confidence: Float
    let citations: [String]
    let provider: UnifiedCloudManager.APIProvider
    let model: String
    let cached: Bool
    var webGrounded: Bool = false
    var timestamp: Date = Date()
}

struct LocationInfoResult {
    let locationName: String
    let information: String
    let citations: [String]
    let provider: UnifiedCloudManager.APIProvider
}

struct APIUsageStatistics {
    let totalRequests: Int
    let cachedRequests: Int
    let cacheHitRate: Float
    let estimatedCostSaved: Double
    let providerBreakdown: [String: Int]
}

enum CloudError: Error {
    case clientNotConfigured
    case unsupportedOperation
    case cacheError

    var localizedDescription: String {
        switch self {
        case .clientNotConfigured: return "API Client nicht konfiguriert"
        case .unsupportedOperation: return "Operation nicht unterstützt"
        case .cacheError: return "Cache Fehler"
        }
    }
}

// MARK: - Configuration Extension

extension Configuration {
    var perplexityKey: String? {
        get { UserDefaults.standard.string(forKey: "perplexity_api_key") }
        set { UserDefaults.standard.set(newValue, forKey: "perplexity_api_key") }
    }

    func hasValidPerplexityKey() -> Bool {
        guard let key = perplexityKey else { return false }
        return key.hasPrefix("pplx-") && key.count > 20
    }
}
