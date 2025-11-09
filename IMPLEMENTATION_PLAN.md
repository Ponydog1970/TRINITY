# 🚀 TRINITY - Konkreter Implementierungsplan

**Erstellt:** 2025-11-09
**Basis:** Comprehensive Analysis Report (88/100)
**Status:** Bereit für Implementierung
**ETA bis Production:** 2-4 Wochen

---

## 📋 Übersicht

Dieser Plan adressiert alle im Analysebericht identifizierten Verbesserungen, priorisiert nach **Impact vs. Aufwand**.

### Priorisierungs-Matrix

```
        HIGH IMPACT              MEDIUM IMPACT           LOW IMPACT
      ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
      │                  │    │                  │    │                  │
LOW   │  🎯 QUICK WINS   │    │  5. Settings     │    │  10. Binary      │
      │  4. ML Models    │    │  6. Cache Fix    │    │      Storage     │
EFFORT│  8. Biometric    │    │                  │    │                  │
      │                  │    │                  │    │                  │
      ├──────────────────┤    ├──────────────────┤    ├──────────────────┤
      │                  │    │                  │    │                  │
MED   │  🔴 CRITICAL     │    │  9. Phase 2      │    │                  │
      │  2. Error UI     │    │     Features     │    │                  │
EFFORT│  7. Emergency    │    │                  │    │                  │
      │                  │    │                  │    │                  │
      ├──────────────────┤    ├──────────────────┤    ├──────────────────┤
      │                  │    │                  │    │                  │
HIGH  │  🔴 CRITICAL     │    │                  │    │                  │
      │  1. Voice Input  │    │                  │    │                  │
EFFORT│  3. Onboarding   │    │                  │    │                  │
      │                  │    │                  │    │                  │
      └──────────────────┘    └──────────────────┘    └──────────────────┘
```

---

## 🔴 PHASE 1: KRITISCHE FEATURES (Woche 1-2)

### ✅ Feature 1: Voice Input (Speech Recognition)

**Priorität:** 🔴 CRITICAL
**Aufwand:** High (3-5 Tage)
**Impact:** High (Hands-free essentiell für Sehbehinderte)
**Dependencies:** iOS 17+, SpeechRecognition Framework

#### Implementierungsschritte

**Schritt 1.1: VoiceCommandManager erstellen**

