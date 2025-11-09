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
    private let conceptualMemoryManager: ConceptualMemoryManager
    private let embeddingGenerator: EmbeddingGenerator
    private let agentCoordinator: AgentCoordinator

    // MARK: - Agents
    private let perceptionAgent: ProductionPerceptionAgent
    private let navigationAgent: NavigationAgent
    private let contextAgent: ContextAgent
    private let communicationAgent: CommunicationAgent

    // MARK: - State
    private var cancellables = Set<AnyCancellable>()
    private var processingQueue: [Observation] = []
    private var isProcessing = false

    // MARK: - Configuration
    private let processingInterval: TimeInterval = 1.0  // Process every 1 second

    // PERFORMANCE OPTIMIZATION: Queue-Limiting for Crash Prevention
    private let maxQueueSize = 10  // Hard limit to prevent memory crashes

    // MARK: - Initialization

    init() throws {
        // Initialize components
        let vectorDB = try HNSWVectorDatabase()
        self.memoryManager = MemoryManager(vectorDatabase: vectorDB)
        self.embeddingGenerator = try EmbeddingGenerator()
        self.conceptualMemoryManager = ConceptualMemoryManager(
            vectorDatabase: vectorDB,
            embeddingGenerator: self.embeddingGenerator
        )
        self.sensorManager = SensorManager()
        self.agentCoordinator = AgentCoordinator()

        // Initialize agents
        self.perceptionAgent = try ProductionPerceptionAgent(embeddingGenerator: embeddingGenerator)
        self.navigationAgent = NavigationAgent()
        self.contextAgent = ContextAgent(memoryManager: memoryManager)
        self.communicationAgent = CommunicationAgent()

        // Register agents
        agentCoordinator.register(perceptionAgent)
        agentCoordinator.register(navigationAgent)
        agentCoordinator.register(contextAgent)
        agentCoordinator.register(communicationAgent)
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
                guard let self = self else { return }

                // PERFORMANCE OPTIMIZATION: Backpressure - Drop old frames on overload
                if self.processingQueue.count >= self.maxQueueSize {
                    self.processingQueue.removeFirst()
                    print("⚠️ Dropping old observation - system overloaded")
                }

                Task { @MainActor in
                    await self.processObservation(observation)
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
            // PERFORMANCE OPTIMIZATION: Parallel Processing
            // Run Perception and Embedding generation in parallel using TaskGroup

            let (perceptionOutput, embedding, contextResults) = try await withThrowingTaskGroup(
                of: TaskResult.self,
                returning: (PerceptionOutput, [Float], [VectorEntry]).self
            ) { group in
                // Task 1: Perception - Process sensor data
                group.addTask {
                    let perceptionInput = PerceptionInput(
                        cameraFrame: observation.cameraImage,
                        depthData: observation.depthMap,
                        arFrame: nil,  // ARFrame is handled internally by SensorManager
                        timestamp: observation.timestamp
                    )
                    let output = try await self.perceptionAgent.process(perceptionInput)
                    return .perception(output)
                }

                // Task 2: Generate embedding (parallel to perception)
                group.addTask {
                    let emb = try await self.embeddingGenerator.generateEmbedding(from: observation)
                    return .embedding(emb)
                }

                // Collect parallel results
                var perceptionResult: PerceptionOutput?
                var embeddingResult: [Float]?

                for try await result in group {
                    switch result {
                    case .perception(let output):
                        perceptionResult = output
                    case .embedding(let emb):
                        embeddingResult = emb
                    case .context:
                        break // Not used in this phase
                    }
                }

                guard let perception = perceptionResult,
                      let emb = embeddingResult else {
                    throw TrinityError.notConfigured
                }

                // PERFORMANCE OPTIMIZATION: Intelligent filtering - only store important data
                var context: [VectorEntry] = []

                if self.shouldStore(observation, confidence: perception.confidence) {
                    // Store in memory (depends on embedding)
                    try await self.memoryManager.addObservation(observation, embedding: emb)

                    // Search for relevant context (depends on embedding)
                    context = try await self.memoryManager.search(embedding: emb, topK: 10)
                } else {
                    // Skip storage but still search for context with existing memories
                    context = try await self.memoryManager.search(embedding: emb, topK: 10)
                }

                return (perception, emb, context)
            }

            // SEQUENTIAL PROCESSING: Context → Navigation → Communication
            // These steps depend on each other and must run sequentially

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

    // MARK: - Task Result Type

    private enum TaskResult {
        case perception(PerceptionOutput)
        case embedding([Float])
        case context([VectorEntry])
    }

    // MARK: - Intelligent Filtering

    /// Determines whether an observation should be stored in memory
    /// Only stores high-confidence, important observations to prevent memory explosion
    private func shouldStore(_ observation: Observation, confidence: Float) -> Bool {
        // 1. Confidence threshold: Only store high-confidence detections
        guard confidence > 0.75 else {
            print("📊 Skipping observation: Low confidence (\(String(format: "%.2f", confidence)))")
            return false
        }

        // 2. Important object types: Filter out common background objects
        let importantLabels = ["person", "obstacle", "stairs", "door", "sign", "text", "vehicle", "animal"]
        let hasImportantObject = observation.detectedObjects.contains { object in
            importantLabels.contains { object.label.lowercased().contains($0) }
        }

        guard hasImportantObject else {
            print("📊 Skipping observation: No important objects detected")
            return false
        }

        // 3. Spatial uniqueness: Check if significantly different from recent observations
        // (This would compare against last few stored observations - simplified for now)

        return true
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
        return try await memoryManager.vectorDatabase.exportToiCloud()
    }

    func importMemories(from url: URL) async throws {
        try await memoryManager.vectorDatabase.importFromiCloud(bundleURL: url)
        try await memoryManager.loadMemories()
    }

    // MARK: - Conceptual Memory API

    /// Add a thought with automatic linking to current location
    func addThought(
        _ content: String,
        category: ThoughtMemory.ThoughtCategory,
        importance: Float = 0.5,
        emotionalTone: ThoughtMemory.EmotionalTone? = nil
    ) async throws {
        let currentLocation = sensorManager.currentLocation?.coordinate

        try await conceptualMemoryManager.addThought(
            content: content,
            category: category,
            importance: importance,
            linkedLocation: currentLocation,
            emotionalTone: emotionalTone
        )

        print("💭 Thought added: \(content.prefix(50))...")
    }

    /// Add a conversation with redundancy reduction
    func addConversation(
        participants: [String],
        messages: [ConversationMemory.Message],
        summary: String,
        keyTopics: [String],
        keyInsights: [String],
        importance: Float = 0.5
    ) async throws {
        let currentLocation = sensorManager.currentLocation?.coordinate

        try await conceptualMemoryManager.addConversation(
            participants: participants,
            messages: messages,
            summary: summary,
            keyTopics: keyTopics,
            keyInsights: keyInsights,
            location: currentLocation,
            importance: importance
        )

        print("💬 Conversation added: \(keyTopics.joined(separator: ", "))")
    }

    /// Add an idea with evolution tracking
    func addIdea(
        title: String,
        description: String,
        tags: [String],
        importance: Float = 0.6
    ) async throws {
        try await conceptualMemoryManager.addIdea(
            title: title,
            description: description,
            tags: tags,
            importance: importance
        )

        print("💡 Idea added: \(title)")
    }

    /// Add a note or reminder
    func addNote(
        title: String,
        content: String,
        tags: [String] = [],
        isReminder: Bool = false,
        reminderDate: Date? = nil
    ) async throws {
        let currentLocation = sensorManager.currentLocation?.coordinate

        try await conceptualMemoryManager.addNote(
            title: title,
            content: content,
            tags: tags,
            isReminder: isReminder,
            reminderDate: reminderDate,
            linkedLocation: currentLocation
        )

        print("📝 Note added: \(title)")
    }

    /// Add a plan or appointment
    func addPlan(
        title: String,
        description: String,
        scheduledDate: Date,
        participants: [String]? = nil,
        tags: [String] = []
    ) async throws {
        let currentLocation = sensorManager.currentLocation?.coordinate

        try await conceptualMemoryManager.addPlan(
            title: title,
            description: description,
            scheduledDate: scheduledDate,
            location: currentLocation,
            participants: participants,
            tags: tags
        )

        print("📅 Plan added: \(title)")
    }

    /// Search thoughts by content
    func searchThoughts(query: String, limit: Int = 10) async throws -> [ThoughtMemory] {
        return try await conceptualMemoryManager.searchThoughts(query: query, limit: limit)
    }

    /// Search conversations by topic
    func searchConversations(query: String, limit: Int = 10) async throws -> [ConversationMemory] {
        return try await conceptualMemoryManager.searchConversations(query: query, limit: limit)
    }

    /// Search ideas
    func searchIdeas(query: String, limit: Int = 10) async throws -> [IdeaMemory] {
        return try await conceptualMemoryManager.searchIdeas(query: query, limit: limit)
    }

    /// Mark idea as implemented
    func markIdeaImplemented(_ ideaId: UUID) {
        conceptualMemoryManager.markIdeaImplemented(ideaId)
    }

    /// Mark plan as completed
    func markPlanCompleted(_ planId: UUID) {
        conceptualMemoryManager.markPlanCompleted(planId)
    }

    /// Get conceptual memory statistics
    func getConceptualMemoryStatistics() -> ConceptualMemoryStatistics {
        return conceptualMemoryManager.getStatistics()
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
        let conceptualStats = conceptualMemoryManager.getStatistics()

        return SystemStatistics(
            totalObservations: processingQueue.count,
            workingMemorySize: memoryManager.workingMemory.count,
            episodicMemorySize: memoryManager.episodicMemory.count,
            semanticMemorySize: memoryManager.semanticMemory.count,
            conceptualMemories: conceptualStats.totalMemories,
            totalThoughts: conceptualStats.totalThoughts,
            totalConversations: conceptualStats.totalConversations,
            totalIdeas: conceptualStats.totalIdeas,
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
    let conceptualMemories: Int
    let totalThoughts: Int
    let totalConversations: Int
    let totalIdeas: Int
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
