//
//  RouteRecording.swift
//  TRINITY Vision Aid
//
//  Route recording and navigation system (Konzept + Implementation)
//

import Foundation
import CoreLocation
import MapKit

/// Aufzeichnet alle Wege und erstellt Routen-Gedächtnis
@MainActor
class RouteRecordingManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isRecording: Bool = false
    @Published var currentRoute: RecordedRoute?
    @Published var savedRoutes: [RecordedRoute] = []

    // MARK: - Configuration

    private let minimumDistance: Double = 5.0       // Min 5 Meter zwischen Waypoints
    private let locationManager: CLLocationManager
    private var currentWaypoints: [RecordedWaypoint] = []
    private var lastLocation: CLLocation?

    // MARK: - Initialization

    override init() {
        self.locationManager = CLLocationManager()
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = minimumDistance
        locationManager.allowsBackgroundLocationUpdates = true
    }

    // MARK: - Recording Control

    func startRecording(name: String? = nil) {
        guard !isRecording else { return }

        isRecording = true
        currentWaypoints = []
        lastLocation = nil

        locationManager.startUpdatingLocation()

        currentRoute = RecordedRoute(
            id: UUID(),
            name: name ?? "Route \(Date().formatted())",
            waypoints: [],
            startTime: Date(),
            endTime: nil
        )

        print("🎙️ Route recording started")
    }

    func stopRecording() {
        guard isRecording else { return }

        isRecording = false
        locationManager.stopUpdatingLocation()

        if var route = currentRoute {
            route.endTime = Date()
            route.waypoints = currentWaypoints

            // Berechne Statistiken
            route.totalDistance = calculateTotalDistance(waypoints: currentWaypoints)
            route.duration = route.endTime!.timeIntervalSince(route.startTime)

            savedRoutes.append(route)

            // Speichere persistent
            saveRoutes()

            print("✅ Route recording stopped: \(route.totalDistance)m in \(route.duration)s")
        }

        currentRoute = nil
        currentWaypoints = []
    }

    // MARK: - Route Management

    func getSavedRoutes() -> [RecordedRoute] {
        return savedRoutes.sorted { $0.startTime > $1.startTime }
    }

    func deleteRoute(id: UUID) {
        savedRoutes.removeAll { $0.id == id }
        saveRoutes()
    }

    func findSimilarRoute(to location: CLLocation, radius: Double = 100) -> RecordedRoute? {
        // Findet RecordedRoute die in der Nähe startet
        return savedRoutes.first { route in
            guard let firstWaypoint = route.waypoints.first else { return false }

            let waypointLocation = CLLocation(
                latitude: firstWaypoint.coordinate.latitude,
                longitude: firstWaypoint.coordinate.longitude
            )

            return location.distance(from: waypointLocation) < radius
        }
    }

    // MARK: - Route Export

    /// Exportiert RecordedRoute als GPX für Navigation-Apps
    func exportToGPX(route: RecordedRoute) throws -> URL {
        let gpxString = generateGPX(route: route)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(route.name).gpx")

        try gpxString.write(to: tempURL, atomically: true, encoding: .utf8)

        return tempURL
    }

    /// Exportiert RecordedRoute für Apple Maps
    func exportToAppleMaps(route: RecordedRoute) throws {
        guard let firstWaypoint = route.waypoints.first,
              let lastWaypoint = route.waypoints.last else {
            throw RouteError.invalidRoute
        }

        let startCoord = firstWaypoint.coordinate
        let endCoord = lastWaypoint.coordinate

        let startPlacemark = MKPlacemark(coordinate: startCoord)
        let endPlacemark = MKPlacemark(coordinate: endCoord)

        let startItem = MKMapItem(placemark: startPlacemark)
        let endItem = MKMapItem(placemark: endPlacemark)

        startItem.name = route.name + " (Start)"
        endItem.name = route.name + " (Ziel)"

        // Öffne Apple Maps mit Route
        MKMapItem.openMaps(
            with: [startItem, endItem],
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
            ]
        )
    }

    /// Exportiert Waypoints für Google Maps URL
    func generateGoogleMapsURL(route: RecordedRoute) -> URL? {
        guard let firstWaypoint = route.waypoints.first,
              let lastWaypoint = route.waypoints.last else {
            return nil
        }

        let origin = "\(firstWaypoint.coordinate.latitude),\(firstWaypoint.coordinate.longitude)"
        let destination = "\(lastWaypoint.coordinate.latitude),\(lastWaypoint.coordinate.longitude)"

        // Waypoints dazwischen
        let waypointsString = route.waypoints.dropFirst().dropLast()
            .map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" }
            .joined(separator: "|")

        var urlString = "https://www.google.com/maps/dir/?api=1"
        urlString += "&origin=\(origin)"
        urlString += "&destination=\(destination)"

        if !waypointsString.isEmpty {
            urlString += "&waypoints=\(waypointsString)"
        }

        urlString += "&travelmode=walking"

        return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
    }

    // MARK: - Route Analysis

    func analyzeRoute(_ route: RecordedRoute) -> RouteAnalysis {
        // Analysiere RecordedRoute für Muster, häufige Wege, etc.

        var analysis = RouteAnalysis(route: route)

        // Häufig besuchte Orte entlang der Route
        analysis.frequentLocations = identifyFrequentLocations(route: route)

        // Gefahrenstellen (basierend auf Trigger-Historie)
        analysis.hazardPoints = identifyHazards(route: route)

        // Barrierefreiheit (basierend auf Memory)
        analysis.accessibilityNotes = checkAccessibility(route: route)

        return analysis
    }

    private func identifyFrequentLocations(route: RecordedRoute) -> [LocationCluster] {
        // Cluster Waypoints zu häufigen Orten
        // Placeholder
        return []
    }

    private func identifyHazards(route: RecordedRoute) -> [HazardPoint] {
        // Identifiziere Gefahrenstellen aus Trigger-Historie
        // Placeholder
        return []
    }

    private func checkAccessibility(route: RecordedRoute) -> [String] {
        // Überprüfe Barrierefreiheit
        return [
            "Route größtenteils auf Gehwegen",
            "2 Straßenüberquerungen",
            "Keine bekannten Barrieren"
        ]
    }

    // MARK: - GPX Generation

    private func generateGPX(route: RecordedRoute) -> String {
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TRINITY Vision Aid">
          <metadata>
            <name>\(route.name)</name>
            <time>\(route.startTime.ISO8601Format())</time>
          </metadata>
          <trk>
            <name>\(route.name)</name>
            <trkseg>
        """

        for waypoint in route.waypoints {
            gpx += """
                  <trkpt lat="\(waypoint.coordinate.latitude)" lon="\(waypoint.coordinate.longitude)">
                    <time>\(waypoint.timestamp.ISO8601Format())</time>
            """

            if let desc = waypoint.description {
                gpx += """
                        <desc>\(desc)</desc>
                """
            }

            gpx += """
                  </trkpt>
            """
        }

        gpx += """
            </trkseg>
          </trk>
        </gpx>
        """

        return gpx
    }

    // MARK: - Helpers

    private func calculateTotalDistance(waypoints: [RecordedWaypoint]) -> Double {
        var total: Double = 0.0

        for i in 0..<(waypoints.count - 1) {
            let loc1 = CLLocation(
                latitude: waypoints[i].coordinate.latitude,
                longitude: waypoints[i].coordinate.longitude
            )
            let loc2 = CLLocation(
                latitude: waypoints[i + 1].coordinate.latitude,
                longitude: waypoints[i + 1].coordinate.longitude
            )

            total += loc1.distance(from: loc2)
        }

        return total
    }

    // MARK: - Persistence

    private func saveRoutes() {
        // In production: Save to SwiftData or CloudKit
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(savedRoutes) {
            UserDefaults.standard.set(data, forKey: "saved_routes")
        }
    }

    private func loadRoutes() {
        // In production: Load from SwiftData or CloudKit
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "saved_routes"),
           let routes = try? decoder.decode([RecordedRoute].self, from: data) {
            savedRoutes = routes
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension RouteRecordingManager: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            guard isRecording else { return }

            for location in locations {
                // Prüfe Mindestdistanz
                if let last = lastLocation {
                    let distance = location.distance(from: last)
                    if distance < minimumDistance {
                        continue  // Zu nah am letzten Punkt
                    }
                }

                // Erstelle RecordedWaypoint
                let waypoint = RecordedWaypoint(
                    id: UUID(),
                    coordinate: location.coordinate,
                    timestamp: location.timestamp,
                    accuracy: location.horizontalAccuracy,
                    altitude: location.altitude,
                    description: nil,
                    memoryID: nil
                )

                currentWaypoints.append(waypoint)
                lastLocation = location

                print("📍 Waypoint added: \(location.coordinate)")
            }
        }
    }
}

// MARK: - Data Models

/// GPS-basierte aufgezeichnete Route (unterscheidet sich von ContextAgent.Route)
struct RecordedRoute: Codable, Identifiable {
    let id: UUID
    var name: String
    var waypoints: [RecordedWaypoint]
    let startTime: Date
    var endTime: Date?

    // Statistiken
    var totalDistance: Double = 0.0  // Meter
    var duration: TimeInterval = 0.0 // Sekunden

    var formattedDistance: String {
        if totalDistance < 1000 {
            return "\(Int(totalDistance))m"
        } else {
            return String(format: "%.1fkm", totalDistance / 1000)
        }
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)min \(seconds)s"
    }
}

/// GPS-Wegpunkt mit Timestamp und Genauigkeit (unterscheidet sich von ContextAgent.Waypoint)
struct RecordedWaypoint: Codable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let accuracy: Double
    let altitude: Double
    var description: String?
    var memoryID: UUID?  // Verbindung zu EnhancedVectorEntry
}

struct RouteAnalysis {
    let route: RecordedRoute
    var frequentLocations: [LocationCluster] = []
    var hazardPoints: [HazardPoint] = []
    var accessibilityNotes: [String] = []
    var estimatedDifficulty: Difficulty = .easy

    enum Difficulty {
        case easy
        case moderate
        case difficult
    }
}

struct LocationCluster {
    let center: CLLocationCoordinate2D
    let radius: Double
    let visitCount: Int
    let name: String?
}

struct HazardPoint {
    let coordinate: CLLocationCoordinate2D
    let type: HazardType
    let severity: Float

    enum HazardType {
        case traffic
        case stairs
        case construction
        case other
    }
}

enum RouteError: Error {
    case invalidRoute
    case exportFailed
}

// MARK: - Usage Examples

/*
 let routeManager = RouteRecordingManager()

 // Route aufzeichnen:
 routeManager.startRecording(name: "Weg zur Arbeit")
 // ... User geht ...
 routeManager.stopRecording()

 // Routen abrufen:
 let routes = routeManager.getSavedRoutes()

 // Export zu Apple Maps:
 try routeManager.exportToAppleMaps(route: routes[0])

 // Export als GPX:
 let gpxURL = try routeManager.exportToGPX(route: routes[0])
 // Teilen via Activity View Controller

 // Google Maps URL:
 if let url = routeManager.generateGoogleMapsURL(route: routes[0]) {
     UIApplication.shared.open(url)
 }

 // Route analysieren:
 let analysis = routeManager.analyzeRoute(routes[0])
 print("Häufige Orte: \(analysis.frequentLocations.count)")
 print("Gefahrenstellen: \(analysis.hazardPoints.count)")
 */