```swift
// Neue Datei: TrinityApp/Sources/Utils/VoiceCommandManager.swift

import Foundation
import Speech
import AVFoundation

/// Verwaltet Spracheingabe und Voice Commands
@MainActor
class VoiceCommandManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isListening: Bool = false
    @Published var recognizedText: String = ""
    @Published var lastCommand: VoiceCommand?

    // MARK: - Configuration

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Wake word detection
    private let wakeWords = ["hey trinity", "trinity", "hallo trinity"]
    private var isWakeWordDetected = false

    // Command timeout
    private var commandTimer: Timer?
    private let commandTimeout: TimeInterval = 5.0

    // MARK: - Supported Commands

    enum VoiceCommand: String, CaseIterable {
        case describeScene = "beschreibe szene"
        case describeSceneAlt = "was siehst du"
        case repeatLast = "wiederhole"
        case repeatLastAlt = "noch einmal"
        case startNavigation = "navigation starten"
        case stopNavigation = "navigation stoppen"
        case emergency = "notfall"
        case emergencyAlt = "hilfe"
        case stop = "stopp"
        case stopAlt = "stop"

        var action: String {
            switch self {
            case .describeScene, .describeSceneAlt:
                return "describeScene"
            case .repeatLast, .repeatLastAlt:
                return "repeatLast"
            case .startNavigation:
                return "startNavigation"
            case .stopNavigation:
                return "stopNavigation"
            case .emergency, .emergencyAlt:
                return "emergency"
            case .stop, .stopAlt:
                return "stopListening"
            }
        }
    }

    // MARK: - Callback

    var onCommandRecognized: ((String) -> Void)?

    // MARK: - Initialization

    override init() {
        // Deutsch und Englisch Support
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
        super.init()

        speechRecognizer?.delegate = self
    }

    // MARK: - Permission Handling

    func requestPermissions() async -> Bool {
        // Speech Recognition Permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard speechStatus else {
            print("❌ Speech recognition permission denied")
            return false
        }

        // Microphone Permission
        let micStatus = await AVAudioApplication.requestRecordPermission()

        guard micStatus else {
            print("❌ Microphone permission denied")
            return false
        }

        return true
    }

    // MARK: - Listening Control

    func startListening() async throws {
        guard !isListening else { return }

        // Check permissions
        let hasPermission = await requestPermissions()
        guard hasPermission else {
            throw VoiceError.permissionDenied
        }

        // Cancel previous task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw VoiceError.setupFailed
        }

        recognitionRequest.shouldReportPartialResults = true

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        // Start recognition
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result: result, error: error)
            }
        }

        isListening = true
        print("🎤 Voice input started")
    }

    func stopListening() {
        guard isListening else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
        isWakeWordDetected = false

        print("🎤 Voice input stopped")
    }

    // MARK: - Recognition Handling

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            print("❌ Recognition error: \(error)")
            stopListening()
            return
        }

        guard let result = result else { return }

        let transcript = result.bestTranscription.formattedString.lowercased()
        recognizedText = transcript

        // Wake word detection
        if !isWakeWordDetected {
            for wakeWord in wakeWords {
                if transcript.contains(wakeWord) {
                    isWakeWordDetected = true
                    print("👂 Wake word detected: \(wakeWord)")

                    // Provide feedback
                    playActivationSound()

                    // Start command timeout
                    resetCommandTimer()
                    return
                }
            }
            return
        }

        // Command recognition (only after wake word)
        for command in VoiceCommand.allCases {
            if transcript.contains(command.rawValue) {
                print("✅ Command recognized: \(command.rawValue)")

                lastCommand = command
                onCommandRecognized?(command.action)

                // Reset for next command
                isWakeWordDetected = false
                commandTimer?.invalidate()

                return
            }
        }

        // Reset command timeout
        resetCommandTimer()
    }

    private func resetCommandTimer() {
        commandTimer?.invalidate()
        commandTimer = Timer.scheduledTimer(withTimeInterval: commandTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.isWakeWordDetected = false
                print("⏱️ Command timeout - waiting for wake word again")
            }
        }
    }

    // MARK: - Audio Feedback

    private func playActivationSound() {
        // Play short beep to indicate wake word detected
        AudioServicesPlaySystemSound(1052) // Tink sound
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension VoiceCommandManager: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in
            if !available {
                stopListening()
            }
        }
    }
}

// MARK: - Errors

enum VoiceError: Error {
    case permissionDenied
    case setupFailed
    case recognitionFailed

    var localizedDescription: String {
        switch self {
        case .permissionDenied:
            return "Spracheingabe-Berechtigung verweigert"
        case .setupFailed:
            return "Spracheingabe konnte nicht gestartet werden"
        case .recognitionFailed:
            return "Spracherkennung fehlgeschlagen"
        }
    }
}

import AudioToolbox
```

**Schritt 1.2: Integration in TrinityCoordinator**

```swift
// In TrinityCoordinator.swift - add property:

private let voiceCommandManager: VoiceCommandManager

// In init():
self.voiceCommandManager = VoiceCommandManager()

// Setup voice commands:
voiceCommandManager.onCommandRecognized = { [weak self] action in
    Task { @MainActor in
        await self?.handleVoiceCommand(action)
    }
}

// Add handler:
private func handleVoiceCommand(_ action: String) async {
    switch action {
    case "describeScene":
        await describeCurrentScene()
    case "repeatLast":
        repeatLastMessage()
    case "startNavigation":
        // TODO: Implement navigation start
        break
    case "stopNavigation":
        // TODO: Implement navigation stop
        break
    case "emergency":
        // TODO: Implement emergency call
        break
    case "stopListening":
        voiceCommandManager.stopListening()
    default:
        break
    }
}

// In start():
try? await voiceCommandManager.startListening()

// In stop():
voiceCommandManager.stopListening()
```

**Schritt 1.3: UI Integration (MainView)**

