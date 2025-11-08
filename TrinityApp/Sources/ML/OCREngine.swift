//
//  OCREngine.swift
//  TRINITY Vision Aid
//
//  Hochpräzise Text-Erkennung für Schilder, Beschriftungen, Dokumente
//

import Foundation
import Vision
import CoreImage
import UIKit

/// Fehlertypen für OCR
enum OCRError: Error {
    case noText
    case invalidImage
    case processingFailed(String)
    case unsupportedLanguage
}

/// Erkannter Text mit Metadaten
struct DetectedText: Identifiable, Codable {
    let id: UUID
    let text: String
    let confidence: Float
    let boundingBox: CGRect
    let language: String

    // Zusätzliche Metadaten
    var category: TextCategory
    var importance: Float

    enum TextCategory: String, Codable {
        case sign           // Straßenschild, Hinweisschild
        case label          // Produktbeschriftung, Etiketten
        case menu           // Speisekarte, Preise
        case document       // Dokument, Brief
        case navigation     // Wegweiser, Richtungsanzeigen
        case warning        // Warnhinweise
        case information    // Informationstafeln
        case unknown
    }
}

/// OCR Engine für Text-Erkennung
class OCREngine {
    // Unterstützte Sprachen
    private let supportedLanguages = ["de-DE", "en-US", "en-GB", "fr-FR", "es-ES", "it-IT"]

    // Recognition Level
    enum RecognitionLevel {
        case fast       // Schneller, weniger genau
        case accurate   // Langsamer, präziser (empfohlen)
    }

    private let recognitionLevel: RecognitionLevel
    private let minimumConfidence: Float = 0.5

    init(recognitionLevel: RecognitionLevel = .accurate) {
        self.recognitionLevel = recognitionLevel
    }

