//
//  CommunicationAgent.swift
//  TRINITY Vision Aid
//
//  Agent responsible for generating natural language descriptions and audio feedback
//

import Foundation
import AVFoundation

/// Input for communication agent
struct CommunicationInput {
    let perceptionOutput: PerceptionOutput?
    let navigationOutput: NavigationOutput?
    let contextOutput: ContextOutput?
    let priority: MessagePriority
}

/// Output from communication agent
struct CommunicationOutput {
    let spokenMessage: String
    let detailedDescription: String
    let hapticFeedback: HapticPattern?
    let audioFeedback: AudioFeedback?
}

enum HapticPattern {
    case success
    case warning
    case error
    case navigationLeft
    case navigationRight
    case obstacleNear
    case obstacleFar
}

struct AudioFeedback {
    let type: AudioType
    let volume: Float
    let spatial: SpatialAudio?
}

enum AudioType {
    case beep
    case chime
    case warning
    case notification
}

struct SpatialAudio {
    let direction: Direction
    let distance: Float
}

/// Agent that generates user-friendly communication
class CommunicationAgent: BaseAgent<CommunicationInput, CommunicationOutput> {
    // PERFORMANCE OPTIMIZATION: Non-Blocking Speech
    private let synthesizer = AVSpeechSynthesizer()
    private let speechQueue = DispatchQueue(label: "com.trinity.speech", qos: .userInteractive)
    private var isSpeaking = false

    // Priority Queue for messages
    private var messageQueue: PriorityQueue<SpeechMessage> = PriorityQueue()
    private let queueLock = NSLock()

    // SAFETY: Limit queue size to prevent memory leaks
    private let maxQueueSize = 20

    // Verbosity settings
    private var verbosityLevel: VerbosityLevel = .medium

    enum VerbosityLevel {
        case minimal  // Only critical info
        case medium   // Balanced
        case detailed // Everything
    }

    init() {
        super.init(name: "CommunicationAgent")
        synthesizer.delegate = SpeechDelegate(agent: self)
    }

    override func process(_ input: CommunicationInput) async throws -> CommunicationOutput {
        // Generate spoken message based on priority and inputs
        let spokenMessage = generateSpokenMessage(
            perception: input.perceptionOutput,
            navigation: input.navigationOutput,
            context: input.contextOutput,
            priority: input.priority
        )

        // Generate detailed description
        let detailedDescription = generateDetailedDescription(
            perception: input.perceptionOutput,
            navigation: input.navigationOutput,
            context: input.contextOutput
        )

        // Generate haptic feedback
        let hapticFeedback = generateHapticFeedback(
            navigation: input.navigationOutput
        )

        // Generate audio feedback
        let audioFeedback = generateAudioFeedback(
            navigation: input.navigationOutput,
            priority: input.priority
        )

        return CommunicationOutput(
            spokenMessage: spokenMessage,
            detailedDescription: detailedDescription,
            hapticFeedback: hapticFeedback,
            audioFeedback: audioFeedback
        )
    }

    // MARK: - Message Generation

    private func generateSpokenMessage(
        perception: PerceptionOutput?,
        navigation: NavigationOutput?,
        context: ContextOutput?,
        priority: MessagePriority
    ) -> String {
        var message = ""

        // Priority 1: Critical safety warnings
        if let navigation = navigation,
           !navigation.safetyWarnings.isEmpty {
            let criticalWarnings = navigation.safetyWarnings
                .filter { $0.severity >= .high }
                .sorted { $0.severity > $1.severity }

            if let warning = criticalWarnings.first {
                return warning.message  // Only critical warning
            }
        }

        // Priority 2: Navigation instructions
        if let navigation = navigation,
           !navigation.instructions.isEmpty {
            let primaryInstruction = navigation.instructions
                .sorted { $0.priority > $1.priority }
                .first!

            message += primaryInstruction.audioDescription
        }

        // Priority 3: Scene description (if not navigating)
        if message.isEmpty, let perception = perception {
            switch verbosityLevel {
            case .minimal:
                message = generateMinimalDescription(perception)
            case .medium:
                message = generateMediumDescription(perception)
            case .detailed:
                message = generateDetailedSceneDescription(perception)
            }
        }

        // Add context if available and relevant
        if verbosityLevel == .detailed,
           let context = context,
           !context.contextSummary.isEmpty {
            message += ". " + context.contextSummary
        }

        return message.isEmpty ? "No significant information" : message
    }

    private func generateMinimalDescription(_ perception: PerceptionOutput) -> String {
        if perception.detectedObjects.isEmpty {
            return "Clear"
        }

        let topObject = perception.detectedObjects
            .sorted { $0.confidence > $1.confidence }
            .first!

        return "\(topObject.label.capitalized) ahead"
    }

