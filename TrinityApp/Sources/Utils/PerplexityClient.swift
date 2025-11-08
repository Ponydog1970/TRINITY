//
//  PerplexityClient.swift
//  TRINITY Vision Aid
//
//  Perplexity API integration for web-grounded responses and search
//

import Foundation

/// Client for Perplexity API (Sonar models for web search + reasoning)
class PerplexityClient {
    private let apiKey: String
    private let baseURL = "https://api.perplexity.ai"

    // Available Perplexity models
    enum Model: String, CaseIterable {
        case sonarSmall = "sonar-small-online"      // Fast, web-grounded
        case sonar = "sonar"                        // Standard online
        case sonarPro = "sonar-pro"                 // Best quality, online
        case sonarHuge = "sonar-huge"               // Most capable

        var displayName: String {
            switch self {
            case .sonarSmall: return "Sonar Small (Online)"
            case .sonar: return "Sonar (Online)"
            case .sonarPro: return "Sonar Pro (Online)"
            case .sonarHuge: return "Sonar Huge (Online)"
            }
        }

        var description: String {
            switch self {
            case .sonarSmall: return "Schnell, web-basiert, günstig"
            case .sonar: return "Standard, web-basiert"
            case .sonarPro: return "Beste Qualität, teurer"
            case .sonarHuge: return "Maximale Leistung"
            }
        }

        var estimatedCostPer1kTokens: Double {
            switch self {
            case .sonarSmall: return 0.0002
            case .sonar: return 0.0005
            case .sonarPro: return 0.001
            case .sonarHuge: return 0.005
            }
        }
    }

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Web-Grounded Chat

    /// Web-grounded chat completion (mit aktuellen Internet-Daten)
    func chat(
        messages: [ChatMessage],
        model: Model = .sonar,
        searchDomain: String? = nil,
        returnCitations: Bool = true
    ) async throws -> PerplexityResponse {

        var requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": messages.map { $0.toDictionary() },
            "return_citations": returnCitations
        ]

        if let domain = searchDomain {
            requestBody["search_domain_filter"] = [domain]
        }

        let response = try await makeRequest(
            endpoint: "/chat/completions",
            body: requestBody
        )

        return try parseResponse(response)
    }

    // MARK: - Location-Based Search

    /// Sucht nach Informationen zu einem Ort (web-basiert)
    func searchLocation(
        _ locationName: String,
        query: String,
        model: Model = .sonar
    ) async throws -> PerplexityResponse {

        let messages = [
            ChatMessage(
                role: .system,
                content: "Du bist ein hilfreicher Assistent für Menschen mit Sehbehinderung. Gib präzise, strukturierte Informationen."
            ),
            ChatMessage(
                role: .user,
                content: "Informationen zu '\(locationName)': \(query). Fokus auf Navigation und Zugänglichkeit."
            )
        ]

        return try await chat(messages: messages, model: model)
    }

    // MARK: - Object Information

    /// Holt aktuelle Web-Informationen zu einem erkannten Objekt
    func getObjectInfo(
        objectType: String,
        context: String?,
        model: Model = .sonarSmall
    ) async throws -> String {

        var prompt = "Kurze Info zu: \(objectType)"
        if let ctx = context {
            prompt += " (Kontext: \(ctx))"
        }
        prompt += ". Max 2 Sätze, relevant für Navigation."

        let messages = [
            ChatMessage(role: .user, content: prompt)
        ]

        let response = try await chat(messages: messages, model: model)
        return response.content
    }

    // MARK: - Scene Analysis with Web Context

    /// Analysiert Szene mit Web-Kontext
    func analyzeSceneWithWebContext(
        sceneDescription: String,
        location: String?,
        model: Model = .sonar
    ) async throws -> PerplexityResponse {

        var prompt = "Szene: \(sceneDescription)"

        if let loc = location {
            prompt += "\nOrt: \(loc)"
            prompt += "\n\nGib Kontext zu diesem Ort: Bekannte Gefahren? Besonderheiten? Barrierefreiheit?"
        }

        let messages = [
            ChatMessage(
                role: .system,
                content: "Du hilfst Menschen mit Sehbehinderung. Nutze aktuelle Web-Informationen."
            ),
            ChatMessage(role: .user, content: prompt)
        ]

        return try await chat(messages: messages, model: model)
    }

    // MARK: - Route Information

    /// Holt Routen-Informationen (ÖPNV, Wege, etc.)
    func getRouteInfo(
        from: String,
        to: String,
        preferences: [String] = ["barrierefrei", "ÖPNV"],
        model: Model = .sonarPro
    ) async throws -> RouteInfo {

        let prefsText = preferences.joined(separator: ", ")
        let prompt = """
        Route von '\(from)' nach '\(to)'.
        Präferenzen: \(prefsText)

        Gib zurück (strukturiert):
        1. Beste Route
        2. Dauer
        3. ÖPNV-Verbindungen
        4. Barrierefreiheit
        5. Alternativ-Routen
        """

        let messages = [
            ChatMessage(role: .user, content: prompt)
        ]

        let response = try await chat(messages: messages, model: model)

        return RouteInfo(
            description: response.content,
            citations: response.citations,
            estimatedDuration: nil // Könnte geparst werden
        )
    }

    // MARK: - Network

    private func makeRequest(
        endpoint: String,
        body: [String: Any]
    ) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + endpoint) else {
            throw PerplexityError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PerplexityError.httpError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PerplexityError.invalidResponse
        }

        return json
    }

    private func parseResponse(_ json: [String: Any]) throws -> PerplexityResponse {
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PerplexityError.parseError
        }

        // Citations (optional)
        let citations = json["citations"] as? [String] ?? []

        return PerplexityResponse(
            content: content,
            citations: citations,
            model: json["model"] as? String
        )
    }
}

// MARK: - Data Models

struct ChatMessage {
    let role: Role
    let content: String

    enum Role: String {
        case system
        case user
        case assistant
    }

    func toDictionary() -> [String: String] {
        return [
            "role": role.rawValue,
            "content": content
        ]
    }
}

struct PerplexityResponse {
    let content: String
    let citations: [String]
    let model: String?
}

struct RouteInfo {
    let description: String
    let citations: [String]
    let estimatedDuration: TimeInterval?
}

enum PerplexityError: Error {
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

// MARK: - Usage Examples

/*
 let perplexity = PerplexityClient(apiKey: "pplx-...")

 // Orts-Info:
 let locationInfo = try await perplexity.searchLocation(
     "Hauptbahnhof Berlin",
     query: "Barrierefreiheit, Ausgänge, aktuelle Infos"
 )
 print(locationInfo.content)
 print("Quellen: \(locationInfo.citations)")

 // Objekt-Info:
 let objectInfo = try await perplexity.getObjectInfo(
     objectType: "Ampel",
     context: "Kreuzung",
     model: .sonarSmall
 )

 // Routen-Info:
 let route = try await perplexity.getRouteInfo(
     from: "Alexanderplatz",
     to: "Brandenburger Tor",
     preferences: ["barrierefrei", "schnell"]
 )
 */
