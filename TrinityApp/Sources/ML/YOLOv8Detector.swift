//
//  YOLOv8Detector.swift
//  TRINITY Vision Aid
//
//  State-of-the-art Object Detection für sehbehinderte Navigation
//

import Foundation
import CoreML
import Vision
import CoreImage

/// Fehlertypen für Object Detection
enum DetectionError: Error {
    case modelNotFound
    case noResults
    case invalidImage
    case processingFailed(String)
}

/// YOLOv8-basierter Object Detector
/// Download Model: https://developer.apple.com/machine-learning/models/
/// Oder konvertiere von PyTorch: https://github.com/ultralytics/ultralytics
class YOLOv8Detector {
    private var visionModel: VNCoreMLModel?
    private let confidenceThreshold: Float = 0.5
    private var isModelLoading = false
    private var modelLoadTask: Task<Void, Never>?

    // Object Categories optimiert für Navigation/Accessibility
    private let navigationRelevantObjects = Set([
        "person", "car", "bus", "truck", "bicycle", "motorcycle",
        "traffic light", "fire hydrant", "stop sign", "bench",
        "chair", "couch", "dining table", "door", "window",
        "stairs", "escalator", "elevator", "sidewalk",
        "potted plant", "bottle", "cup", "bowl",
        "laptop", "cell phone", "book"
    ])

    init() {
        // PERFORMANCE FIX: Start async model loading immediately, don't block
        modelLoadTask = Task {
            await loadModelAsync()
        }
    }

    /// Lade Core ML Model ASYNCHRONOUSLY
    /// FIX: Prevents UI freeze on app startup
    private func loadModelAsync() async {
        guard !isModelLoading else { return }
        isModelLoading = true

        // Run on background queue
        await Task.detached(priority: .userInitiated) {
            // OPTION 1: Custom YOLOv8 Model (wenn vorhanden)
            if let modelURL = Bundle.main.url(forResource: "yolov8n", withExtension: "mlmodelc") {
                do {
                    let mlModel = try MLModel(contentsOf: modelURL)
                    let visionModel = try VNCoreMLModel(for: mlModel)

                    // Update on main thread
                    await MainActor.run {
                        self.visionModel = visionModel
                        self.isModelLoading = false
                        print("✅ YOLOv8 Model loaded successfully (async)")
                    }
                    return
                } catch {
                    print("⚠️ Failed to load custom YOLOv8 model: \(error)")
                }
            }

            // OPTION 2: Apple's MobileNetV2 (Fallback)
            if let defaultModel = try? VNCoreMLModel(for: MobileNetV2().model) {
                await MainActor.run {
                    self.visionModel = defaultModel
                    self.isModelLoading = false
                    print("⚠️ Using fallback MobileNetV2 model (async)")
                    print("💡 Download YOLOv8 for better accuracy: https://github.com/ultralytics/ultralytics")
                }
            } else {
                await MainActor.run {
                    self.isModelLoading = false
                    print("❌ No object detection model available")
                    print("📥 Please download YOLOv8n.mlmodel and add to project")
                }
            }
        }.value
    }

    /// Ensure model is loaded before detection
    private func ensureModelLoaded() async {
        // Wait for model loading to complete
        await modelLoadTask?.value
    }

    /// Erkenne Objekte in Bild
    func detectObjects(in image: CVPixelBuffer) async throws -> [DetectedObject] {
        // Ensure model is loaded
        await ensureModelLoaded()

        guard let model = visionModel else {
            throw DetectionError.modelNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                guard let self = self else {
                    continuation.resume(throwing: DetectionError.processingFailed("Self deallocated"))
                    return
                }

                if let error = error {
                    continuation.resume(throwing: DetectionError.processingFailed(error.localizedDescription))
                    return
                }

                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(throwing: DetectionError.noResults)
                    return
                }

                let objects = self.processResults(results)
                continuation.resume(returning: objects)
            }

            // Performance Optimizations
            request.imageCropAndScaleOption = .scaleFill
            request.usesCPUOnly = false  // Use Neural Engine wenn verfügbar

            let handler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Erkenne Objekte in UIImage
    func detectObjects(in image: UIImage) async throws -> [DetectedObject] {
        guard let ciImage = CIImage(image: image) else {
            throw DetectionError.invalidImage
        }

        // Convert to CVPixelBuffer
        let context = CIContext()
        guard let pixelBuffer = context.createCVPixelBuffer(from: ciImage) else {
            throw DetectionError.invalidImage
        }

        return try await detectObjects(in: pixelBuffer)
    }

