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
    private let synthesizer = AVSpeechSynthesizer()
    private var isSpeaking = false

    // Verbosity settings
    private var verbosityLevel: VerbosityLevel = .medium

    enum VerbosityLevel {
        case minimal  // Only critical info
        case medium   // Balanced
        case detailed // Everything
    }

    override init() {
        super.init(name: "CommunicationAgent")
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

    // MARK: - Speech Synthesis

    func speak(_ message: String, priority: MessagePriority = .normal) {
        let utterance = AVSpeechUtterance(string: message)

        // Adjust speech rate based on priority
        switch priority {
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

        // Use high-quality voice
        if let voice = AVSpeechSynthesisVoice(language: "de-DE") {
            utterance.voice = voice
        }

        // Stop current speech if critical
        if priority >= .high && isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func setVerbosity(_ level: VerbosityLevel) {
        self.verbosityLevel = level
    }

    override func reset() {
        stopSpeaking()
    }
}
