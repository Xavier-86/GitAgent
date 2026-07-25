//
//  GitHubAuthManager.swift
//  GitAgent
//

import Foundation
import Observation

/// Authentication state.
enum AuthState {
    case loggedOut
    /// Device code obtained, waiting for the user to authorize in the browser.
    case waitingForAuthorization(DeviceCodeResponse)
    case loggedIn(GitHubUser)
}

/// Manages GitHub sign-in via the OAuth Device Flow.
@Observable
final class GitHubAuthManager {
    private(set) var state: AuthState = .loggedOut
    var errorMessage: String?

    private(set) var client: GitHubClient?
    private var pollingTask: Task<Void, Never>?

    init() {
        if let token = KeychainHelper.readToken() {
            let client = GitHubClient(token: token)
            self.client = client
            Task { await loadUser(client: client) }
        }
    }

    // MARK: - Device Flow

    func startLogin() {
        guard GitHubConfig.clientID != "YOUR_CLIENT_ID" else {
            errorMessage = L10n.resolveCurrent(.clientIDMissing)
            return
        }
        errorMessage = nil
        pollingTask?.cancel()
        pollingTask = Task { await runDeviceFlow() }
    }

    func cancelLogin() {
        pollingTask?.cancel()
        pollingTask = nil
        state = .loggedOut
    }

    private func runDeviceFlow() async {
        do {
            let device = try await requestDeviceCode()
            guard !Task.isCancelled else { return }
            state = .waitingForAuthorization(device)
            try await pollForToken(device: device)
        } catch is CancellationError {
            // Cancelled by the user.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            state = .loggedOut
        }
    }

    private func requestDeviceCode() async throws -> DeviceCodeResponse {
        var request = URLRequest(url: GitHubConfig.deviceCodeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "client_id=\(GitHubConfig.clientID)&scope=\(GitHubConfig.scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubError.invalidResponse
        }
        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    private func pollForToken(device: DeviceCodeResponse) async throws {
        var interval = max(device.interval, 5)
        let deadline = Date().addingTimeInterval(TimeInterval(device.expiresIn))

        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            let result = try await requestAccessToken(deviceCode: device.deviceCode)

            if let token = result.accessToken {
                KeychainHelper.save(token: token)
                let client = GitHubClient(token: token)
                self.client = client
                await loadUser(client: client)
                return
            }

            switch result.error {
            case "authorization_pending":
                continue
            case "slow_down":
                interval += 5
            case "expired_token":
                throw GitHubError.localized(.authCodeExpired)
            case "access_denied":
                throw GitHubError.localized(.accessDenied)
            default:
                throw GitHubError.localized(.unknownError)
            }
        }
        throw GitHubError.localized(.authTimeout)
    }

    private func requestAccessToken(deviceCode: String) async throws -> AccessTokenResponse {
        var request = URLRequest(url: GitHubConfig.accessTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id=\(GitHubConfig.clientID)",
            "device_code=\(deviceCode)",
            "grant_type=urn:ietf:params:oauth:grant-type:device_code",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(AccessTokenResponse.self, from: data)
    }

    // MARK: - User

    private func loadUser(client: GitHubClient) async {
        do {
            let user = try await client.currentUser()
            state = .loggedIn(user)
        } catch GitHubError.unauthorized {
            // Stored token is no longer valid; drop it and sign in again.
            logout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        pollingTask?.cancel()
        pollingTask = nil
        KeychainHelper.deleteToken()
        client = nil
        state = .loggedOut
    }
}