    /// Verarbeite Detection Results
    private func processResults(_ observations: [VNRecognizedObjectObservation]) -> [DetectedObject] {
        var detectedObjects: [DetectedObject] = []

        for observation in observations {
            guard let topLabel = observation.labels.first else { continue }

            // Filter nach Confidence Threshold
            guard topLabel.confidence >= confidenceThreshold else { continue }

            let label = topLabel.identifier.lowercased()

            // Priorisiere navigationsrelevante Objekte
            let importance = calculateImportance(label: label, confidence: topLabel.confidence)

            let object = DetectedObject(
                id: UUID(),
                label: localizeLabel(label),  // Übersetze zu Deutsch
                confidence: topLabel.confidence,
                boundingBox: convertBoundingBox(observation.boundingBox),
                spatialData: nil,  // Wird später mit Depth kombiniert
                importance: importance
            )

            detectedObjects.append(object)
        }

        // Sortiere nach Wichtigkeit
        return detectedObjects.sorted { $0.importance > $1.importance }
    }

    /// Berechne Wichtigkeit basierend auf Objekttyp
    private func calculateImportance(label: String, confidence: Float) -> Float {
        var importance = confidence

        // Sehr wichtig für Navigation
        let criticalObjects = ["person", "car", "bus", "truck", "bicycle", "stairs"]
        if criticalObjects.contains(where: { label.contains($0) }) {
            importance += 0.3
        }

        // Wichtig für Orientierung
        let importantObjects = ["door", "window", "traffic light", "stop sign"]
        if importantObjects.contains(where: { label.contains($0) }) {
            importance += 0.2
        }

        // Hindernisse
        let obstacles = ["chair", "table", "bench", "potted plant"]
        if obstacles.contains(where: { label.contains($0) }) {
            importance += 0.1
        }

        return min(importance, 1.0)
    }

    /// Konvertiere Vision Bounding Box zu TRINITY Format
    private func convertBoundingBox(_ visionBox: CGRect) -> BoundingBox {
        // Vision nutzt normalized coordinates (0-1)
        // Origin ist bottom-left

        // Konvertiere zu center-based coordinates
        let centerX = Float(visionBox.midX)
        let centerY = Float(visionBox.midY)
        let width = Float(visionBox.width)
        let height = Float(visionBox.height)

        return BoundingBox(
            x: centerX,
            y: centerY,
            z: 0,  // Depth wird später hinzugefügt
            width: width,
            height: height,
            depth: 0
        )
    }

    /// Übersetze englische Labels zu Deutsch
    private func localizeLabel(_ label: String) -> String {
        let translations: [String: String] = [
            "person": "Person",
            "car": "Auto",
            "bus": "Bus",
            "truck": "LKW",
            "bicycle": "Fahrrad",
            "motorcycle": "Motorrad",
            "traffic light": "Ampel",
            "stop sign": "Stoppschild",
            "bench": "Bank",
            "chair": "Stuhl",
            "couch": "Sofa",
            "dining table": "Tisch",
            "door": "Tür",
            "window": "Fenster",
            "stairs": "Treppe",
            "potted plant": "Pflanze",
            "bottle": "Flasche",
            "cup": "Tasse",
            "bowl": "Schüssel",
            "laptop": "Laptop",
            "cell phone": "Handy",
            "book": "Buch"
        ]

        return translations[label] ?? label.capitalized
    }
}

// MARK: - Helper Extensions

extension DetectedObject {
    var importance: Float {
        get {
            // Berechne aus confidence und Objekttyp
            return confidence
        }
    }
}

extension CIContext {
    func createCVPixelBuffer(from ciImage: CIImage) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(ciImage.extent.width),
            Int(ciImage.extent.height),
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        render(ciImage, to: buffer)
        return buffer
    }
}

// MARK: - Usage Example

/*
 // Initialize Detector
 let detector = YOLOv8Detector()

 // Detect in Camera Frame
 if let pixelBuffer = arFrame.capturedImage {
     let objects = try await detector.detectObjects(in: pixelBuffer)

     for object in objects {
         print("\(object.label): \(object.confidence)")
         // "Person: 0.95"
         // "Auto: 0.87"
         // "Tür: 0.76"
     }
 }

 // Detect in UIImage
 let image = UIImage(named: "test.jpg")!
 let objects = try await detector.detectObjects(in: image)
 */
