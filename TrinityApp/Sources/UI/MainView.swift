//
//  MainView.swift
//  TRINITY Vision Aid
//
//  Main user interface - optimized for VoiceOver and accessibility
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject var coordinator: TrinityCoordinator
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                VStack(spacing: 40) {
                    // Status indicator
                    StatusView(status: coordinator.currentStatus)
                        .accessibilityLabel("System status: \(coordinator.currentStatus.description)")

                    Spacer()

                    // Main controls
                    VStack(spacing: 30) {
                        // Start/Stop button
                        MainControlButton(
                            isRunning: coordinator.isRunning,
                            action: {
                                Task {
                                    if coordinator.isRunning {
                                        await coordinator.stop()
                                    } else {
                                        try? await coordinator.start()
                                    }
                                }
                            }
                        )

                        // Describe scene button
                        ActionButton(
                            title: "Describe Scene",
                            icon: "camera.fill",
                            action: {
                                Task {
                                    await coordinator.describeCurrentScene()
                                }
                            }
                        )
                        .disabled(!coordinator.isRunning)

                        // Repeat last message button
                        ActionButton(
                            title: "Repeat",
                            icon: "arrow.clockwise",
                            action: {
                                coordinator.repeatLastMessage()
                            }
                        )
                        .disabled(coordinator.lastSpokenMessage.isEmpty)
                    }

                    Spacer()

                    // Settings button
                    Button(action: { showSettings.toggle() }) {
                        Label("Settings", systemImage: "gearshape.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .padding()
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Double tap to open settings")
                }
                .padding()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(coordinator)
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Status View

struct StatusView: View {
    let status: SystemStatus

    var body: some View {
        VStack(spacing: 10) {
            // Status icon
            Image(systemName: statusIcon)
                .font(.system(size: 60))
                .foregroundColor(statusColor)
                .accessibilityHidden(true)

            // Status text
            Text(status.description)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var statusIcon: String {
        switch status {
        case .idle:
            return "pause.circle.fill"
        case .running:
            return "play.circle.fill"
        case .processing:
            return "waveform.circle.fill"
        case .consolidatingMemory:
            return "brain.head.profile"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .idle:
            return .gray
        case .running:
            return .green
        case .processing:
            return .blue
        case .consolidatingMemory:
            return .purple
        case .error:
            return .red
        }
    }
}

// MARK: - Main Control Button

struct MainControlButton: View {
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRunning ? Color.red : Color.green)
                    .frame(width: 120, height: 120)
                    .shadow(radius: 10)

                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white)
            }
        }
        .accessibilityLabel(isRunning ? "Stop TRINITY" : "Start TRINITY")
        .accessibilityHint(isRunning ? "Double tap to stop the system" : "Double tap to start the system")
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.title2)

                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.white.opacity(0.2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color.white, lineWidth: 2)
            )
        }
        .accessibilityLabel(title)
        .accessibilityHint("Double tap to \(title.lowercased())")
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var coordinator: TrinityCoordinator
    @Environment(\.dismiss) var dismiss

    @State private var verbosityLevel = 1  // 0: minimal, 1: medium, 2: detailed

    var body: some View {
        NavigationView {
            Form {
                Section("Voice Settings") {
                    Picker("Verbosity Level", selection: $verbosityLevel) {
                        Text("Minimal").tag(0)
                        Text("Medium").tag(1)
                        Text("Detailed").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Verbosity level")
                    .onChange(of: verbosityLevel) { _, newValue in
                        let level: CommunicationAgent.VerbosityLevel
                        switch newValue {
                        case 0: level = .minimal
                        case 2: level = .detailed
                        default: level = .medium
                        }
                        coordinator.adjustVerbosity(level)
                    }
                }

                Section("Memory") {
                    Button("Consolidate Memories") {
                        Task {
                            await coordinator.consolidateMemories()
                        }
                    }
                    .accessibilityLabel("Consolidate memories")
                    .accessibilityHint("Organize and optimize stored memories")

                    Button("Clear All Memories") {
                        coordinator.clearAllMemories()
                    }
                    .foregroundColor(.red)
                    .accessibilityLabel("Clear all memories")
                    .accessibilityHint("Warning: This will delete all stored data")
                }

                Section("Data") {
                    Button("Export to iCloud") {
                        Task {
                            _ = try? await coordinator.exportMemories()
                        }
                    }
                    .accessibilityLabel("Export to iCloud")

                    Button("Import from iCloud") {
                        // Would show file picker
                    }
                    .accessibilityLabel("Import from iCloud")
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("001")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
            .environmentObject(try! TrinityCoordinator())
            .preferredColorScheme(.dark)
    }
}
