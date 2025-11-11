//
//  TrinityCoordinator.swift
//  TRINITY Vision Aid
//
//  Main coordinator that orchestrates all system components
//

import Foundation
import Combine
import CoreLocation

/// Main coordinator for the TRINITY system
@MainActor
class TrinityCoordinator: ObservableObject {
    // MARK: - Published Properties
    @Published var isRunning = false
    @Published var currentStatus: SystemStatus = .idle
    @Published var lastSpokenMessage: String = ""

    // MARK: - Components
    private let sensorManager: SensorManager
    private let memoryManager: MemoryManager
    private let embeddingGenerator: EmbeddingGenerator
    private let vectorDatabase: VectorDatabase
    private let agentCoordinator: AgentCoordinator

    // MARK: - Agents
    private let perceptionAgent: PerceptionAgent
    private let navigationAgent: NavigationAgent
    private let contextAgent: ContextAgent
    private let communicationAgent: CommunicationAgent
    private let ragAgent: RAGAgent

    // MARK: - State
    private var cancellables = Set<AnyCancellable>()
    private var processingQueue: [Observation] = []
    private var isProcessing = false

    // MARK: - Configuration
    private let processingInterval: TimeInterval = 1.0  // Process every 1 second

    // MARK: - Initialization

    init() throws {
        // Initialize components
        let vectorDB = try VectorDatabase()
        self.vectorDatabase = vectorDB
        self.memoryManager = MemoryManager(vectorDatabase: vectorDB)
        self.embeddingGenerator = try EmbeddingGenerator()
        self.sensorManager = SensorManager()
        self.agentCoordinator = AgentCoordinator()

        // Initialize agents
        self.perceptionAgent = try PerceptionAgent(embeddingGenerator: embeddingGenerator)
        self.navigationAgent = NavigationAgent()
        self.contextAgent = ContextAgent(memoryManager: memoryManager)
        self.communicationAgent = CommunicationAgent()
        self.ragAgent = RAGAgent(
            memoryManager: memoryManager,
            embeddingGenerator: embeddingGenerator,
            vectorDatabase: vectorDB,
            contextAgent: contextAgent
        )

        // Register agents
        agentCoordinator.register(perceptionAgent)
        agentCoordinator.register(navigationAgent)
        agentCoordinator.register(contextAgent)
        agentCoordinator.register(communicationAgent)
        agentCoordinator.register(ragAgent)
    }

    // MARK: - System Control

    func start() async throws {
        guard !isRunning else { return }

        // Check permissions
        guard sensorManager.checkPermissions() else {
            let granted = await sensorManager.requestPermissions()
            guard granted else {
                throw TrinityError.permissionsNotGranted
            }
        }

        // Configure sensors
        try sensorManager.configure()

        // Load existing memories
        try await memoryManager.loadMemories()

        // Start sensor session
        sensorManager.startSession()

        // Subscribe to observations
        subscribeToObservations()

        isRunning = true
        currentStatus = .running
    }

    func stop() async {
        guard isRunning else { return }

        // Stop sensor session
        sensorManager.pauseSession()

        // Save memories
        try? await memoryManager.saveMemories()

        // Stop speech
        communicationAgent.stopSpeaking()

        isRunning = false
        currentStatus = .idle
    }

    // MARK: - Observation Processing

    private func subscribeToObservations() {
        sensorManager.observationPublisher
            .sink { [weak self] observation in
                Task { @MainActor in
                    await self?.processObservation(observation)
                }
            }
            .store(in: &cancellables)
    }

