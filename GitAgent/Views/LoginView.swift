//
//  LoginView.swift
//  GitAgent
//

import SwiftUI

struct LoginView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var showAuthPage = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "book.pages")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("GitAgent")
                .font(.largeTitle.bold())

            switch auth.state {
            case .loggedOut:
                Button {
                    auth.startLogin()
                } label: {
                    Label(settings.tr(.signIn), systemImage: "person.crop.circle.badge.checkmark")
                        .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let error = auth.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

            case .waitingForAuthorization(let device):
                Text(settings.tr(.deviceCodePrompt))
                    .foregroundStyle(.secondary)
                Text(device.userCode)
                    .font(.system(.title, design: .monospaced).bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)

                HStack(spacing: 12) {
                    Button {
                        copyToClipboard(device.userCode)
                    } label: {
                        Label(settings.tr(.copyCode), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showAuthPage = true
                    } label: {
                        Label(settings.tr(.openAuthPage), systemImage: "person.badge.key")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Alternative to the in-app viewer: authorize in the system browser.
                Button {
                    openURL(Self.authorizationURL(for: device))
                } label: {
                    Label(settings.tr(.openInBrowser), systemImage: "safari")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ProgressView()
                    Text(settings.tr(.waitingAuth)).foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                Button(settings.tr(.cancel), role: .cancel) {
                    auth.cancelLogin()
                }
                .foregroundStyle(.secondary)

                if let error = auth.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

            case .loggedIn, .restoring:
                EmptyView()
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAuthPage) {
            if case .waitingForAuthorization(let device) = auth.state {
                WebPageView(url: Self.authorizationURL(for: device))
            }
        }
    }

    /// The device verification page with the user code pre-filled (?user_code=),
    /// shown in the in-app web viewer so authorization never leaves the app.
    private static func authorizationURL(for device: DeviceCodeResponse) -> URL {
        var components = URLComponents(url: device.verificationURI, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "user_code", value: device.userCode)]
        return components?.url ?? device.verificationURI
    }
}

#Preview {
    LoginView()
        .environment(GitHubAuthManager())
        .environment(AppSettings())
}