```swift
// In MainView.swift - add toggle:

VStack {
    // ... existing UI ...

    HStack {
        Image(systemName: voiceManager.isListening ? "mic.fill" : "mic.slash.fill")
            .foregroundColor(voiceManager.isListening ? .green : .gray)

        if voiceManager.isListening {
            Text(voiceManager.isWakeWordDetected ? "Lausche auf Befehl..." : "Sage 'Hey Trinity'")
                .font(.caption)
        }
    }
    .accessibilityLabel(voiceManager.isListening ? "Spracheingabe aktiv" : "Spracheingabe inaktiv")
}
```

**Testing:**
```swift
// Unit Test: VoiceCommandManagerTests.swift

func testWakeWordDetection() async {
    let manager = VoiceCommandManager()

    // Simulate wake word
    manager.handleRecognitionResult(
        result: mockResult(text: "Hey Trinity"),
        error: nil
    )

    XCTAssertTrue(manager.isWakeWordDetected)
}

func testCommandRecognition() async {
    // Test all commands
    for command in VoiceCommand.allCases {
        // ...
    }
}
```

**Geschätzter Aufwand:** 3-5 Tage
**Dateien:** 1 neu, 2 modifiziert
**LOC:** ~350 neue Zeilen

---

### ✅ Feature 2: Error Handling & User Feedback

**Priorität:** 🔴 CRITICAL
**Aufwand:** Medium (2-3 Tage)
**Impact:** High (User Experience)

#### Implementierungsschritte

**Schritt 2.1: ErrorManager erstellen**

```swift
// Neue Datei: TrinityApp/Sources/Utils/ErrorManager.swift

import Foundation
import SwiftUI

/// Zentrales Error Management mit User-Feedback
@MainActor
class ErrorManager: ObservableObject {

    @Published var currentError: TrinityError?
    @Published var showErrorAlert = false

    private let communicationAgent: CommunicationAgent?

    init(communicationAgent: CommunicationAgent? = nil) {
        self.communicationAgent = communicationAgent
    }

    // MARK: - Error Handling

    func handle(_ error: Error, context: String = "") {
        print("❌ Error in \(context): \(error)")

        let trinityError = mapToTrinityError(error, context: context)
        currentError = trinityError
        showErrorAlert = true

        // Voice feedback
        let message = trinityError.voiceMessage
        communicationAgent?.speak(message, priority: .high)

        // Haptic feedback
        triggerErrorHaptic()
    }

    private func mapToTrinityError(_ error: Error, context: String) -> TrinityError {
        if let trinityError = error as? TrinityError {
            return trinityError
        }

        // Map common errors
        if context.contains("Camera") || context.contains("ARKit") {
            return .cameraError(message: error.localizedDescription)
        } else if context.contains("Location") {
            return .locationError(message: error.localizedDescription)
        } else if context.contains("Network") || context.contains("API") {
            return .networkError(message: error.localizedDescription)
        } else if context.contains("ML") || context.contains("Detection") {
            return .mlModelError(message: error.localizedDescription)
        } else {
            return .unknownError(message: error.localizedDescription)
        }
    }

    private func triggerErrorHaptic() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        #endif
    }

    func clearError() {
        currentError = nil
        showErrorAlert = false
    }
}

// MARK: - Enhanced TrinityError

enum TrinityError: Error {
    case permissionsNotGranted
    case notConfigured
    case alreadyRunning
    case notRunning
    case cameraError(message: String)
    case locationError(message: String)
    case networkError(message: String)
    case mlModelError(message: String)
    case storageError(message: String)
    case unknownError(message: String)

    var localizedDescription: String {
        switch self {
        case .permissionsNotGranted:
            return "Erforderliche Berechtigungen wurden nicht erteilt"
        case .notConfigured:
            return "System ist nicht konfiguriert"
        case .alreadyRunning:
            return "System läuft bereits"
        case .notRunning:
            return "System ist nicht gestartet"
        case .cameraError(let message):
            return "Kamera-Fehler: \(message)"
        case .locationError(let message):
            return "Standort-Fehler: \(message)"
        case .networkError(let message):
            return "Netzwerk-Fehler: \(message)"
        case .mlModelError(let message):
            return "KI-Modell-Fehler: \(message)"
        case .storageError(let message):
            return "Speicher-Fehler: \(message)"
        case .unknownError(let message):
            return "Unbekannter Fehler: \(message)"
        }
    }

    var voiceMessage: String {
        switch self {
        case .permissionsNotGranted:
            return "Bitte erteilen Sie die erforderlichen Berechtigungen in den Einstellungen."
        case .cameraError:
            return "Die Kamera konnte nicht gestartet werden. Bitte starten Sie die App neu."
        case .locationError:
            return "Der Standort konnte nicht ermittelt werden."
        case .networkError:
            return "Keine Internetverbindung. Einige Funktionen sind eingeschränkt."
        case .mlModelError:
            return "Die Bilderkennung ist temporär nicht verfügbar."
        case .storageError:
            return "Speicherfehler. Bitte prüfen Sie den freien Speicherplatz."
        default:
            return "Ein Fehler ist aufgetreten. Bitte versuchen Sie es erneut."
        }
    }

    var recoveryOptions: [RecoveryOption] {
        switch self {
        case .permissionsNotGranted:
            return [.openSettings, .cancel]
        case .cameraError, .mlModelError:
            return [.retry, .restart, .cancel]
        case .networkError:
            return [.retry, .continueOffline, .cancel]
        case .storageError:
            return [.clearCache, .cancel]
        default:
            return [.retry, .cancel]
        }
    }
}

enum RecoveryOption {
    case retry
    case cancel
    case restart
    case openSettings
    case continueOffline
    case clearCache

    var title: String {
        switch self {
        case .retry: return "Erneut versuchen"
        case .cancel: return "Abbrechen"
        case .restart: return "App neu starten"
        case .openSettings: return "Einstellungen öffnen"
        case .continueOffline: return "Offline fortfahren"
        case .clearCache: return "Cache leeren"
        }
    }
}
```