    private func processObservation(_ observation: Observation) async {
        guard isRunning, !isProcessing else {
            processingQueue.append(observation)
            return
        }

        isProcessing = true
        currentStatus = .processing

        do {
            // Step 1: Perception - Process sensor data
            let perceptionInput = PerceptionInput(
                cameraFrame: observation.cameraImage,
                depthData: observation.depthMap,
                arFrame: nil,  // ARFrame is handled internally by SensorManager
                timestamp: observation.timestamp
            )

            let perceptionOutput = try await perceptionAgent.process(perceptionInput)

            // Step 2: Generate embedding
            let embedding = try await embeddingGenerator.generateEmbedding(from: observation)

            // Step 3: Store in memory
            try await memoryManager.addObservation(observation, embedding: embedding)

            // Step 4: Search for relevant context
            let contextResults = try await memoryManager.search(embedding: embedding, topK: 10)

            // Step 5: Context - Assemble contextual information
            let contextInput = ContextInput(
                currentObservation: observation,
                query: nil,
                memorySearchResults: contextResults
            )

            let contextOutput = try await contextAgent.process(contextInput)

            // Step 6: Navigation - Generate navigation guidance
            let navigationInput = NavigationInput(
                currentLocation: observation.location,
                destination: nil,  // Could be set by user
                spatialMap: perceptionOutput.spatialMap,
                detectedObjects: observation.detectedObjects,
                userHeading: sensorManager.currentHeading
            )

            let navigationOutput = try await navigationAgent.process(navigationInput)

            // Step 7: Communication - Generate user-friendly output
            let communicationInput = CommunicationInput(
                perceptionOutput: perceptionOutput,
                navigationOutput: navigationOutput,
                contextOutput: contextOutput,
                priority: determineMessagePriority(navigationOutput)
            )

            let communicationOutput = try await communicationAgent.process(communicationInput)

            // Step 8: Deliver output to user
            await deliverOutput(communicationOutput)

            currentStatus = .idle

        } catch {
            print("Error processing observation: \(error)")
            currentStatus = .error(error)
        }

        isProcessing = false

        // Process queued observations
        if !processingQueue.isEmpty {
            let nextObservation = processingQueue.removeFirst()
            await processObservation(nextObservation)
        }
    }

    private func determineMessagePriority(_ navigation: NavigationOutput) -> MessagePriority {
        // Determine priority based on safety warnings
        if !navigation.safetyWarnings.isEmpty {
            let maxSeverity = navigation.safetyWarnings.map { $0.severity }.max()
            switch maxSeverity {
            case .critical:
                return .critical
            case .high:
                return .high
            case .medium:
                return .normal
            default:
                return .low
            }
        }

        return .normal
    }

    private func deliverOutput(_ output: CommunicationOutput) async {
        // Speak the message
        communicationAgent.speak(output.spokenMessage)
        lastSpokenMessage = output.spokenMessage

        // Trigger haptic feedback
        if let haptic = output.hapticFeedback {
            triggerHapticFeedback(haptic)
        }

        // Play audio feedback
        if let audio = output.audioFeedback {
            playAudioFeedback(audio)
        }
    }

    // MARK: - User Commands

    func describeCurrentScene() async {
        guard let observation = sensorManager.captureCurrentObservation() else {
            communicationAgent.speak("No sensor data available")
            return
        }

        await processObservation(observation)
    }

    func navigateTo(destination: CLLocation) async {
        // Set navigation destination
        // This would be integrated with the navigation agent
        communicationAgent.speak("Navigation to destination started")
    }

    func repeatLastMessage() {
        communicationAgent.speak(lastSpokenMessage)
    }

    func adjustVerbosity(_ level: CommunicationAgent.VerbosityLevel) {
        communicationAgent.setVerbosity(level)
    }

    // MARK: - RAG (Retrieval-Augmented Generation)

    /// Process a natural language query using RAG
    func askQuestion(
        _ query: String,
        maxContextItems: Int = 10,
        memoryLayers: [MemoryLayerType]? = nil
    ) async throws -> RAGOutput {
        guard isRunning else {
            throw TrinityError.notRunning
        }

        currentStatus = .processing

        do {
            // Generate query embedding
            let queryEmbedding = try await embeddingGenerator.generateEmbedding(from: query)

            // Create RAG input
            let ragInput = RAGInput(
                query: query,
                queryEmbedding: queryEmbedding,
                maxContextItems: maxContextItems,
                memoryLayers: memoryLayers,
                includeCurrentObservation: true
            )

            // Process through RAG agent
            let ragOutput = try await ragAgent.process(ragInput)

            // Speak the answer
            communicationAgent.speak(ragOutput.answer)
            lastSpokenMessage = ragOutput.answer

            currentStatus = .idle
            return ragOutput

        } catch {
            currentStatus = .error(error)
            throw error
        }
    }

