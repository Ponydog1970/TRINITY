//
//  TriggerAgent.swift
//  TRINITY Vision Aid
//
//  Proaktives Trigger-System für automatische Aktionen
//

import Foundation
import CoreLocation
import Combine

/// Agent für proaktive Trigger basierend auf Kontext
@MainActor
class TriggerAgent: ObservableObject {
    @Published var activeTriggers: [MemoryTrigger] = []
    @Published var triggeredActions: [TriggeredAction] = []

    private let memoryManager: EnhancedMemoryManager
    private let communicationAgent: CommunicationAgent

    // Trigger-Historie
    private var triggerHistory: [TriggerEvent] = []
    private let maxHistorySize = 100

    init(
        memoryManager: EnhancedMemoryManager,
        communicationAgent: CommunicationAgent
    ) {
        self.memoryManager = memoryManager
        self.communicationAgent = communicationAgent
    }

    // MARK: - Trigger Evaluation

    /// Evaluiert alle aktiven Trigger gegen aktuelle Beobachtung
    func evaluateTriggers(
        observation: Observation,
        currentLocation: CLLocation?,
        memories: [EnhancedVectorEntry]
    ) async {
        var triggeredActions: [TriggeredAction] = []

        for memory in memories {
            for trigger in memory.triggers where trigger.isActive {

                let shouldTrigger = memory.shouldActivateTrigger(
                    trigger,
                    currentLocation: currentLocation,
                    currentTime: Date(),
                    detectedObjects: observation.detectedObjects
                )

                if shouldTrigger {
                    // Prüfe ob Trigger kürzlich schon aktiviert wurde (Debouncing)
                    if !wasRecentlyTriggered(trigger, within: 60) {
                        let action = await executeTrigger(
                            trigger,
                            memory: memory,
                            observation: observation
                        )
                        triggeredActions.append(action)

                        // Log Trigger Event
                        logTriggerEvent(
                            trigger: trigger,
                            memory: memory,
                            successful: true
                        )
                    }
                }
            }
        }

        self.triggeredActions = triggeredActions
    }

    // MARK: - Trigger Execution

    private func executeTrigger(
        _ trigger: MemoryTrigger,
        memory: EnhancedVectorEntry,
        observation: Observation
    ) async -> TriggeredAction {

        let action = trigger.action

        switch action.actionType {
        case .speak:
            await executeSpeakAction(action, memory: memory)

        case .notify:
            executeNotifyAction(action, memory: memory)

        case .retrieve:
            await executeRetrieveAction(action, memory: memory)

        case .webSearch:
            await executeWebSearchAction(action, memory: memory)

        case .log:
            executeLogAction(action, memory: memory)

        case .custom:
            executeCustomAction(action, memory: memory)
        }

        return TriggeredAction(
            trigger: trigger,
            memory: memory,
            executedAt: Date(),
            result: "Success"
        )
    }

    // MARK: - Action Implementations

    private func executeSpeakAction(
        _ action: MemoryTrigger.TriggerAction,
        memory: EnhancedVectorEntry
    ) async {
        let message = action.message ?? "Trigger aktiviert: \(memory.objectType)"

        // Erweitere mit Kontext
        var fullMessage = message

        // Füge Distanz hinzu wenn verfügbar
        if let spatialData = memory.spatialData {
            fullMessage += " - etwa \(Int(spatialData.depth)) Meter entfernt"
        }

        // Füge Richtung hinzu
        if let spatialData = memory.spatialData {
            let direction = describeDirection(spatialData.boundingBox)
            fullMessage += ", \(direction)"
        }

        // Sprechen via Communication Agent
        communicationAgent.speak(fullMessage, priority: .high)

        print("🔊 Trigger Speech: \(fullMessage)")
    }

    private func executeNotifyAction(
        _ action: MemoryTrigger.TriggerAction,
        memory: EnhancedVectorEntry
    ) {
        // Haptic Feedback
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif

        print("🔔 Trigger Notification: \(action.message ?? "")")
    }

    private func executeRetrieveAction(
        _ action: MemoryTrigger.TriggerAction,
        memory: EnhancedVectorEntry
    ) async {
        guard let memoryIDs = action.relatedMemoryIDs else { return }

        // Rufe verwandte Memories ab
        let relatedMemories = await memoryManager.retrieve(memoryIDs: memoryIDs)

        // Erstelle Zusammenfassung
        let summary = relatedMemories.map { $0.description }.joined(separator: ", ")

        let message = "Kontext: \(summary)"
        communicationAgent.speak(message, priority: .normal)

        print("📚 Retrieved \(relatedMemories.count) related memories")
    }

    private func executeWebSearchAction(
        _ action: MemoryTrigger.TriggerAction,
        memory: EnhancedVectorEntry
    ) async {
        guard let query = action.webSearchQuery else { return }

        // Web-Suche durchführen (vereinfacht)
        let searchQuery = query.replacingOccurrences(of: "{location}", with: memory.locationName ?? "")
        let searchQuery2 = searchQuery.replacingOccurrences(of: "{object}", with: memory.objectType)

        print("🔍 Web Search: \(searchQuery2)")

        // In echter Implementation: WebSearch API nutzen
        // Beispiel:
        // let results = try await webSearchAPI.search(query: searchQuery2)
        // communicationAgent.speak("Gefunden: \(results.first?.snippet ?? "")")

        // Für jetzt: Nur Info
        let message = "Ich würde jetzt nach '\(searchQuery2)' suchen"
        communicationAgent.speak(message)
    }

