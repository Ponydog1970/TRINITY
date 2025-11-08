//
//  SensorManager.swift
//  TRINITY Vision Aid
//
//  Manages camera, LiDAR, and other sensors
//

import Foundation
import AVFoundation
import ARKit
import CoreLocation
import Combine

/// Manages all sensor inputs
@MainActor
class SensorManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isARSessionRunning = false
    @Published var currentLocation: CLLocation?
    @Published var currentHeading: Double = 0.0

    // MARK: - Sensors
    private var arSession: ARSession?
    private var locationManager: CLLocationManager?

    // MARK: - Observation Stream
    private let observationSubject = PassthroughSubject<Observation, Never>()
    var observationPublisher: AnyPublisher<Observation, Never> {
        observationSubject.eraseToAnyPublisher()
    }

    // MARK: - Configuration
    private var isConfigured = false

    // MARK: - Initialization

    override init() {
        super.init()
        setupLocationManager()
    }

    // MARK: - Setup

    func configure() throws {
        guard !isConfigured else { return }

        // Check AR availability
        guard ARWorldTrackingConfiguration.isSupported else {
            throw SensorError.arNotSupported
        }

        // Setup AR session
        setupARSession()

        isConfigured = true
    }

    private func setupARSession() {
        arSession = ARSession()
        arSession?.delegate = self

        let configuration = ARWorldTrackingConfiguration()

        // Enable LiDAR scanning
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }

        // Enable plane detection
        configuration.planeDetection = [.horizontal, .vertical]

        // Enable frame semantics for person segmentation
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        }

        arSession?.run(configuration)
    }

    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBest

        // Request location permissions
        locationManager?.requestWhenInUseAuthorization()
    }

    // MARK: - Session Control

    func startSession() {
        guard let arSession = arSession else { return }

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }

        arSession.run(configuration)
        isARSessionRunning = true

        // Start location updates
        locationManager?.startUpdatingLocation()
        locationManager?.startUpdatingHeading()
    }

    func pauseSession() {
        arSession?.pause()
        isARSessionRunning = false

        locationManager?.stopUpdatingLocation()
        locationManager?.stopUpdatingHeading()
    }

    func resetSession() {
        guard let arSession = arSession else { return }

        let configuration = ARWorldTrackingConfiguration()
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - Capture

    func captureCurrentObservation() -> Observation? {
        guard let frame = arSession?.currentFrame else { return nil }

        return createObservation(from: frame)
    }

    private func createObservation(from arFrame: ARFrame) -> Observation {
        // Extract camera image
        let cameraImage = extractImageData(from: arFrame)

        // Extract depth data
        let depthData = extractDepthData(from: arFrame)

        // Detect objects (placeholder - would use Vision framework)
        let detectedObjects = detectObjects(in: arFrame)

        // Get device orientation
        let orientation = Orientation(
            pitch: Float(arFrame.camera.eulerAngles.x),
            yaw: Float(arFrame.camera.eulerAngles.y),
            roll: Float(arFrame.camera.eulerAngles.z)
        )

        return Observation(
            timestamp: Date(),
            cameraImage: cameraImage,
            depthMap: depthData,
            detectedObjects: detectedObjects,
            location: currentLocation,
            deviceOrientation: orientation
        )
    }

    private func extractImageData(from frame: ARFrame) -> Data? {
        let pixelBuffer = frame.capturedImage

        guard let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right) else {
            return nil
        }

        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        #if os(iOS)
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.8)
        #else
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return nsImage.tiffRepresentation
        #endif
    }

    private func extractDepthData(from frame: ARFrame) -> Data? {
        guard let depthMap = frame.sceneDepth?.depthMap else { return nil }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }

        let data = Data(bytes: baseAddress, count: bytesPerRow * height)
        return data
    }

    private func detectObjects(in frame: ARFrame) -> [DetectedObject] {
        // Placeholder - in production, use Vision framework
        // This would process frame.capturedImage with VNRecognizeObjectsRequest

        var objects: [DetectedObject] = []

        // Extract detected planes as objects
        for anchor in frame.anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                let object = DetectedObject(
                    id: UUID(),
                    label: planeAnchor.alignment == .horizontal ? "floor" : "wall",
                    confidence: 0.95,
                    boundingBox: BoundingBox(
                        x: planeAnchor.center.x,
                        y: planeAnchor.center.y,
                        z: planeAnchor.center.z,
                        width: planeAnchor.planeExtent.width,
                        height: 0.1,
                        depth: planeAnchor.planeExtent.height
                    ),
                    spatialData: SpatialData(
                        depth: calculateDistance(to: planeAnchor.center),
                        boundingBox: BoundingBox(
                            x: planeAnchor.center.x,
                            y: planeAnchor.center.y,
                            z: planeAnchor.center.z,
                            width: planeAnchor.planeExtent.width,
                            height: 0.1,
                            depth: planeAnchor.planeExtent.height
                        ),
                        orientation: Orientation(pitch: 0, yaw: 0, roll: 0),
                        confidence: 0.95
                    )
                )
                objects.append(object)
            }
        }

        return objects
    }

    private func calculateDistance(to point: SIMD3<Float>) -> Float {
        return sqrt(point.x * point.x + point.y * point.y + point.z * point.z)
    }

    // MARK: - Permissions

    func checkPermissions() -> Bool {
        // Check camera permission
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard cameraStatus == .authorized else { return false }

        // Check location permission
        let locationStatus = locationManager?.authorizationStatus
        guard locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways else {
            return false
        }

        return true
    }

    func requestPermissions() async -> Bool {
        // Request camera permission
        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        guard cameraGranted else { return false }

        // Location permission is handled by CLLocationManagerDelegate
        locationManager?.requestWhenInUseAuthorization()

        return true
    }
}

// MARK: - ARSessionDelegate

extension SensorManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Create observation from frame
        let observation = createObservation(from: frame)

        // Publish observation
        Task { @MainActor in
            observationSubject.send(observation)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR Session failed: \(error.localizedDescription)")
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            isARSessionRunning = false
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            isARSessionRunning = true
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension SensorManager: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            currentLocation = locations.last
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        Task { @MainActor in
            currentHeading = newHeading.trueHeading
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("Location manager failed: \(error.localizedDescription)")
    }
}

// MARK: - Errors

enum SensorError: Error {
    case arNotSupported
    case cameraPermissionDenied
    case locationPermissionDenied

    var localizedDescription: String {
        switch self {
        case .arNotSupported:
            return "ARKit is not supported on this device"
        case .cameraPermissionDenied:
            return "Camera permission was denied"
        case .locationPermissionDenied:
            return "Location permission was denied"
        }
    }
}

#if os(iOS)
import UIKit
#else
import AppKit
#endif
