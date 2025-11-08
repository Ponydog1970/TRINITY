//
//  NavigationAgent.swift
//  TRINITY Vision Aid
//
//  Agent responsible for navigation guidance and obstacle detection
//

import Foundation
import CoreLocation
import ARKit

/// Input for navigation agent
struct NavigationInput {
    let currentLocation: CLLocation?
    let destination: CLLocation?
    let spatialMap: SpatialMap?
    let detectedObjects: [DetectedObject]
    let userHeading: Double  // Degrees
}

/// Output from navigation agent
struct NavigationOutput {
    let instructions: [NavigationInstruction]
    let obstacles: [Obstacle]
    let safetyWarnings: [SafetyWarning]
    let estimatedDistance: Double?  // meters to destination
}

struct NavigationInstruction {
    let text: String
    let audioDescription: String
    let direction: Direction
    let distance: Double?  // meters
    let priority: MessagePriority
}

enum Direction {
    case forward
    case left
    case right
    case back
    case upStairs
    case downStairs
    case stop

    var description: String {
        switch self {
        case .forward: return "ahead"
        case .left: return "to your left"
        case .right: return "to your right"
        case .back: return "behind you"
        case .upStairs: return "stairs going up"
        case .downStairs: return "stairs going down"
        case .stop: return "stop"
        }
    }
}

struct Obstacle {
    let id: UUID
    let type: ObstacleType
    let distance: Float  // meters
    let direction: Direction
    let boundingBox: BoundingBox
    let severity: Severity
}

enum ObstacleType {
    case wall
    case furniture
    case stairs
    case dropOff
    case person
    case vehicle
    case unknown

    var description: String {
        switch self {
        case .wall: return "wall"
        case .furniture: return "furniture"
        case .stairs: return "stairs"
        case .dropOff: return "drop-off"
        case .person: return "person"
        case .vehicle: return "vehicle"
        case .unknown: return "obstacle"
        }
    }
}

enum Severity: Int, Comparable {
    case low = 0      // > 3 meters away
    case medium = 1   // 1-3 meters
    case high = 2     // < 1 meter
    case critical = 3 // immediate danger

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

struct SafetyWarning {
    let message: String
    let severity: Severity
}

/// Agent that provides navigation guidance and obstacle avoidance
class NavigationAgent: BaseAgent<NavigationInput, NavigationOutput> {
    private let minSafeDistance: Float = 1.0  // meters
    private let warningDistance: Float = 2.0  // meters

    init() {
        super.init(name: "NavigationAgent")
    }

    override func process(_ input: NavigationInput) async throws -> NavigationOutput {
        // Detect obstacles from spatial map and objects
        let obstacles = detectObstacles(
            spatialMap: input.spatialMap,
            objects: input.detectedObjects
        )

        // Generate safety warnings for nearby obstacles
        let warnings = generateSafetyWarnings(obstacles: obstacles)

        // Generate navigation instructions
        let instructions = generateInstructions(
            from: input.currentLocation,
            to: input.destination,
            obstacles: obstacles,
            heading: input.userHeading
        )

        // Calculate distance to destination
        let distance = calculateDistance(
            from: input.currentLocation,
            to: input.destination
        )

        return NavigationOutput(
            instructions: instructions,
            obstacles: obstacles,
            safetyWarnings: warnings,
            estimatedDistance: distance
        )
    }

    // MARK: - Obstacle Detection

    private func detectObstacles(
        spatialMap: SpatialMap?,
        objects: [DetectedObject]
    ) -> [Obstacle] {
        var obstacles: [Obstacle] = []

        // Detect obstacles from detected objects
        for object in objects {
            guard let spatialData = object.spatialData else { continue }

            let obstacleType = classifyObstacle(object.label)
            let direction = determineDirection(from: spatialData.boundingBox)
            let severity = calculateSeverity(distance: spatialData.depth)

            let obstacle = Obstacle(
                id: object.id,
                type: obstacleType,
                distance: spatialData.depth,
                direction: direction,
                boundingBox: spatialData.boundingBox,
                severity: severity
            )

            obstacles.append(obstacle)
        }

        // Detect obstacles from spatial map (walls, drop-offs)
        if let spatialMap = spatialMap {
            obstacles += detectWalls(from: spatialMap)
            obstacles += detectDropOffs(from: spatialMap)
        }

        return obstacles.sorted { $0.distance < $1.distance }
    }

    private func classifyObstacle(_ label: String) -> ObstacleType {
        let lowercased = label.lowercased()

        if lowercased.contains("wall") || lowercased.contains("door") {
            return .wall
        } else if lowercased.contains("stair") {
            return .stairs
        } else if lowercased.contains("person") || lowercased.contains("people") {
            return .person
        } else if lowercased.contains("car") || lowercased.contains("vehicle") {
            return .vehicle
        } else if lowercased.contains("table") || lowercased.contains("chair") ||
                  lowercased.contains("furniture") {
            return .furniture
        } else {
            return .unknown
        }
    }

    private func determineDirection(from boundingBox: BoundingBox) -> Direction {
        let centerX = boundingBox.x + boundingBox.width / 2

        if centerX < -0.3 {
            return .left
        } else if centerX > 0.3 {
            return .right
        } else {
            return .forward
        }
    }

    private func calculateSeverity(distance: Float) -> Severity {
        if distance < 0.5 {
            return .critical
        } else if distance < minSafeDistance {
            return .high
        } else if distance < warningDistance {
            return .medium
        } else {
            return .low
        }
    }