    private func generateMediumDescription(_ perception: PerceptionOutput) -> String {
        if perception.detectedObjects.isEmpty {
            return "No obstacles detected"
        }

        let topObjects = perception.detectedObjects
            .sorted { $0.confidence > $1.confidence }
            .prefix(3)

        if topObjects.count == 1 {
            return "I see a \(topObjects.first!.label)"
        } else if topObjects.count == 2 {
            return "I see a \(topObjects[0].label) and a \(topObjects[1].label)"
        } else {
            let first = topObjects.dropLast().map { $0.label }.joined(separator: ", ")
            return "I see \(first), and a \(topObjects.last!.label)"
        }
    }

    private func generateDetailedSceneDescription(_ perception: PerceptionOutput) -> String {
        var description = perception.sceneDescription

        // Add spatial information if available
        if let spatialMap = perception.spatialMap {
            if !spatialMap.planes.isEmpty {
                description += ". "
                description += describeSpace(spatialMap)
            }
        }

        // Add confidence qualifier
        if perception.confidence < 0.7 {
            description += ". I'm not entirely certain about this"
        }

        return description
    }

    private func describeSpace(_ spatialMap: SpatialMap) -> String {
        let planes = spatialMap.planes

        let walls = planes.filter { $0.alignment == .vertical }.count
        let floors = planes.filter {
            $0.alignment == .horizontal && $0.center.y < -0.5
        }.count

        var description = "The space has "

        if walls > 0 {
            description += "\(walls) wall\(walls == 1 ? "" : "s")"
        }

        if floors > 0 {
            if walls > 0 {
                description += " and "
            }
            description += "\(floors) floor surface\(floors == 1 ? "" : "s")"
        }

        return description
    }

    private func generateDetailedDescription(
        perception: PerceptionOutput?,
        navigation: NavigationOutput?,
        context: ContextOutput?
    ) -> String {
        var details: [String] = []

        // Perception details
        if let perception = perception {
            details.append("Scene: \(perception.sceneDescription)")
            details.append("Confidence: \(Int(perception.confidence * 100))%")
            details.append("Objects: \(perception.detectedObjects.count)")
        }

        // Navigation details
        if let navigation = navigation {
            details.append("Obstacles: \(navigation.obstacles.count)")

            if let distance = navigation.estimatedDistance {
                details.append("Distance to destination: \(Int(distance))m")
            }
        }

        // Context details
        if let context = context {
            details.append("Context: \(context.contextSummary)")
        }

        return details.joined(separator: "\n")
    }

    // MARK: - Haptic Feedback

    private func generateHapticFeedback(
        navigation: NavigationOutput?
    ) -> HapticPattern? {
        guard let navigation = navigation else { return nil }

        // Critical obstacles
        if let warning = navigation.safetyWarnings.first(where: { $0.severity == .critical }) {
            return .error
        }

        // High priority warnings
        if let warning = navigation.safetyWarnings.first(where: { $0.severity == .high }) {
            return .warning
        }

        // Navigation guidance
        if let instruction = navigation.instructions.first {
            switch instruction.direction {
            case .left:
                return .navigationLeft
            case .right:
                return .navigationRight
            default:
                return nil
            }
        }

        // Nearby obstacles
        let nearbyObstacles = navigation.obstacles.filter { $0.distance < 2.0 }
        if !nearbyObstacles.isEmpty {
            return .obstacleNear
        }

        return nil
    }

    // MARK: - Audio Feedback

    private func generateAudioFeedback(
        navigation: NavigationOutput?,
        priority: MessagePriority
    ) -> AudioFeedback? {
        guard let navigation = navigation else { return nil }

        // Critical warnings get audio beep
        if !navigation.safetyWarnings.filter({ $0.severity == .critical }).isEmpty {
            return AudioFeedback(
                type: .warning,
                volume: 1.0,
                spatial: nil
            )
        }

        // Obstacles get spatial audio
        if let closest = navigation.obstacles.first {
            return AudioFeedback(
                type: .beep,
                volume: 0.7,
                spatial: SpatialAudio(
                    direction: closest.direction,
                    distance: closest.distance
                )
            )
        }

        return nil
    }

    // MARK: - Speech Synthesis (Non-Blocking)

