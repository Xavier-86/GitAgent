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
    @State private var chatStore = ChatStore()
    @State private var sshHosts = SSHHostStore()
    @State private var repositoryLocations = RepositoryLocationStore()
    @State private var repoLaunch = RepoLaunchStore()
    @State private var terminalLauncher = TerminalLaunchCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(auth)
                .environment(settings)
                .environment(chatStore)
                .environment(sshHosts)
                .environment(repositoryLocations)
                .environment(repoLaunch)
                .environment(terminalLauncher)
                // App-wide default font driven by the UI Font Size setting —
                // exact points (dynamicTypeSize is a no-op on macOS).
                .font(.system(size: CGFloat(settings.uiFontSize)))
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
                .font(.system(size: CGFloat(settings.uiFontSize)))
        }
        #endif
    }
}
