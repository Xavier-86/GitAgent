//
//  GitAgentApp.swift
//  GitAgent
//
//  Created by XuMingyuan on 2026/7/25.
//

import SwiftUI

@main
struct GitAgentApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(GitAgentNotificationAppDelegate.self)
    private var notificationAppDelegate
    #else
    @UIApplicationDelegateAdaptor(GitAgentNotificationAppDelegate.self)
    private var notificationAppDelegate
    #endif

    @State private var auth = GitHubAuthManager()
    @State private var settings = AppSettings()
    @State private var chatStore = ChatStore()
    @State private var sshHosts = SSHHostStore()
    @State private var repositoryLocations = RepositoryLocationStore()
    @State private var repoLaunch = RepoLaunchStore()
    @State private var coder = CoderStore()
    @State private var terminalLauncher = TerminalLaunchCoordinator()
    @State private var workspace = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(auth)
                .environment(settings)
                .environment(chatStore)
                .environment(sshHosts)
                .environment(repositoryLocations)
                .environment(repoLaunch)
                .environment(coder)
                .environment(terminalLauncher)
                .environment(workspace)
                // App-wide default font driven by the UI Font Size setting —
                // exact points (dynamicTypeSize is a no-op on macOS).
                .font(.system(size: CGFloat(settings.uiFontSize)))
                .onAppear {
                    // Re-attach to remote deployments that outlived the app.
                    repoLaunch.resumeInterruptedDeployments(hosts: sshHosts)
                    // Coder sessions are probed via SSH routes from the host store.
                    coder.attach(hosts: sshHosts, settings: settings)
                    LocalNotifier.installCoderSessionHandler { recordID in
                        if let record = coder.record(recordID) {
                            workspace.focusCoderTerminal(record)
                        } else {
                            workspace.openCoder()
                        }
                    }
                    if settings.coderCompletionNotifications {
                        LocalNotifier.requestAuthorizationIfNeeded()
                    }
                }
                #if os(macOS)
                .onAppear {
                    // Closing the last macOS window does not necessarily quit
                    // the app. Reopening it should still begin with one clean
                    // New Page and the sidebar's detail-only initial state.
                    workspace.resetToInitialPage()
                    // Activate at launch so the window comes to the front
                    // instead of staying behind the previously active app.
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                #endif
        }
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(settings.tr(.settings)) {
                    workspace.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif
    }
}
