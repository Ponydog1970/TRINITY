//
//  OpenAIClient.swift
//  TRINITY Vision Aid
//
//  Optional: OpenAI API Integration für erweiterte Bildbeschreibungen
//

import Foundation
import UIKit

/// Client für OpenAI API (optional, erfordert API Key)
class OpenAIClient {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Vision API (GPT-4 Vision)

    /// Generiert detaillierte Bildbeschreibung mit GPT-4 Vision
    func describeImage(
        _ imageData: Data,
        prompt: String = "Beschreibe diese Szene für eine blinde Person. Fokussiere auf Hindernisse und Navigation."
    ) async throws -> String {
        let base64Image = imageData.base64EncodedString()

        let requestBody: [String: Any] = [
            "model": "gpt-4-vision-preview",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 300
        ]

        let response = try await makeRequest(
            endpoint: "/chat/completions",
            body: requestBody
        )

        guard let choices = response["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }

        return content
    }

    // MARK: - Text Generation (GPT-4)

    /// Generiert natürliche Navigationsbeschreibung
    func generateNavigationDescription(
        objects: [String],
        distances: [Float],
        context: String
    ) async throws -> String {
        let objectList = zip(objects, distances)
            .map { "\($0) (\($1)m entfernt)" }
            .joined(separator: ", ")

        let prompt = """
        Du bist eine Navigationshilfe für blinde Menschen.

        Erkannte Objekte: \(objectList)
        Kontext: \(context)

        Generiere eine kurze (1-2 Sätze), klare Navigationsbeschreibung auf Deutsch.
        Fokus auf Sicherheit und wichtige Hindernisse.
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                [
                    "role": "system",
                    "content": "Du bist eine präzise Navigationshilfe für Menschen mit Sehbehinderung."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": 100,
            "temperature": 0.3
        ]

        let response = try await makeRequest(
            endpoint: "/chat/completions",
            body: requestBody
        )

        guard let choices = response["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }

        return content
    }

    // MARK: - Embeddings

    /// Generiert Text-Embedding mit OpenAI (alternative zu lokalen Embeddings)
    func generateEmbedding(text: String) async throws -> [Float] {
        let requestBody: [String: Any] = [
            "model": "text-embedding-3-small",
            "input": text
        ]

        let response = try await makeRequest(
            endpoint: "/embeddings",
            body: requestBody
        )

        guard let data = response["data"] as? [[String: Any]],
              let first = data.first,
              let embedding = first["embedding"] as? [Double] else {
            throw OpenAIError.invalidResponse
        }

        return embedding.map { Float($0) }
    }

    // MARK: - Network Request

    private func makeRequest(
        endpoint: String,
        body: [String: Any]
    ) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + endpoint) else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OpenAIError.httpError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIError.invalidResponse
        }

        return json
    }
}

// MARK: - Errors

enum OpenAIError: Error {
    case invalidURL
    case invalidResponse
    case httpError
    case rateLimitExceeded

    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Ungültige API URL"
        case .invalidResponse:
            return "Ungültige API Antwort"
        case .httpError:
            return "HTTP Fehler"
        case .rateLimitExceeded:
            return "Rate Limit überschritten"
        }
    }
}

// MARK: - Usage Example

/*
 // In TrinityCoordinator.swift oder PerceptionAgent.swift:

 let openAI = OpenAIClient(apiKey: "sk-...")

 // Bild beschreiben:
 if let imageData = observation.cameraImage {
     let description = try await openAI.describeImage(imageData)
     print("GPT-4 Vision: \(description)")
 }

 // Navigation generieren:
 let navDescription = try await openAI.generateNavigationDescription(
     objects: ["Tisch", "Stuhl", "Tür"],
     distances: [0.5, 1.2, 3.0],
     context: "Wohnzimmer, Nachmittag"
 )

 // Embedding generieren:
 let embedding = try await openAI.generateEmbedding(
     text: "Tisch vor mir"
 )
 */
