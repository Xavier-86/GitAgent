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
            if case .loggedIn = auth.state {
                MainView()
            } else {
                LoginView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(GitHubAuthManager())
}
