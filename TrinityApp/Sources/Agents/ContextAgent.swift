//
//  ContextAgent.swift
//  TRINITY Vision Aid
//
//  Agent responsible for managing context across memory layers
//

import Foundation

/// Input for context agent
struct ContextInput {
    let currentObservation: Observation
    let query: String?
    let memorySearchResults: [VectorEntry]
}

/// Output from context agent
struct ContextOutput {
    let relevantContext: [VectorEntry]
    let contextSummary: String
    let temporalContext: TemporalContext
    let spatialContext: SpatialContext
}

struct TemporalContext {
    let recentEvents: [VectorEntry]  // Last few minutes
    let historicalPatterns: [VectorEntry]  // Similar past experiences
    let timeOfDay: String
}

struct SpatialContext {
    let currentLocation: String
    let nearbyPlaces: [VectorEntry]
    let knownRoutes: [Route]
}

struct Route {
    let id: UUID
    let name: String
    let waypoints: [Waypoint]
    let totalDistance: Double
    let confidence: Float
}

struct Waypoint {
    let location: CLLocationCoordinate2D?
    let description: String
    let landmarks: [String]
}

/// Agent that assembles and manages contextual information
class ContextAgent: BaseAgent<ContextInput, ContextOutput> {
    private let memoryManager: MemoryManager
    private let maxContextSize = 10  // Maximum context items

    init(memoryManager: MemoryManager) {
        self.memoryManager = memoryManager
        super.init(name: "ContextAgent")
    }

    override func process(_ input: ContextInput) async throws -> ContextOutput {
        // Build temporal context
        let temporalContext = buildTemporalContext(
            currentObservation: input.currentObservation,
            memoryResults: input.memorySearchResults
        )

        // Build spatial context
        let spatialContext = await buildSpatialContext(
            currentLocation: input.currentObservation.location
        )

        // Select most relevant context
        let relevantContext = selectRelevantContext(
            from: input.memorySearchResults,
            temporal: temporalContext,
            spatial: spatialContext
        )

        // Generate context summary
        let summary = generateContextSummary(
            context: relevantContext,
            temporal: temporalContext,
            spatial: spatialContext
        )

        return ContextOutput(
            relevantContext: relevantContext,
            contextSummary: summary,
            temporalContext: temporalContext,
            spatialContext: spatialContext
        )
    }

    // MARK: - Context Building

    private func buildTemporalContext(
        currentObservation: Observation,
        memoryResults: [VectorEntry]
    ) -> TemporalContext {
        let now = Date()
        let fiveMinutesAgo = now.addingTimeInterval(-300)

        // Recent events from working and episodic memory
        let recentEvents = memoryResults.filter { entry in
            entry.metadata.timestamp > fiveMinutesAgo &&
            (entry.memoryLayer == .working || entry.memoryLayer == .episodic)
        }.sorted { $0.metadata.timestamp > $1.metadata.timestamp }

        // Historical patterns from semantic memory
        let historicalPatterns = memoryResults.filter { entry in
            entry.memoryLayer == .semantic
        }.sorted { $0.accessCount > $1.accessCount }

        // Time of day context
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let timeOfDay = categorizeTimeOfDay(hour: hour)

        return TemporalContext(
            recentEvents: Array(recentEvents.prefix(5)),
            historicalPatterns: Array(historicalPatterns.prefix(5)),
            timeOfDay: timeOfDay
        )
    }

    private func buildSpatialContext(
        currentLocation: CLLocation?
    ) async -> SpatialContext {
        guard let location = currentLocation else {
            return SpatialContext(
                currentLocation: "Unknown location",
                nearbyPlaces: [],
                knownRoutes: []
            )
        }

        // Find nearby places from episodic memory
        let nearbyPlaces = await findNearbyPlaces(location: location)

        // Find known routes
        let routes = await findKnownRoutes(near: location)

        // Reverse geocode for location name
        let locationName = "Current location"  // In production, use CLGeocoder

        return SpatialContext(
            currentLocation: locationName,
            nearbyPlaces: nearbyPlaces,
            knownRoutes: routes
        )
    }

    private func findNearbyPlaces(location: CLLocation) async -> [VectorEntry] {
        // Search episodic memory for entries near current location
        let radiusMeters = 100.0

        return await memoryManager.episodicMemory.filter { entry in
            guard let entryLocation = entry.metadata.location else { return false }

            let entryCoordinate = CLLocation(
                latitude: entryLocation.latitude,
                longitude: entryLocation.longitude
            )

            return location.distance(from: entryCoordinate) < radiusMeters
        }
    }