**Schritt 2.2: UI Alert View**

```swift
// In MainView.swift - add error alert:

.alert(
    currentError?.localizedDescription ?? "Fehler",
    isPresented: $errorManager.showErrorAlert,
    presenting: errorManager.currentError
) { error in
    ForEach(error.recoveryOptions, id: \.title) { option in
        Button(option.title) {
            handleRecoveryOption(option, for: error)
        }
    }
} message: { error in
    Text(error.voiceMessage)
}

private func handleRecoveryOption(_ option: RecoveryOption, for error: TrinityError) {
    switch option {
    case .retry:
        Task {
            try? await coordinator.start()
        }
    case .openSettings:
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    case .clearCache:
        // TODO: Implement cache clearing
        break
    case .restart:
        // Restart logic
        break
    default:
        errorManager.clearError()
    }
}
```

**Schritt 2.3: Integration in TrinityCoordinator**

```swift
// In TrinityCoordinator - add ErrorManager:

private let errorManager: ErrorManager

// Replace all print("Error: ...") with:
errorManager.handle(error, context: "processObservation")

// Wrap critical sections:
do {
    try await someOperation()
} catch {
    errorManager.handle(error, context: "Operation Name")
}
```

**Testing:**
```swift
func testErrorHandling() {
    let manager = ErrorManager()

    let error = TrinityError.cameraError(message: "Test")
    manager.handle(error, context: "Test")

    XCTAssertNotNil(manager.currentError)
    XCTAssertTrue(manager.showErrorAlert)
}
```

**Geschätzter Aufwand:** 2-3 Tage
**Dateien:** 1 neu, 3 modifiziert
**LOC:** ~250 neue Zeilen

---

### ✅ Feature 3: Onboarding & Tutorial

**Priorität:** 🔴 CRITICAL
**Aufwand:** High (4-5 Tage)
**Impact:** High (User Adoption)

#### Implementierungsschritte

**Schritt 3.1: OnboardingView erstellen**