    private func detectWalls(from spatialMap: SpatialMap) -> [Obstacle] {
        var walls: [Obstacle] = []

        for plane in spatialMap.planes where plane.alignment == .vertical {
            let distance = calculateDistance(to: plane.center)

            if distance < warningDistance {
                let obstacle = Obstacle(
                    id: UUID(),
                    type: .wall,
                    distance: distance,
                    direction: determineDirection(from: plane.center),
                    boundingBox: createBoundingBox(from: plane),
                    severity: calculateSeverity(distance: distance)
                )
                walls.append(obstacle)
            }
        }

        return walls
    }

    private func detectDropOffs(from spatialMap: SpatialMap) -> [Obstacle] {
        // Analyze height changes in horizontal planes to detect stairs or drop-offs
        // This is a simplified version
        return []
    }

    private func calculateDistance(to point: SIMD3<Float>) -> Float {
        return sqrt(point.x * point.x + point.y * point.y + point.z * point.z)
    }

    private func determineDirection(from point: SIMD3<Float>) -> Direction {
        if point.x < -0.5 {
            return .left
        } else if point.x > 0.5 {
            return .right
        } else {
            return .forward
        }
    }

    private func createBoundingBox(from plane: ARPlaneAnchor) -> BoundingBox {
        return BoundingBox(
            x: plane.center.x - plane.planeExtent.width / 2,
            y: plane.center.y,
            z: plane.center.z - plane.planeExtent.height / 2,
            width: plane.planeExtent.width,
            height: 2.0,  // Assume 2m wall height
            depth: 0.1
        )
    }

    // MARK: - Safety Warnings

    private func generateSafetyWarnings(obstacles: [Obstacle]) -> [SafetyWarning] {
        var warnings: [SafetyWarning] = []

        // Critical obstacles
        let criticalObstacles = obstacles.filter { $0.severity == .critical }
        if !criticalObstacles.isEmpty {
            let obstacle = criticalObstacles[0]
            warnings.append(SafetyWarning(
                message: "Stop! \(obstacle.type.description.capitalized) directly ahead, very close",
                severity: .critical
            ))
        }

        // High severity obstacles
        let highObstacles = obstacles.filter { $0.severity == .high }
        for obstacle in highObstacles.prefix(2) {
            warnings.append(SafetyWarning(
                message: "\(obstacle.type.description.capitalized) \(obstacle.direction.description), about \(Int(obstacle.distance)) meter away",
                severity: .high
            ))
        }

        return warnings
    }

    // MARK: - Navigation Instructions

    private func generateInstructions(
        from currentLocation: CLLocation?,
        to destination: CLLocation?,
        obstacles: [Obstacle],
        heading: Double
    ) -> [NavigationInstruction] {
        var instructions: [NavigationInstruction] = []

        // Priority 1: Immediate obstacle warnings
        let immediateObstacles = obstacles.filter { $0.severity >= .high }
        if let closest = immediateObstacles.first {
            let instruction = NavigationInstruction(
                text: "Obstacle ahead",
                audioDescription: "\(closest.type.description.capitalized) \(closest.direction.description), \(Int(closest.distance)) meter away",
                direction: .stop,
                distance: Double(closest.distance),
                priority: .critical
            )
            instructions.append(instruction)
            return instructions  // Stop further navigation if immediate danger
        }

        // Priority 2: Route guidance if destination is set
        if let current = currentLocation, let dest = destination {
            let bearing = calculateBearing(from: current, to: dest)
            let turnDirection = calculateTurnDirection(
                currentHeading: heading,
                targetBearing: bearing
            )

            let distance = current.distance(from: dest)

            let instruction = NavigationInstruction(
                text: "Turn \(turnDirection.description)",
                audioDescription: "Turn \(turnDirection.description) and continue for \(Int(distance)) meters",
                direction: turnDirection,
                distance: distance,
                priority: .normal
            )
            instructions.append(instruction)
        }

        // Priority 3: Environmental awareness
        if obstacles.filter({ $0.severity == .medium }).count > 0 {
            instructions.append(NavigationInstruction(
                text: "Obstacles nearby",
                audioDescription: "Be aware of obstacles in the area",
                direction: .forward,
                distance: nil,
                priority: .low
            ))
        }

        return instructions
    }

    private func calculateBearing(from: CLLocation, to: CLLocation) -> Double {
        let lat1 = from.coordinate.latitude.degreesToRadians
        let lon1 = from.coordinate.longitude.degreesToRadians
        let lat2 = to.coordinate.latitude.degreesToRadians
        let lon2 = to.coordinate.longitude.degreesToRadians

        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

        let bearing = atan2(y, x).radiansToDegrees
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    private func calculateTurnDirection(
        currentHeading: Double,
        targetBearing: Double
    ) -> Direction {
        let difference = (targetBearing - currentHeading + 360)
            .truncatingRemainder(dividingBy: 360)

        if difference < 30 || difference > 330 {
            return .forward
        } else if difference < 180 {
            return .right
        } else {
            return .left
        }
    }

    private func calculateDistance(
        from: CLLocation?,
        to: CLLocation?
    ) -> Double? {
        guard let from = from, let to = to else { return nil }
        return from.distance(from: to)
    }
}

// MARK: - Extensions

extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
    var radiansToDegrees: Double { self * 180 / .pi }
}