    /// Erkenne Text in Bild (CVPixelBuffer)
    func recognizeText(in image: CVPixelBuffer, languages: [String] = ["de-DE", "en-US"]) async throws -> [DetectedText] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.processingFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRError.noText)
                    return
                }

                let texts = self.processOCRResults(observations, requestedLanguages: languages)
                continuation.resume(returning: texts)
            }

            // Configure Request
            self.configureRequest(request, languages: languages)

            let handler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Erkenne Text in UIImage
    func recognizeText(in image: UIImage, languages: [String] = ["de-DE", "en-US"]) async throws -> [DetectedText] {
        guard let ciImage = CIImage(image: image) else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.processingFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRError.noText)
                    return
                }

                let texts = self.processOCRResults(observations, requestedLanguages: languages)
                continuation.resume(returning: texts)
            }

            self.configureRequest(request, languages: languages)

            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Konfiguriere OCR Request
    private func configureRequest(_ request: VNRecognizeTextRequest, languages: [String]) {
        // Recognition Level
        switch recognitionLevel {
        case .fast:
            request.recognitionLevel = .fast
        case .accurate:
            request.recognitionLevel = .accurate
        }

        // Sprachen
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true

        // Revision (neueste nutzen)
        if #available(iOS 16.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        } else if #available(iOS 14.0, *) {
            request.revision = VNRecognizeTextRequestRevision2
        }

        // Custom Words (für bessere Erkennung häufiger Wörter)
        request.customWords = germanAccessibilityWords()
    }

    /// Verarbeite OCR Results
    private func processOCRResults(
        _ observations: [VNRecognizedTextObservation],
        requestedLanguages: [String]
    ) -> [DetectedText] {
        var detectedTexts: [DetectedText] = []

        for observation in observations {
            // Get top candidates
            let candidates = observation.topCandidates(3)

            guard let topCandidate = candidates.first,
                  topCandidate.confidence >= minimumConfidence else {
                continue
            }

            let text = topCandidate.string
            let category = categorizeText(text)
            let importance = calculateImportance(text: text, category: category, confidence: topCandidate.confidence)

            let detectedText = DetectedText(
                id: UUID(),
                text: text,
                confidence: topCandidate.confidence,
                boundingBox: observation.boundingBox,
                language: detectLanguage(text, from: requestedLanguages),
                category: category,
                importance: importance
            )

            detectedTexts.append(detectedText)
        }

        // Sortiere nach Wichtigkeit
        return detectedTexts.sorted { $0.importance > $1.importance }
    }

    /// Kategorisiere erkannten Text
    private func categorizeText(_ text: String) -> DetectedText.TextCategory {
        let lowerText = text.lowercased()

        // Warning Signs
        let warningKeywords = ["achtung", "vorsicht", "warnung", "danger", "warning", "caution", "gefahr"]
        if warningKeywords.contains(where: { lowerText.contains($0) }) {
            return .warning
        }

        // Navigation
        let navigationKeywords = ["ausgang", "eingang", "exit", "entrance", "treppe", "aufzug", "elevator", "stairs"]
        if navigationKeywords.contains(where: { lowerText.contains($0) }) {
            return .navigation
        }

        // Signs
        let signKeywords = ["straße", "platz", "weg", "street", "road", "avenue"]
        if signKeywords.contains(where: { lowerText.contains($0) }) {
            return .sign
        }

        // Menu/Prices
        if lowerText.contains("€") || lowerText.contains("eur") || lowerText.contains("preis") {
            return .menu
        }

        // Information
        let infoKeywords = ["information", "info", "öffnungszeiten", "öffnet", "schließt", "hours"]
        if infoKeywords.contains(where: { lowerText.contains($0) }) {
            return .information
        }

        return .unknown
    }

    /// Berechne Wichtigkeit
    private func calculateImportance(text: String, category: DetectedText.TextCategory, confidence: Float) -> Float {
        var importance = confidence

        // Category-based importance
        switch category {
        case .warning:
            importance += 0.4  // Sehr wichtig!
        case .navigation:
            importance += 0.3
        case .sign:
            importance += 0.2
        case .information:
            importance += 0.1
        case .menu, .label, .document, .unknown:
            break
        }

        // Length-based (kürzere Texte sind oft wichtiger - Schilder)
        if text.count < 20 {
            importance += 0.1
        }

        // Numbers (Hausnummern, Preise) wichtiger
        if text.rangeOfCharacter(from: .decimalDigits) != nil {
            importance += 0.05
        }

        return min(importance, 1.0)
    }

    /// Erkenne Sprache des Texts
    private func detectLanguage(_ text: String, from candidates: [String]) -> String {
        // Simple heuristics für Deutsch
        let germanWords = ["der", "die", "das", "und", "oder", "ist", "sind", "ein", "eine", "für"]
        let lowerText = text.lowercased()

        for word in germanWords {
            if lowerText.contains(word) {
                return "de-DE"
            }
        }

        // Default zu erster Sprache
        return candidates.first ?? "de-DE"
    }

    /// Häufige deutsche Wörter für bessere Erkennung
    private func germanAccessibilityWords() -> [String] {
        return [
            // Navigation
            "Ausgang", "Eingang", "Notausgang", "Treppe", "Aufzug", "Fahrstuhl",
            "Toilette", "WC", "Herren", "Damen", "Behinderten-WC",

            // Warnings
            "Achtung", "Vorsicht", "Warnung", "Gefahr", "Verboten", "Zutritt",

            // Directions
            "Links", "Rechts", "Geradeaus", "Oben", "Unten", "Nord", "Süd", "Ost", "West",

            // Places
            "Bahnhof", "Haltestelle", "Bushaltestelle", "U-Bahn", "S-Bahn",
            "Apotheke", "Arzt", "Krankenhaus", "Polizei", "Feuerwehr",

            // Common
            "Öffnungszeiten", "Geöffnet", "Geschlossen", "Drücken", "Ziehen",
            "Parkplatz", "Fahrrad", "Fußgänger", "Straße", "Platz"
        ]
    }
}

// MARK: - Convenience Extensions

extension OCREngine {
    /// Quick Recognition für einfache Anwendungen
    func quickRecognize(in image: UIImage) async -> String {
        do {
            let texts = try await recognizeText(in: image)
            return texts.map { $0.text }.joined(separator: "\n")
        } catch {
            return ""
        }
    }

    /// Erkenne nur wichtige Texte (Warnings, Navigation)
    func recognizeImportantText(in image: CVPixelBuffer) async throws -> [DetectedText] {
        let allTexts = try await recognizeText(in: image)
        return allTexts.filter { $0.importance > 0.7 }
    }
}

// MARK: - Usage Example

/*
 // Initialize OCR Engine
 let ocr = OCREngine(recognitionLevel: .accurate)

 // Recognize in Camera Frame
 if let pixelBuffer = arFrame.capturedImage {
     let texts = try await ocr.recognizeText(in: pixelBuffer)

     for text in texts {
         print("\(text.category): \(text.text) (\(text.confidence))")
         // "navigation: Ausgang ← (0.95)"
         // "warning: Achtung Stufe! (0.89)"
         // "sign: Hauptstraße 42 (0.87)"
     }
 }

 // Recognize in Photo
 let image = UIImage(named: "street_sign.jpg")!
 let texts = try await ocr.recognizeText(in: image, languages: ["de-DE"])

 // Quick Recognition
 let fullText = await ocr.quickRecognize(in: image)
 print(fullText)  // "Hauptstraße 42\nNächster Ausgang 100m"
 */