```swift
// Neue Datei: TrinityApp/Sources/UI/OnboardingView.swift

import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @Binding var isComplete: Bool

    var body: some View {
        VStack(spacing: 30) {
            // Progress indicator
            ProgressView(value: Double(viewModel.currentStep), total: Double(viewModel.totalSteps))
                .accessibilityLabel("Schritt \(viewModel.currentStep) von \(viewModel.totalSteps)")

            // Current step content
            currentStepView

            Spacer()

            // Navigation buttons
            HStack(spacing: 20) {
                if viewModel.canGoBack {
                    Button("Zurück") {
                        viewModel.previousStep()
                    }
                    .accessibilityLabel("Vorheriger Schritt")
                }

                Spacer()

                Button(viewModel.isLastStep ? "Fertig" : "Weiter") {
                    if viewModel.isLastStep {
                        completeOnboarding()
                    } else {
                        viewModel.nextStep()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(viewModel.isLastStep ? "Onboarding abschließen" : "Nächster Schritt")
            }
            .padding()
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            viewModel.speakCurrentStep()
        }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch viewModel.currentStepType {
        case .welcome:
            WelcomeStepView()
        case .permissions:
            PermissionsStepView(viewModel: viewModel)
        case .voiceCommands:
            VoiceCommandsStepView()
        case .features:
            FeaturesStepView()
        case .tutorial:
            TutorialStepView(viewModel: viewModel)
        }
    }

    private func completeOnboarding() {
        viewModel.markAsComplete()
        isComplete = true
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "eye.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .accessibilityHidden(true)

            Text("Willkommen bei TRINITY")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Ihre intelligente Navigationshilfe")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("""
            TRINITY nutzt künstliche Intelligenz, um Ihre Umgebung zu erkennen \
            und Sie sicher durch Ihre Welt zu führen.
            """)
                .multilineTextAlignment(.center)
                .padding()
        }
    }
}

// MARK: - Permissions Step

struct PermissionsStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 30) {
            Text("Erforderliche Berechtigungen")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 20) {
                PermissionRow(
                    icon: "camera.fill",
                    title: "Kamera",
                    description: "Für Objekterkennung und Navigation",
                    status: viewModel.cameraPermission
                )

                PermissionRow(
                    icon: "location.fill",
                    title: "Standort",
                    description: "Für GPS-Navigation und Route Recording",
                    status: viewModel.locationPermission
                )

                PermissionRow(
                    icon: "mic.fill",
                    title: "Mikrofon",
                    description: "Für Sprachbefehle",
                    status: viewModel.microphonePermission
                )
            }

            Button("Berechtigungen erteilen") {
                Task {
                    await viewModel.requestAllPermissions()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.allPermissionsGranted)
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: status.icon)
                .foregroundColor(status.color)
                .accessibilityLabel(status.label)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.1))
        )
    }
}

// MARK: - Voice Commands Step

struct VoiceCommandsStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Sprachbefehle")
                .font(.title)
                .fontWeight(.bold)

            Text("Steuern Sie TRINITY mit Ihrer Stimme")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 15) {
                CommandRow(wakeWord: "Hey Trinity", command: nil, description: "Aktiviert die Spracheingabe")
                CommandRow(wakeWord: nil, command: "Beschreibe Szene", description: "Beschreibt die aktuelle Umgebung")
                CommandRow(wakeWord: nil, command: "Wiederhole", description: "Wiederholt die letzte Ansage")
                CommandRow(wakeWord: nil, command: "Navigation starten", description: "Startet die Navigation")
                CommandRow(wakeWord: nil, command: "Notfall", description: "Ruft Notfallkontakt an")
            }
        }
    }
}

struct CommandRow: View {
    let wakeWord: String?
    let command: String?
    let description: String

    var body: some View {
        HStack {
            Text(wakeWord ?? command ?? "")
                .font(.headline)
                .foregroundColor(.blue)

            Spacer()

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// MARK: - ViewModel

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var currentStep = 0
    @Published var cameraPermission: PermissionStatus = .notDetermined
    @Published var locationPermission: PermissionStatus = .notDetermined
    @Published var microphonePermission: PermissionStatus = .notDetermined

    private let synthesizer = AVSpeechSynthesizer()

    let totalSteps = 5

    enum StepType {
        case welcome
        case permissions
        case voiceCommands
        case features
        case tutorial
    }

    var currentStepType: StepType {
        switch currentStep {
        case 0: return .welcome
        case 1: return .permissions
        case 2: return .voiceCommands
        case 3: return .features
        case 4: return .tutorial
        default: return .welcome
        }
    }

    var canGoBack: Bool {
        currentStep > 0
    }

    var isLastStep: Bool {
        currentStep == totalSteps - 1
    }

    var allPermissionsGranted: Bool {
        cameraPermission == .granted &&
        locationPermission == .granted &&
        microphonePermission == .granted
    }

    func nextStep() {
        guard currentStep < totalSteps - 1 else { return }
        currentStep += 1
        speakCurrentStep()
    }

    func previousStep() {
        guard currentStep > 0 else { return }
        currentStep -= 1
        speakCurrentStep()
    }

    func speakCurrentStep() {
        let message: String
        switch currentStepType {
        case .welcome:
            message = "Willkommen bei TRINITY. Ihre intelligente Navigationshilfe."
        case .permissions:
            message = "Bitte erteilen Sie die erforderlichen Berechtigungen für Kamera, Standort und Mikrofon."
        case .voiceCommands:
            message = "Sie können TRINITY mit Sprachbefehlen steuern. Sagen Sie Hey Trinity, um die Spracheingabe zu aktivieren."
        case .features:
            message = "TRINITY erkennt Objekte, liest Texte und führt Sie sicher durch Ihre Umgebung."
        case .tutorial:
            message = "Lassen Sie uns einen ersten Test durchführen."
        }

        speak(message)
    }

    private func speak(_ message: String) {
        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func requestAllPermissions() async {
        // Request camera
        // Request location
        // Request microphone
        // Update status
    }

    func markAsComplete() {
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
    }
}

enum PermissionStatus {
    case notDetermined
    case granted
    case denied

    var icon: String {
        switch self {
        case .notDetermined: return "circle"
        case .granted: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notDetermined: return .gray
        case .granted: return .green
        case .denied: return .red
        }
    }

    var label: String {
        switch self {
        case .notDetermined: return "Nicht erteilt"
        case .granted: return "Erteilt"
        case .denied: return "Verweigert"
        }
    }
}
```

