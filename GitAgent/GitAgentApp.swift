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
        }

        // macOS: GitAgent → Settings… (⌘,). Ignored on iOS.
        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
