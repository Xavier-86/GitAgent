//
//  GitAgentApp.swift
//  GitAgent
//
//  Created by XuMingyuan on 2026/7/25.
//

import SwiftUI

@main
struct GitAgentApp: App {
    @State private var auth = GitHubAuthManager()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(auth)
                .environment(settings)
                #if os(macOS)
                .onAppear {
                    // Activate at launch so the window comes to the front
                    // instead of staying behind the previously active app.
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                #endif
        }

        // macOS: GitAgent → Settings… (⌘,). The Settings scene is macOS-only.
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(settings)
        }
        #endif
    }
}