**Schritt 3.2: Integration in TrinityApp**

```swift
// In TrinityApp.swift:

@State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingComplete")

var body: some View {
    if showOnboarding {
        OnboardingView(isComplete: $showOnboarding)
    } else {
        MainView()
            .environmentObject(coordinator)
    }
}
```

**Geschätzter Aufwand:** 4-5 Tage
**Dateien:** 1 neu, 1 modifiziert
**LOC:** ~600 neue Zeilen

---

### ✅ Feature 4: ML Model Bundles hinzufügen

**Priorität:** 🔴 CRITICAL
**Aufwand:** Low (1 Tag)
**Impact:** High (App funktioniert nicht richtig ohne)

#### Implementierungsschritte

**Schritt 4.1: YOLOv8 Model herunterladen**

```bash
# Terminal:
pip install ultralytics

# Export YOLOv8n zu Core ML
yolo export model=yolov8n.pt format=coreml

# Resultat: yolov8n.mlmodel (~10MB)
```

**Schritt 4.2: In Xcode Bundle packen**

1. Öffne Xcode
2. Erstelle Ordner `TrinityApp/Resources/Models/`
3. Füge `yolov8n.mlmodel` hinzu
4. Target Membership: ✅ TrinityApp
5. Build Phases → Copy Bundle Resources: Prüfen dass Model dabei ist

**Schritt 4.3: MobileNetV3 Model**

Download von Apple Developer:
https://developer.apple.com/machine-learning/models/

Oder nutze eingebautes:
```swift
// Falls kein Custom Model, nutze Apple's FeaturePrint (bereits implementiert)
```

**Schritt 4.4: Verifikation im Code**

```swift
// YOLOv8Detector.swift sollte Model finden:
if let modelURL = Bundle.main.url(forResource: "yolov8n", withExtension: "mlmodelc") {
    print("✅ YOLOv8 model found!")
}
```

**Testing:**
```swift
func testModelLoading() throws {
    let detector = YOLOv8Detector()
    XCTAssertNotNil(detector.model)
}
```

**Geschätzter Aufwand:** 1 Tag
**Dateien:** 0 neu (nur Resources)
**LOC:** 0

---

## 🟡 PHASE 2: WICHTIGE FEATURES (Woche 3)

### ✅ Feature 5: Erweiterte Settings

**Priorität:** 🟡 HIGH
**Aufwand:** Low (1-2 Tage)
**Impact:** Medium

#### Quick Implementation