    private func findKnownRoutes(near location: CLLocation) async -> [Route] {
        // Analyze episodic memory to identify frequently traveled routes
        // This is a simplified version - in production, use path clustering

        var routes: [Route] = []

        // Group episodic memories by temporal proximity
        let sortedMemories = await memoryManager.episodicMemory
            .filter { $0.metadata.location != nil }
            .sorted { $0.metadata.timestamp < $1.metadata.timestamp }

        // Identify consecutive location points as potential routes
        var currentRoute: [VectorEntry] = []
        var previousTime: Date?

        for entry in sortedMemories {
            if let prevTime = previousTime {
                let timeDiff = entry.metadata.timestamp.timeIntervalSince(prevTime)

                if timeDiff < 300 { // Within 5 minutes
                    currentRoute.append(entry)
                } else {
                    // Route ended, save if significant
                    if currentRoute.count >= 3 {
                        routes.append(createRoute(from: currentRoute))
                    }
                    currentRoute = [entry]
                }
            } else {
                currentRoute = [entry]
            }

            previousTime = entry.metadata.timestamp
        }

        return routes.prefix(5).map { $0 }
    }

    private func createRoute(from entries: [VectorEntry]) -> Route {
        let waypoints = entries.compactMap { entry -> Waypoint? in
            guard let location = entry.metadata.location else { return nil }

            return Waypoint(
                location: location,
                description: entry.metadata.description,
                landmarks: entry.metadata.tags
            )
        }

        // Calculate total distance
        var totalDistance = 0.0
        for i in 0..<(waypoints.count - 1) {
            if let loc1 = waypoints[i].location,
               let loc2 = waypoints[i + 1].location {
                let clLoc1 = CLLocation(latitude: loc1.latitude, longitude: loc1.longitude)
                let clLoc2 = CLLocation(latitude: loc2.latitude, longitude: loc2.longitude)
                totalDistance += clLoc1.distance(from: clLoc2)
            }
        }

        return Route(
            id: UUID(),
            name: "Route \(entries.first?.metadata.timestamp.formatted() ?? "")",
            waypoints: waypoints,
            totalDistance: totalDistance,
            confidence: 0.8
        )
    }

    // MARK: - Context Selection

    private func selectRelevantContext(
        from allResults: [VectorEntry],
        temporal: TemporalContext,
        spatial: SpatialContext
    ) -> [VectorEntry] {
        var context: [VectorEntry] = []

        // Priority 1: Recent events (working memory)
        context.append(contentsOf: temporal.recentEvents.prefix(3))

        // Priority 2: Spatial context (nearby places)
        context.append(contentsOf: spatial.nearbyPlaces.prefix(2))

        // Priority 3: Historical patterns
        context.append(contentsOf: temporal.historicalPatterns.prefix(2))

        // Remove duplicates and limit size
        let uniqueContext = Array(Set(context.map { $0.id }))
            .compactMap { id in context.first { $0.id == id } }
            .prefix(maxContextSize)

        return Array(uniqueContext)
    }

    // MARK: - Summary Generation

    private func generateContextSummary(
        context: [VectorEntry],
        temporal: TemporalContext,
        spatial: SpatialContext
    ) -> String {
        var summary = ""

        // Time context
        summary += "It's currently \(temporal.timeOfDay). "

        // Location context
        if !spatial.nearbyPlaces.isEmpty {
            summary += "You've been to this area before. "
        }

        // Recent activity
        if !temporal.recentEvents.isEmpty {
            let recentObjects = temporal.recentEvents
                .prefix(3)
                .map { $0.metadata.objectType }
                .joined(separator: ", ")
            summary += "Recently seen: \(recentObjects). "
        }

        // Known routes
        if !spatial.knownRoutes.isEmpty {
            summary += "I recognize this as part of a familiar route. "
        }

        return summary.trimmingCharacters(in: .whitespaces)
    }

    private func categorizeTimeOfDay(hour: Int) -> String {
        switch hour {
        case 5..<12:
            return "morning"
        case 12..<17:
            return "afternoon"
        case 17..<21:
            return "evening"
        default:
            return "night"
        }
    }

    override func reset() {
        // Clear any cached context
    }
}
