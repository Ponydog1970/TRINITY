//
//  TrinityApp.swift
//  TRINITY Vision Aid
//
//  Main SwiftUI App entry point
//

import SwiftUI

@main
struct TrinityApp: App {
    @StateObject private var coordinator: TrinityCoordinator

    init() {
        // Initialize coordinator
        do {
            let coordinator = try TrinityCoordinator()
            _coordinator = StateObject(wrappedValue: coordinator)
        } catch {
            fatalError("Failed to initialize TRINITY: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(coordinator)
                .preferredColorScheme(.dark)  // Better for low vision
        }
    }
}
