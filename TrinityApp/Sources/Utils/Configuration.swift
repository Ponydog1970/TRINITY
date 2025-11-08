//
//  Configuration.swift
//  TRINITY Vision Aid
//
//  Zentrale Konfiguration für API Keys und Einstellungen
//

import Foundation

/// App-Konfiguration mit API Keys
class Configuration {
    static let shared = Configuration()

    // MARK: - API Keys

    /// OpenAI API Key (optional)
    /// Hole von: https://platform.openai.com/api-keys
    var openAIKey: String? {
        get { UserDefaults.standard.string(forKey: "openai_api_key") }
        set { UserDefaults.standard.set(newValue, forKey: "openai_api_key") }
    }

    /// Anthropic Claude API Key (optional)
    /// Hole von: https://console.anthropic.com/settings/keys
    var claudeKey: String? {
        get { UserDefaults.standard.string(forKey: "claude_api_key") }
        set { UserDefaults.standard.set(newValue, forKey: "claude_api_key") }
    }

    // MARK: - Perception Mode

    enum PerceptionMode: String, CaseIterable {
        case localOnly = "Nur Lokal"
        case cloudEnhanced = "Cloud-Unterstützt"
        case cloudFirst = "Cloud Bevorzugt"

        var description: String {
            switch self {
            case .localOnly:
                return "Nur on-device Verarbeitung (privat, offline)"
            case .cloudEnhanced:
                return "Lokal + Cloud bei niedriger Confidence"
            case .cloudFirst:
                return "Cloud bevorzugt, Lokal als Fallback"
            }
        }
    }

    var perceptionMode: PerceptionMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "perception_mode") ?? "localOnly"
            return PerceptionMode(rawValue: raw) ?? .localOnly
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "perception_mode")
        }
    }

    // MARK: - Privacy Settings

    var allowCloudProcessing: Bool {
        get { UserDefaults.standard.bool(forKey: "allow_cloud_processing") }
        set { UserDefaults.standard.set(newValue, forKey: "allow_cloud_processing") }
    }

    var sendAnonymizedTelemetry: Bool {
        get { UserDefaults.standard.bool(forKey: "send_telemetry") }
        set { UserDefaults.standard.set(newValue, forKey: "send_telemetry") }
    }

    // MARK: - API Usage Limits

    var maxCloudCallsPerDay: Int {
        get { UserDefaults.standard.integer(forKey: "max_cloud_calls") }
        set { UserDefaults.standard.set(newValue, forKey: "max_cloud_calls") }
    }

    var cloudCallsToday: Int {
        get { UserDefaults.standard.integer(forKey: "cloud_calls_today") }
        set { UserDefaults.standard.set(newValue, forKey: "cloud_calls_today") }
    }

    // MARK: - Validation

    func hasValidOpenAIKey() -> Bool {
        guard let key = openAIKey else { return false }
        return key.hasPrefix("sk-") && key.count > 20
    }

    func hasValidClaudeKey() -> Bool {
        guard let key = claudeKey else { return false }
        return key.hasPrefix("sk-ant-") && key.count > 20
    }

    func canUseCloudAPIs() -> Bool {
        guard allowCloudProcessing else { return false }
        return hasValidOpenAIKey() || hasValidClaudeKey()
    }

    // MARK: - Rate Limiting

    func incrementCloudCalls() {
        cloudCallsToday += 1
    }

    func hasReachedCloudLimit() -> Bool {
        guard maxCloudCallsPerDay > 0 else { return false }
        return cloudCallsToday >= maxCloudCallsPerDay
    }

    func resetDailyCloudCalls() {
        cloudCallsToday = 0
    }

    // MARK: - Cost Estimation

    func estimatedMonthlyCost() -> Double {
        // Basis auf durchschnittlicher Nutzung
        let callsPerDay = Double(cloudCallsToday)

        // OpenAI GPT-4 Vision: ~$0.01 pro Request
        // Claude Vision: ~$0.008 pro Request
        let costPerCall = 0.01

        return callsPerDay * 30 * costPerCall
    }
}

// MARK: - Environment Variables (für Entwicklung)

extension Configuration {
    /// Lade API Keys aus Environment (für Testing/Development)
    func loadFromEnvironment() {
        if let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            self.openAIKey = openAIKey
        }

        if let claudeKey = ProcessInfo.processInfo.environment["CLAUDE_API_KEY"] {
            self.claudeKey = claudeKey
        }
    }

    /// Lade aus .env File (nicht für Production!)
    func loadFromFile(path: String = ".env") {
        guard let data = try? String(contentsOfFile: path) else { return }

        let lines = data.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: "=")
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "OPENAI_API_KEY":
                openAIKey = value
            case "CLAUDE_API_KEY":
                claudeKey = value
            default:
                break
            }
        }
    }
}

// MARK: - Security Helpers

extension Configuration {
    /// Maskiere API Key für Anzeige (zeige nur ersten/letzten Teil)
    func maskedKey(_ key: String?) -> String {
        guard let key = key, key.count > 8 else { return "Nicht gesetzt" }

        let prefix = String(key.prefix(7))
        let suffix = String(key.suffix(4))
        return "\(prefix)...\(suffix)"
    }

    /// Lösche alle API Keys (für Logout/Reset)
    func clearAllKeys() {
        openAIKey = nil
        claudeKey = nil
    }

    /// Export Einstellungen (ohne API Keys!)
    func exportSettings() -> [String: Any] {
        return [
            "perception_mode": perceptionMode.rawValue,
            "allow_cloud_processing": allowCloudProcessing,
            "max_cloud_calls": maxCloudCallsPerDay
        ]
    }

    /// Import Einstellungen
    func importSettings(_ settings: [String: Any]) {
        if let mode = settings["perception_mode"] as? String,
           let perceptionMode = PerceptionMode(rawValue: mode) {
            self.perceptionMode = perceptionMode
        }

        if let allow = settings["allow_cloud_processing"] as? Bool {
            allowCloudProcessing = allow
        }

        if let maxCalls = settings["max_cloud_calls"] as? Int {
            maxCloudCallsPerDay = maxCalls
        }
    }
}

// MARK: - Usage Examples

/*
 // API Keys setzen:
 Configuration.shared.openAIKey = "sk-..."
 Configuration.shared.claudeKey = "sk-ant-..."

 // Mode setzen:
 Configuration.shared.perceptionMode = .cloudEnhanced

 // Prüfen:
 if Configuration.shared.canUseCloudAPIs() {
     // Nutze Cloud APIs
 }

 // Rate Limiting:
 if !Configuration.shared.hasReachedCloudLimit() {
     Configuration.shared.incrementCloudCalls()
     // Make API call
 }

 // Kosten schätzen:
 let cost = Configuration.shared.estimatedMonthlyCost()
 print("Geschätzte Kosten: $\(cost)/Monat")
 */
