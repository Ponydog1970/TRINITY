//
//  AnthropicClient.swift
//  TRINITY Vision Aid
//
//  Optional: Anthropic Claude API für erweiterte Reasoning-Fähigkeiten
//

import Foundation

/// Client für Anthropic Claude API (optional)
class AnthropicClient {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1"
    private let model = "claude-3-5-sonnet-20241022" // Neuestes Model

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Vision Analysis

    /// Analysiert Bild mit Claude Vision für detaillierte Szenenbeschreibung
    func analyzeScene(
        _ imageData: Data,
        context: String? = nil
    ) async throws -> SceneAnalysis {
        let base64Image = imageData.base64EncodedString()

        let systemPrompt = """
        Du bist eine hochpräzise Navigationshilfe für blinde Menschen.

        Deine Aufgabe:
        1. Erkenne ALLE Hindernisse im Bild
        2. Schätze Distanzen so genau wie möglich
        3. Beschreibe die räumliche Anordnung
        4. Priorisiere Sicherheitsrelevante Objekte
        5. Antworte auf Deutsch, klar und präzise

        Format der Antwort (JSON):
        {
          "objects": [
            {"name": "Tisch", "distance": "0.5m", "direction": "links", "risk": "mittel"},
            ...
          ],
          "scene_description": "Kurze Beschreibung des Raums",
          "navigation_advice": "Konkrete Navigationsempfehlung",
          "warnings": ["Liste kritischer Warnungen"]
        }
        """

        var userContent: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64Image
                ]
            ],
            [
                "type": "text",
                "text": "Analysiere diese Szene für Navigation einer blinden Person."
            ]
        ]

        if let context = context {
            userContent.append([
                "type": "text",
                "text": "Zusätzlicher Kontext: \(context)"
            ])
        }

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": userContent
                ]
            ]
        ]

        let response = try await makeRequest(
            endpoint: "/messages",
            body: requestBody
        )

        // Parse JSON response
        guard let content = response["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw AnthropicError.invalidResponse
        }

        // Parse JSON aus Text
        return try parseSceneAnalysis(from: text)
    }

    // MARK: - Context-Aware Navigation

    /// Generiert kontextbewusste Navigationsbeschreibung
    func generateContextualNavigation(
        currentObservation: String,
        recentHistory: [String],
        knownLocation: String?
    ) async throws -> String {
        let historyText = recentHistory.joined(separator: "\n- ")

        var prompt = """
        Aktuelle Beobachtung: \(currentObservation)

        Letzte Beobachtungen:
        - \(historyText)
        """

        if let location = knownLocation {
            prompt += "\n\nBekannter Ort: \(location)"
        }

        prompt += """

        Generiere eine kurze (max 2 Sätze) Navigationsbeschreibung auf Deutsch.
        Nutze den Kontext, um hilfreicher zu sein.
        """

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 150,
            "system": "Du bist eine präzise, kontextbewusste Navigationshilfe.",
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]

        let response = try await makeRequest(
            endpoint: "/messages",
            body: requestBody
        )

        guard let content = response["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw AnthropicError.invalidResponse
        }

        return text
    }

    // MARK: - Reasoning über Memory

    /// Verwendet Claude für intelligente Memory-Konsolidierung
    func consolidateMemories(
        memories: [String]
    ) async throws -> [String] {
        let memoriesText = memories.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        let prompt = """
        Folgende Erinnerungen wurden gesammelt:

        \(memoriesText)

        Aufgabe:
        1. Identifiziere Duplikate
        2. Finde Muster
        3. Konsolidiere zu nicht-redundanten Kern-Erinnerungen
        4. Sortiere nach Wichtigkeit

        Gib nur die konsolidierten Erinnerungen zurück, eine pro Zeile.
        """

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 500,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]

        let response = try await makeRequest(
            endpoint: "/messages",
            body: requestBody
        )

        guard let content = response["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw AnthropicError.invalidResponse
        }

        // Split by newlines
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Network

    private func makeRequest(
        endpoint: String,
        body: [String: Any]
    ) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + endpoint) else {
            throw AnthropicError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AnthropicError.httpError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnthropicError.invalidResponse
        }

        return json
    }

    private func parseSceneAnalysis(from text: String) throws -> SceneAnalysis {
        // Versuche JSON zu parsen
        if let jsonStart = text.range(of: "{"),
           let jsonEnd = text.range(of: "}", options: .backwards) {
            let jsonString = String(text[jsonStart.lowerBound...jsonEnd.upperBound])

            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                let objects = (json["objects"] as? [[String: Any]])?.compactMap { obj -> DetectedNavigationObject? in
                    guard let name = obj["name"] as? String,
                          let distance = obj["distance"] as? String,
                          let direction = obj["direction"] as? String else {
                        return nil
                    }
                    return DetectedNavigationObject(
                        name: name,
                        distance: distance,
                        direction: direction,
                        risk: obj["risk"] as? String ?? "niedrig"
                    )
                } ?? []

                return SceneAnalysis(
                    objects: objects,
                    sceneDescription: json["scene_description"] as? String ?? "",
                    navigationAdvice: json["navigation_advice"] as? String ?? "",
                    warnings: json["warnings"] as? [String] ?? []
                )
            }
        }

        // Fallback: Nutze rohen Text
        return SceneAnalysis(
            objects: [],
            sceneDescription: text,
            navigationAdvice: "",
            warnings: []
        )
    }
}

// MARK: - Data Models

struct SceneAnalysis {
    let objects: [DetectedNavigationObject]
    let sceneDescription: String
    let navigationAdvice: String
    let warnings: [String]
}

struct DetectedNavigationObject {
    let name: String
    let distance: String
    let direction: String
    let risk: String
}

enum AnthropicError: Error {
    case invalidURL
    case invalidResponse
    case httpError
    case parseError

    var localizedDescription: String {
        switch self {
        case .invalidURL: return "Ungültige URL"
        case .invalidResponse: return "Ungültige Antwort"
        case .httpError: return "HTTP Fehler"
        case .parseError: return "Parse Fehler"
        }
    }
}

// MARK: - Usage Example

/*
 // In PerceptionAgent oder TrinityCoordinator:

 let claude = AnthropicClient(apiKey: "sk-ant-...")

 // Szene analysieren:
 if let imageData = observation.cameraImage {
     let analysis = try await claude.analyzeScene(
         imageData,
         context: "Innenraum, Wohnzimmer"
     )

     print("Objekte: \(analysis.objects)")
     print("Beschreibung: \(analysis.sceneDescription)")
     print("Navigation: \(analysis.navigationAdvice)")
     print("Warnungen: \(analysis.warnings)")
 }

 // Kontext-Navigation:
 let navText = try await claude.generateContextualNavigation(
     currentObservation: "Tisch vor mir",
     recentHistory: ["War im Flur", "Tür nach links"],
     knownLocation: "Wohnzimmer"
 )

 // Memory konsolidieren:
 let consolidated = try await claude.consolidateMemories(
     memories: memoryManager.episodicMemory.map { $0.metadata.description }
 )
 */