    private func executeLogAction(
        _ action: MemoryTrigger.TriggerAction,
        memory: EnhancedVectorEntry
    ) {
        print("📝 Trigger Log: \(action.message ?? "") - Memory: \(memory.description)")
    }

    private func executeCustomAction(
        _ action: MemoryTrigger.TriggerAction,
        memory: EnhancedVectorEntry
    ) {
        // Custom Actions aus customData
        if let customData = action.customData {
            print("🎯 Custom Action: \(customData)")
        }
    }

    // MARK: - Helpers

    private func wasRecentlyTriggered(_ trigger: MemoryTrigger, within seconds: TimeInterval) -> Bool {
        let recentEvents = triggerHistory.filter { event in
            event.trigger.id == trigger.id &&
            Date().timeIntervalSince(event.timestamp) < seconds
        }
        return !recentEvents.isEmpty
    }

    private func logTriggerEvent(
        trigger: MemoryTrigger,
        memory: EnhancedVectorEntry,
        successful: Bool
    ) {
        let event = TriggerEvent(
            trigger: trigger,
            memoryID: memory.id,
            timestamp: Date(),
            successful: successful
        )

        triggerHistory.append(event)

        // Limit Größe
        if triggerHistory.count > maxHistorySize {
            triggerHistory.removeFirst()
        }
    }

    private func describeDirection(_ boundingBox: BoundingBox) -> String {
        let centerX = boundingBox.x + boundingBox.width / 2

        if centerX < -0.3 {
            return "links von Ihnen"
        } else if centerX > 0.3 {
            return "rechts von Ihnen"
        } else {
            return "vor Ihnen"
        }
    }

    // MARK: - Trigger Management

    /// Fügt neuen Trigger hinzu
    func addTrigger(
        to memoryID: UUID,
        trigger: MemoryTrigger
    ) async {
        await memoryManager.addTrigger(to: memoryID, trigger: trigger)
        activeTriggers.append(trigger)
    }

    /// Deaktiviert Trigger
    func deactivateTrigger(id: UUID) async {
        if let index = activeTriggers.firstIndex(where: { $0.id == id }) {
            activeTriggers[index].isActive = false
        }
    }

    /// Holt alle aktiven Trigger
    func getActiveTriggers() -> [MemoryTrigger] {
        return activeTriggers.filter { $0.isActive }
    }

    /// Statistiken
    func getTriggerStatistics() -> TriggerStatistics {
        let totalTriggers = activeTriggers.count
        let activeCount = activeTriggers.filter { $0.isActive }.count
        let totalFired = triggerHistory.count
        let successfulFired = triggerHistory.filter { $0.successful }.count

        return TriggerStatistics(
            totalTriggers: totalTriggers,
            activeTriggers: activeCount,
            totalFired: totalFired,
            successfulFired: successfulFired
        )
    }
}

// MARK: - Supporting Types

struct TriggeredAction {
    let trigger: MemoryTrigger
    let memory: EnhancedVectorEntry
    let executedAt: Date
    let result: String
}

struct TriggerEvent {
    let trigger: MemoryTrigger
    let memoryID: UUID
    let timestamp: Date
    let successful: Bool
}

struct TriggerStatistics {
    let totalTriggers: Int
    let activeTriggers: Int
    let totalFired: Int
    let successfulFired: Int
}

// MARK: - Enhanced Memory Manager (Placeholder)

class EnhancedMemoryManager: MemoryManager {
    // Erweiterte Version mit EnhancedVectorEntry Support

    func retrieve(memoryIDs: [UUID]) async -> [EnhancedVectorEntry] {
        // Rufe Memories by IDs ab
        // Placeholder Implementation
        return []
    }

    func addTrigger(to memoryID: UUID, trigger: MemoryTrigger) async {
        // Füge Trigger zu Memory hinzu
        // Placeholder Implementation
    }
}

// MARK: - Usage Example

/*
 // Trigger-Agent erstellen:
 let triggerAgent = TriggerAgent(
     memoryManager: enhancedMemoryManager,
     communicationAgent: communicationAgent
 )

 // Trigger erstellen: "Auto gesehen → Warnung"
 let autoTrigger = MemoryTrigger(
     triggerType: .objectDetected,
     condition: MemoryTrigger.TriggerCondition(
         objectLabels: ["Auto", "Bus", "LKW"],
         locationRadius: nil,
         locationCoordinate: nil,
         timeRange: nil,
         keywords: nil,
         minConfidence: 0.7
     ),
     action: MemoryTrigger.TriggerAction(
         actionType: .speak,
         message: "Achtung! Fahrzeug in Ihrer Nähe",
         relatedMemoryIDs: nil,
         webSearchQuery: nil,
         customData: nil
     ),
     priority: 10 // Sehr wichtig!
 )

 // Trigger zu Memory hinzufügen:
 await triggerAgent.addTrigger(to: memoryID, trigger: autoTrigger)

 // Trigger evaluieren bei neuer Beobachtung:
 await triggerAgent.evaluateTriggers(
     observation: observation,
     currentLocation: currentLocation,
     memories: allMemories
 )

 // Statistiken abrufen:
 let stats = triggerAgent.getTriggerStatistics()
 print("Trigger gefeuert: \(stats.totalFired)")
 */