```swift
// In SettingsView - add sections:

Section("Sprache") {
    Slider(value: $speechRate, in: 0.3...0.7) {
        Text("Sprechgeschwindigkeit: \(Int(speechRate * 100))%")
    }
    .accessibilityLabel("Sprechgeschwindigkeit anpassen")

    Slider(value: $speechVolume, in: 0.5...1.0) {
        Text("Lautstärke: \(Int(speechVolume * 100))%")
    }
    .accessibilityLabel("Lautstärke anpassen")

    Picker("Sprache", selection: $language) {
        Text("Deutsch").tag("de-DE")
        Text("English").tag("en-US")
    }
    .accessibilityLabel("Sprache auswählen")
}

Section("Erkennung") {
    Slider(value: $confidenceThreshold, in: 0.3...0.9) {
        Text("Genauigkeit: \(Int(confidenceThreshold * 100))%")
    }
    .accessibilityHint("Höhere Werte bedeuten weniger, aber genauere Erkennungen")
}

Section("Haptik") {
    Picker("Intensität", selection: $hapticIntensity) {
        Text("Aus").tag(0)
        Text("Leicht").tag(1)
        Text("Mittel").tag(2)
        Text("Stark").tag(3)
    }
}
```

**Geschätzter Aufwand:** 1-2 Tage

---

### ✅ Feature 6: CacheManager Tier 2 reparieren

**Priorität:** 🟡 MEDIUM
**Aufwand:** Low (1 Tag)
**Impact:** Medium

#### Fix Type Mismatch

```swift
// In CacheManager.swift - create generic cache entry:

struct CacheEntry: Codable {
    let key: String
    let timestamp: Date
    let expiresAt: Date
    let data: Data  // Codable to Data

    init<T: Codable>(key: String, value: T, ttl: TimeInterval) throws {
        self.key = key
        self.timestamp = Date()
        self.expiresAt = Date().addingTimeInterval(ttl)
        self.data = try JSONEncoder().encode(value)
    }

    func decode<T: Codable>(as type: T.Type) throws -> T {
        return try JSONDecoder().decode(type, from: data)
    }
}

// Tier 2: Semantic Cache (now works)
func cacheSemanticResult(query: [Float], result: Any) throws {
    let key = semanticCacheKey(query)

    // Store as generic Data
    if let codable = result as? Codable {
        let entry = try CacheEntry(key: key, value: codable, ttl: semanticCacheTTL)
        // ... save entry
    }
}
```

**Geschätzter Aufwand:** 1 Tag

---

## 🟢 PHASE 3: SICHERHEIT & NOTFALL (Woche 4)

### ✅ Feature 7: Emergency Features

**Priorität:** 🟡 HIGH (Safety)
**Aufwand:** Medium (2 Tage)

```swift
// Emergency Manager

import CallKit

class EmergencyManager {
    func triggerEmergency() {
        // 1. Call 112
        callEmergency()

        // 2. Send SMS to emergency contacts
        sendEmergencySMS()

        // 3. Share location
        shareLocationWithContacts()
    }

    private func callEmergency() {
        let url = URL(string: "tel://112")!
        UIApplication.shared.open(url)
    }
}

// Triple-press Volume Down = Emergency
// Implement in AppDelegate or SceneDelegate
```

### ✅ Feature 8: Biometric Security

**Priorität:** 🟡 MEDIUM
**Aufwand:** Low (1 Tag)

```swift
import LocalAuthentication

class BiometricManager {
    func authenticate() async throws -> Bool {
        let context = LAContext()

        return try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Zugriff auf TRINITY"
        )
    }
}

// In TrinityApp - before showing MainView:
if needsAuthentication {
    try await biometricManager.authenticate()
}
```

---

## 📅 Gesamt-Timeline