    /// Ask a question with current observation context
    func askQuestionWithContext(
        _ query: String,
        currentObservation: Observation? = nil
    ) async throws -> RAGOutput {
        // If no observation provided, try to capture current one
        let observation = currentObservation ?? sensorManager.captureCurrentObservation()

        // Generate embedding for current observation if available
        var queryEmbedding: [Float]?
        if let observation = observation {
            queryEmbedding = try? await embeddingGenerator.generateEmbedding(from: observation)
        }

        // Create RAG input with observation context
        let ragInput = RAGInput(
            query: query,
            queryEmbedding: queryEmbedding,
            maxContextItems: 15,
            memoryLayers: nil, // Search all layers
            includeCurrentObservation: observation != nil
        )

        return try await ragAgent.process(ragInput)
    }

    // MARK: - Memory Management

    func consolidateMemories() async {
        currentStatus = .consolidatingMemory

        await memoryManager.consolidateEpisodicMemory()

        currentStatus = .idle
    }

    func clearAllMemories() {
        memoryManager.clearAllMemories()
    }

    func exportMemories() async throws -> URL {
        return try await vectorDatabase.exportToiCloud()
    }

    func importMemories(from url: URL) async throws {
        try await vectorDatabase.importFromiCloud(bundleURL: url)
        try await memoryManager.loadMemories()
    }

    // MARK: - Feedback

    private func triggerHapticFeedback(_ pattern: HapticPattern) {
        #if os(iOS)
        import UIKit

        let generator: UIFeedbackGenerator

        switch pattern {
        case .success:
            generator = UINotificationFeedbackGenerator()
            (generator as! UINotificationFeedbackGenerator).notificationOccurred(.success)
        case .warning:
            generator = UINotificationFeedbackGenerator()
            (generator as! UINotificationFeedbackGenerator).notificationOccurred(.warning)
        case .error:
            generator = UINotificationFeedbackGenerator()
            (generator as! UINotificationFeedbackGenerator).notificationOccurred(.error)
        case .navigationLeft, .navigationRight:
            generator = UISelectionFeedbackGenerator()
            (generator as! UISelectionFeedbackGenerator).selectionChanged()
        case .obstacleNear:
            generator = UIImpactFeedbackGenerator(style: .heavy)
            (generator as! UIImpactFeedbackGenerator).impactOccurred()
        case .obstacleFar:
            generator = UIImpactFeedbackGenerator(style: .light)
            (generator as! UIImpactFeedbackGenerator).impactOccurred()
        }
        #endif
    }

    private func playAudioFeedback(_ feedback: AudioFeedback) {
        // Implementation for spatial audio feedback
        // Would use AVAudioEngine for 3D audio positioning
    }

    // MARK: - Statistics

    func getSystemStatistics() async throws -> SystemStatistics {
        let dbStats = try await memoryManager.vectorDatabase.getStatistics()

        return SystemStatistics(
            totalObservations: processingQueue.count,
            workingMemorySize: memoryManager.workingMemory.count,
            episodicMemorySize: memoryManager.episodicMemory.count,
            semanticMemorySize: memoryManager.semanticMemory.count,
            isRunning: isRunning,
            currentStatus: currentStatus
        )
    }
}

// MARK: - Supporting Types

enum SystemStatus: Equatable {
    case idle
    case running
    case processing
    case consolidatingMemory
    case error(Error)

    static func == (lhs: SystemStatus, rhs: SystemStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.running, .running),
             (.processing, .processing),
             (.consolidatingMemory, .consolidatingMemory):
            return true
        case (.error, .error):
            return true
        default:
            return false
        }
    }

    var description: String {
        switch self {
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .processing:
            return "Processing"
        case .consolidatingMemory:
            return "Consolidating Memory"
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        }
    }
}

struct SystemStatistics {
    let totalObservations: Int
    let workingMemorySize: Int
    let episodicMemorySize: Int
    let semanticMemorySize: Int
    let isRunning: Bool
    let currentStatus: SystemStatus
}

enum TrinityError: Error {
    case permissionsNotGranted
    case notConfigured
    case alreadyRunning
    case notRunning

    var localizedDescription: String {
        switch self {
        case .permissionsNotGranted:
            return "Required permissions were not granted"
        case .notConfigured:
            return "System is not configured"
        case .alreadyRunning:
            return "System is already running"
        case .notRunning:
            return "System is not running"
        }
    }
}

#if os(iOS)
import UIKit
#endif
