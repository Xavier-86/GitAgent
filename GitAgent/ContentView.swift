//
//  ContentView.swift
//  GitAgent
//
//  Created by XuMingyuan on 2026/7/25.
//

import SwiftUI

struct ContentView: View {
    @Environment(GitHubAuthManager.self) private var auth

    var body: some View {
        Group {
            switch auth.state {
            case .loggedIn:
                MainView()
            case .restoring:
                // Blank while the stored token is validated — avoids flashing
                // the login page on cold start.
                Color.clear
            default:
                LoginView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(GitHubAuthManager())
}