    /// PERFORMANCE: Non-blocking speech with priority queue
    func speak(_ message: String, priority: MessagePriority = .normal) {
        let speechMessage = SpeechMessage(text: message, priority: priority)

        speechQueue.async { [weak self] in
            guard let self = self else { return }

            self.queueLock.lock()
            defer { self.queueLock.unlock() }

            // Critical messages: Interrupt current speech and clear queue
            if priority == .critical {
                self.synthesizer.stopSpeaking(at: .immediate)
                self.messageQueue.removeAll()
                self.isSpeaking = false
            }

            // High priority: Interrupt but keep queue
            if priority == .high && self.isSpeaking {
                self.synthesizer.stopSpeaking(at: .word)
            }

            // SAFETY CHECK: Prevent queue overflow
            if self.messageQueue.count >= self.maxQueueSize {
                // Remove lowest priority message
                _ = self.messageQueue.dequeue()
                print("⚠️ Speech queue full, dropping lowest priority message")
            }

            // Add to priority queue
            self.messageQueue.enqueue(speechMessage)

            // Process queue if not speaking
            if !self.isSpeaking {
                self.processNextMessage()
            }
        }
    }

    private func processNextMessage() {
        queueLock.lock()
        guard let nextMessage = messageQueue.dequeue() else {
            queueLock.unlock()
            return
        }
        queueLock.unlock()

        let utterance = AVSpeechUtterance(string: nextMessage.text)

        // Adjust speech rate based on priority
        switch nextMessage.priority {
        case .critical:
            utterance.rate = AVSpeechUtteranceMaximumSpeechRate * 0.5
            utterance.volume = 1.0
        case .high:
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.volume = 0.9
        default:
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.volume = 0.7
        }

        // Use high-quality German voice
        if let voice = AVSpeechSynthesisVoice(language: "de-DE") {
            utterance.voice = voice
        }

        isSpeaking = true

        // Speak on main thread (AVSpeechSynthesizer requirement)
        DispatchQueue.main.async { [weak self] in
            self?.synthesizer.speak(utterance)
        }
    }

    fileprivate func didFinishSpeaking() {
        isSpeaking = false
        // Process next message in queue
        processNextMessage()
    }

    func stopSpeaking() {
        speechQueue.async { [weak self] in
            guard let self = self else { return }

            self.queueLock.lock()
            self.synthesizer.stopSpeaking(at: .immediate)
            self.messageQueue.removeAll()
            self.isSpeaking = false
            self.queueLock.unlock()
        }
    }

    func setVerbosity(_ level: VerbosityLevel) {
        self.verbosityLevel = level
    }

    override func reset() {
        stopSpeaking()
    }
}

// MARK: - Supporting Types

/// Message with priority for speech queue
struct SpeechMessage: Comparable {
    let text: String
    let priority: MessagePriority
    let timestamp: Date

    init(text: String, priority: MessagePriority) {
        self.text = text
        self.priority = priority
        self.timestamp = Date()
    }

    static func < (lhs: SpeechMessage, rhs: SpeechMessage) -> Bool {
        // Higher priority comes first
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        // Same priority: FIFO (older first)
        return lhs.timestamp < rhs.timestamp
    }
}

/// AVSpeechSynthesizerDelegate for completion tracking
private class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    weak var agent: CommunicationAgent?

    init(agent: CommunicationAgent) {
        self.agent = agent
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        agent?.didFinishSpeaking()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        agent?.didFinishSpeaking()
    }
}

/// Priority Queue implementation (Min-Heap)
/// PERFORMANCE: O(log n) enqueue/dequeue
struct PriorityQueue<Element: Comparable> {
    private var heap: [Element] = []

    var isEmpty: Bool {
        return heap.isEmpty
    }

    var count: Int {
        return heap.count
    }

    mutating func enqueue(_ element: Element) {
        heap.append(element)
        siftUp(from: heap.count - 1)
    }

    mutating func dequeue() -> Element? {
        guard !heap.isEmpty else { return nil }

        if heap.count == 1 {
            return heap.removeLast()
        }

        let result = heap[0]
        heap[0] = heap.removeLast()
        siftDown(from: 0)

        return result
    }

    func peek() -> Element? {
        return heap.first
    }

    mutating func removeAll() {
        heap.removeAll()
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        var parent = parentIndex(of: child)

        while child > 0 && heap[child] < heap[parent] {
            heap.swapAt(child, parent)
            child = parent
            parent = parentIndex(of: child)
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index

        while true {
            let left = leftChildIndex(of: parent)
            let right = rightChildIndex(of: parent)
            var candidate = parent

            if left < heap.count && heap[left] < heap[candidate] {
                candidate = left
            }

            if right < heap.count && heap[right] < heap[candidate] {
                candidate = right
            }

            if candidate == parent {
                return
            }

            heap.swapAt(parent, candidate)
            parent = candidate
        }
    }

    private func parentIndex(of index: Int) -> Int {
        return (index - 1) / 2
    }

    private func leftChildIndex(of index: Int) -> Int {
        return 2 * index + 1
    }

    private func rightChildIndex(of index: Int) -> Int {
        return 2 * index + 2
    }
}
