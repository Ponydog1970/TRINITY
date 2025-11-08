//
//  EnhancedSettingsView.swift
//  TRINITY Vision Aid
//
//  Erweiterte Settings mit API-Konfiguration
//

import SwiftUI

struct EnhancedSettingsView: View {
    @EnvironmentObject var coordinator: TrinityCoordinator
    @Environment(\.dismiss) var dismiss

    @State private var verbosityLevel = 1
    @State private var perceptionMode = Configuration.shared.perceptionMode
    @State private var allowCloud = Configuration.shared.allowCloudProcessing

    @State private var openAIKey = Configuration.shared.openAIKey ?? ""
    @State private var claudeKey = Configuration.shared.claudeKey ?? ""

    @State private var showAPIKeys = false
    @State private var maxCloudCalls = Configuration.shared.maxCloudCallsPerDay

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Voice Settings
                Section("Sprachausgabe") {
                    Picker("Detailgrad", selection: $verbosityLevel) {
                        Text("Minimal").tag(0)
                        Text("Medium").tag(1)
                        Text("Detailliert").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: verbosityLevel) { _, newValue in
                        updateVerbosity(newValue)
                    }
                }

                // MARK: - Perception Mode
                Section {
                    Picker("Erkennungs-Modus", selection: $perceptionMode) {
                        ForEach(Configuration.PerceptionMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .onChange(of: perceptionMode) { _, newValue in
                        Configuration.shared.perceptionMode = newValue
                    }

                    Text(perceptionMode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)

                } header: {
                    Text("Erkennungsmodus")
                } footer: {
                    if perceptionMode != .localOnly {
                        Text("⚠️ Cloud-Modi senden Bilder an externe Server")
                            .foregroundColor(.orange)
                    }
                }

                // MARK: - Cloud APIs
                if perceptionMode != .localOnly {
                    Section("Cloud-APIs") {
                        Toggle("Cloud-Verarbeitung erlauben", isOn: $allowCloud)
                            .onChange(of: allowCloud) { _, newValue in
                                Configuration.shared.allowCloudProcessing = newValue
                            }

                        if allowCloud {
                            NavigationLink("API Keys konfigurieren") {
                                APIKeysView(
                                    openAIKey: $openAIKey,
                                    claudeKey: $claudeKey
                                )
                            }

                            // Status
                            HStack {
                                Text("OpenAI")
                                Spacer()
                                StatusIcon(isValid: Configuration.shared.hasValidOpenAIKey())
                            }

                            HStack {
                                Text("Claude")
                                Spacer()
                                StatusIcon(isValid: Configuration.shared.hasValidClaudeKey())
                            }

                            // Rate Limiting
                            Stepper("Max. Anfragen/Tag: \(maxCloudCalls)", value: $maxCloudCalls, in: 0...1000, step: 10)
                                .onChange(of: maxCloudCalls) { _, newValue in
                                    Configuration.shared.maxCloudCallsPerDay = newValue
                                }

                            // Usage
                            HStack {
                                Text("Heute verwendet")
                                Spacer()
                                Text("\(Configuration.shared.cloudCallsToday) / \(maxCloudCalls)")
                                    .foregroundColor(.secondary)
                            }

                            // Cost Estimation
                            let estimatedCost = Configuration.shared.estimatedMonthlyCost()
                            if estimatedCost > 0 {
                                HStack {
                                    Text("Geschätzte Kosten/Monat")
                                    Spacer()
                                    Text("$\(String(format: "%.2f", estimatedCost))")
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }

                // MARK: - Privacy
                Section("Datenschutz") {
                    Toggle("Cloud-Verarbeitung", isOn: $allowCloud)

                    if allowCloud {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Daten werden an externe Server gesendet", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)

                            Text("Bilder werden an OpenAI/Anthropic gesendet für bessere Erkennung")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Label("Alle Daten bleiben auf dem Gerät", systemImage: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }

                // MARK: - Memory
                Section("Gedächtnis") {
                    Button("Erinnerungen konsolidieren") {
                        Task {
                            await coordinator.consolidateMemories()
                        }
                    }

                    Button("Alle Erinnerungen löschen") {
                        coordinator.clearAllMemories()
                    }
                    .foregroundColor(.red)

                    // Statistics
                    Task {
                        if let stats = try? await coordinator.getSystemStatistics() {
                            VStack(alignment: .leading, spacing: 4) {
                                StatRow(title: "Working Memory", value: "\(stats.workingMemorySize)")
                                StatRow(title: "Episodic Memory", value: "\(stats.episodicMemorySize)")
                                StatRow(title: "Semantic Memory", value: "\(stats.semanticMemorySize)")
                            }
                            .font(.caption)
                        }
                    }
                }

                // MARK: - Data
                Section("Daten") {
                    Button("Nach iCloud exportieren") {
                        Task {
                            _ = try? await coordinator.exportMemories()
                        }
                    }

                    Button("Von iCloud importieren") {
                        // Show file picker
                    }

                    if allowCloud {
                        Button("API Keys löschen") {
                            Configuration.shared.clearAllKeys()
                            openAIKey = ""
                            claudeKey = ""
                        }
                        .foregroundColor(.red)
                    }
                }

                // MARK: - About
                Section("Info") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Erkennungsmodus")
                        Spacer()
                        Text(perceptionMode.rawValue)
                            .foregroundColor(.secondary)
                    }

                    if allowCloud {
                        HStack {
                            Text("Cloud-Status")
                            Spacer()
                            if Configuration.shared.canUseCloudAPIs() {
                                Text("Aktiv")
                                    .foregroundColor(.green)
                            } else {
                                Text("Inaktiv")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func updateVerbosity(_ level: Int) {
        let verbosity: CommunicationAgent.VerbosityLevel
        switch level {
        case 0: verbosity = .minimal
        case 2: verbosity = .detailed
        default: verbosity = .medium
        }
        coordinator.adjustVerbosity(verbosity)
    }
}

// MARK: - API Keys View

struct APIKeysView: View {
    @Binding var openAIKey: String
    @Binding var claudeKey: String

    @State private var showOpenAIKey = false
    @State private var showClaudeKey = false

    var body: some View {
        Form {
            Section {
                HStack {
                    if showOpenAIKey {
                        TextField("sk-...", text: $openAIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Text(Configuration.shared.maskedKey(openAIKey))
                            .foregroundColor(.secondary)
                    }

                    Button(action: { showOpenAIKey.toggle() }) {
                        Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                    }
                }

                Button("Speichern") {
                    Configuration.shared.openAIKey = openAIKey
                }
                .disabled(openAIKey.isEmpty)

                Link("API Key holen", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)

            } header: {
                Text("OpenAI API Key")
            } footer: {
                Text("Für GPT-4 Vision Bildbeschreibungen")
            }

            Section {
                HStack {
                    if showClaudeKey {
                        TextField("sk-ant-...", text: $claudeKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Text(Configuration.shared.maskedKey(claudeKey))
                            .foregroundColor(.secondary)
                    }

                    Button(action: { showClaudeKey.toggle() }) {
                        Image(systemName: showClaudeKey ? "eye.slash" : "eye")
                    }
                }

                Button("Speichern") {
                    Configuration.shared.claudeKey = claudeKey
                }
                .disabled(claudeKey.isEmpty)

                Link("API Key holen", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)

            } header: {
                Text("Anthropic Claude API Key")
            } footer: {
                Text("Für Claude 3.5 Sonnet Vision-Analyse")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("API Keys werden lokal gespeichert", systemImage: "lock.fill")
                        .font(.caption)

                    Label("Niemals mit anderen teilen!", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)

                    Text("Kosten fallen direkt bei OpenAI/Anthropic an")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Sicherheitshinweise")
            }
        }
        .navigationTitle("API Keys")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helper Views

struct StatusIcon: View {
    let isValid: Bool

    var body: some View {
        Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundColor(isValid ? .green : .red)
    }
}

struct StatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

struct EnhancedSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedSettingsView()
            .environmentObject(try! TrinityCoordinator())
    }
}