```
┌─────────────────────────────────────────────────────────────┐
│ WOCHE 1: KRITISCHE FEATURES (PHASE 1.1)                     │
├─────────────────────────────────────────────────────────────┤
│ Mo-Di:  Voice Input Implementation                          │
│ Mi-Do:  Error Handling & User Feedback                      │
│ Fr:     ML Models hinzufügen & Testing                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ WOCHE 2: KRITISCHE FEATURES (PHASE 1.2)                     │
├─────────────────────────────────────────────────────────────┤
│ Mo-Do:  Onboarding & Tutorial Implementation                │
│ Fr:     Integration Testing, Bug Fixes                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ WOCHE 3: WICHTIGE FEATURES (PHASE 2)                        │
├─────────────────────────────────────────────────────────────┤
│ Mo-Di:  Erweiterte Settings                                 │
│ Mi:     CacheManager Tier 2 Fix                             │
│ Do-Fr:  Emergency Features                                  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ WOCHE 4: POLISH & TESTING                                   │
├─────────────────────────────────────────────────────────────┤
│ Mo:     Biometric Security                                  │
│ Di-Mi:  Comprehensive Testing (Unit + Integration)          │
│ Do:     Bug Fixes & Performance Tuning                      │
│ Fr:     Beta Release Preparation                            │
└─────────────────────────────────────────────────────────────┘
```

---

## ✅ Testing Strategie

### Unit Tests (jedes Feature)

```swift
// VoiceCommandManagerTests.swift
class VoiceCommandManagerTests: XCTestCase {
    func testWakeWordDetection() { }
    func testCommandRecognition() { }
    func testPermissionHandling() { }
}

// ErrorManagerTests.swift
class ErrorManagerTests: XCTestCase {
    func testErrorMapping() { }
    func testVoiceFeedback() { }
    func testRecoveryOptions() { }
}

// OnboardingViewModelTests.swift
class OnboardingViewModelTests: XCTestCase {
    func testStepProgression() { }
    func testPermissionRequests() { }
    func testVoiceGuidance() { }
}
```

### Integration Tests

```swift
class TrinityIntegrationTests: XCTestCase {
    func testVoiceCommandToAction() async {
        // User says "Beschreibe Szene"
        // → VoiceCommandManager recognizes
        // → TrinityCoordinator handles
        // → Perception runs
        // → Communication speaks result
    }

    func testErrorRecovery() async {
        // Simulate camera error
        // → ErrorManager handles
        // → User sees alert + hears message
        // → User chooses retry
        // → System recovers
    }
}
```

### Accessibility Tests

```swift
func testVoiceOverSupport() {
    // All buttons have labels
    // All images are hidden or have labels
    // Navigation is logical
}

func testVoiceGuidance() {
    // Onboarding speaks each step
    // Errors speak feedback
    // Commands provide audio confirmation
}
```

---

## 📊 Success Metrics

**Funktionalität:**
- ✅ Voice Input funktioniert mit >90% Erkennungsrate
- ✅ Errors werden zu 100% gefangen und angezeigt
- ✅ Onboarding komplett durchlaufbar
- ✅ ML Models laden ohne Fehler

**Performance:**
- ✅ Voice Input Latenz <500ms
- ✅ Error Handling <50ms Overhead
- ✅ Onboarding Voice Feedback <1s delay
- ✅ ML Model Loading <3s

**UX:**
- ✅ User kann App komplett per Voice bedienen
- ✅ Errors sind verständlich erklärt
- ✅ Onboarding unter 5 Minuten
- ✅ VoiceOver Rating: 100/100

---

## 🎯 Definition of Done

**Feature ist fertig wenn:**
1. ✅ Code implementiert und committed
2. ✅ Unit Tests geschrieben und bestanden
3. ✅ Integration Tests bestanden
4. ✅ Accessibility geprüft (VoiceOver)
5. ✅ Performance Targets erreicht
6. ✅ Code Review durchgeführt
7. ✅ Dokumentation aktualisiert
8. ✅ Beta Testing erfolgreich

---

## 📝 Nächste Schritte

**Sofort:**
1. ⏳ Warte auf Perplexity O3 + Opus4.1 Analyse
2. ⏳ Kombiniere beide Analysen
3. ⏳ Finalisiere Prioritäten
4. ✅ Beginne mit Feature 1 (Voice Input)

**Nach Perplexity Feedback:**
- Adjustiere Prioritäten basierend auf zusätzlichen Findings
- Integriere neue Verbesserungsvorschläge
- Update Timeline falls nötig
- Start Implementation!

---

**Bereit für Implementation sobald Perplexity-Analyse vorliegt!** 🚀
