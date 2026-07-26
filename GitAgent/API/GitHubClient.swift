//
//  GitHubClient.swift
//  GitAgent
//

import Foundation

enum GitHubError: LocalizedError {
    case unauthorized
    case rateLimited
    case httpError(status: Int, message: String)
    case invalidResponse
    /// Error whose message comes from the L10n table (used by the auth flow).
    case localized(L10n.Key)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return L10n.resolveCurrent(.unauthorized)
        case .rateLimited:
            return L10n.resolveCurrent(.rateLimited)
        case .httpError(let status, let message):
            return L10n.requestFailed(status: status, message: message)
        case .invalidResponse:
            return L10n.resolveCurrent(.invalidResponse)
        case .localized(let key):
            return L10n.resolveCurrent(key)
        }
    }
}

/// Thin wrapper around the GitHub REST API.
final class GitHubClient {
    let token: String

    init(token: String) {
        self.token = token
    }

    // MARK: - Caches (app-session scoped)

    /// Downloaded images (Markdown rendering), ~64 MB cap.
    private static let imageCache: NSCache<NSURL, CachedImage> = {
        let cache = NSCache<NSURL, CachedImage>()
        cache.countLimit = 300
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    /// File/README text — avoids refetching when navigating back and forth.
    private static let textCache = NSCache<NSString, NSString>()

    final class CachedImage: NSObject {
        let data: Data
        let mimeType: String
        init(data: Data, mimeType: String) {
            self.data = data
            self.mimeType = mimeType
        }
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = f.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unparseable date \(string)")
        }
        return d
    }()

    // MARK: - Request plumbing

    private func makeRequest(path: String, query: [URLQueryItem] = [], raw: Bool = false) -> URLRequest {
        var components = URLComponents(url: GitHubConfig.apiBase.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(raw ? "application/vnd.github.raw+json" : "application/vnd.github+json",
                       forHTTPHeaderField: "Accept")
        return request
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw GitHubError.unauthorized
        case 403 where http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0":
            throw GitHubError.rateLimited
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["message"]
                ?? L10n.resolveCurrent(.unknownError)
            throw GitHubError.httpError(status: http.statusCode, message: message)
        }
    }

    private func get<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: makeRequest(path: path, query: query))
        try validate(response, data: data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GitHubError.invalidResponse
        }
    }

    // MARK: - User & repositories

    func currentUser() async throws -> GitHubUser {
        try await get(GitHubUser.self, path: "/user")
    }

    /// Repositories of the signed-in user (including private), most recently updated first.
    func myRepos() async throws -> [Repo] {
        try await get([Repo].self, path: "/user/repos", query: [
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "per_page", value: "100"),
        ])
    }

    /// Public repositories of any user.
    func userRepos(username: String) async throws -> [Repo] {
        try await get([Repo].self, path: "/users/\(username)/repos", query: [
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "per_page", value: "100"),
        ])
    }

    /// Repositories starred by the signed-in user, most recently starred first.
    func starredRepos() async throws -> [Repo] {
        try await get([Repo].self, path: "/user/starred", query: [
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "per_page", value: "100"),
        ])
    }

    /// A single repository by owner and name (used to open github.com links in-app).
    func repo(owner: String, name: String) async throws -> Repo {
        try await get(Repo.self, path: "/repos/\(owner)/\(name)")
    }

    /// Global repository search.
    func searchRepos(keyword: String) async throws -> [Repo] {
        let result = try await get(RepoSearchResult.self, path: "/search/repositories", query: [
            URLQueryItem(name: "q", value: keyword),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "per_page", value: "50"),
        ])
        return result.items
    }

    // MARK: - Repository contents

    /// Lists a directory (empty path = repository root).
    func contents(owner: String, repo: String, path: String = "") async throws -> [RepoContent] {
        // Note: never use a trailing slash for the root — appending(path:) would produce
        // a double slash, GitHub answers with a 302 redirect, and URLSession drops the
        // Authorization header when following it, which turns into a 404 on private repos.
        let fullPath = path.isEmpty
            ? "/repos/\(owner)/\(repo)/contents"
            : "/repos/\(owner)/\(repo)/contents/\(path)"
        let items = try await get([RepoContent].self, path: fullPath)
        return items.sorted { a, b in
            if (a.type == .dir) != (b.type == .dir) { return a.type == .dir }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// True when the path is a directory (the contents endpoint returns a JSON
    /// array for directories, an object for files). Used to resolve ambiguous
    /// Markdown links that carry no file extension.
    func isDirectory(owner: String, repo: String, path: String, ref: String? = nil) async throws -> Bool {
        var query: [URLQueryItem] = []
        if let ref { query.append(URLQueryItem(name: "ref", value: ref)) }
        let (data, response) = try await URLSession.shared.data(
            for: makeRequest(path: "/repos/\(owner)/\(repo)/contents/\(path)", query: query))
        try validate(response, data: data)
        return (try? JSONSerialization.jsonObject(with: data)) is [Any]
    }

    /// Returns the entry when the path is a git submodule pointer (the API
    /// answers a single object, not a list), nil for regular files/dirs.
    func submoduleEntry(owner: String, repo: String, path: String, ref: String? = nil) async throws -> RepoContent? {
        var query: [URLQueryItem] = []
        if let ref { query.append(URLQueryItem(name: "ref", value: ref)) }
        let (data, response) = try await URLSession.shared.data(
            for: makeRequest(path: "/repos/\(owner)/\(repo)/contents/\(path)", query: query))
        try validate(response, data: data)
        guard let entry = try? decoder.decode(RepoContent.self, from: data),
              entry.type == .submodule else { return nil }
        return entry
    }

    /// Reads a file as plain text. `ref` pins the read to a branch/tag/commit
    /// (nil reads the default branch). Results are cached for the app session.
    func fileText(owner: String, repo: String, path: String, ref: String? = nil) async throws -> String {
        let cacheKey = "\(owner)/\(repo)/\(path)#\(ref ?? "")" as NSString
        if let cached = Self.textCache.object(forKey: cacheKey) { return cached as String }
        var query: [URLQueryItem] = []
        if let ref { query.append(URLQueryItem(name: "ref", value: ref)) }
        let (data, response) = try await URLSession.shared.data(
            for: makeRequest(path: "/repos/\(owner)/\(repo)/contents/\(path)", query: query, raw: true))
        try validate(response, data: data)
        guard let text = String(data: data, encoding: .utf8) else { throw GitHubError.invalidResponse }
        Self.textCache.setObject(text as NSString, forKey: cacheKey)
        return text
    }

    /// Reads the README (returns nil when the repository has none).
    func readme(owner: String, repo: String) async throws -> (name: String, text: String)? {
        let cacheKey = "\(owner)/\(repo)/README" as NSString
        if let cached = Self.textCache.object(forKey: cacheKey) { return ("README", cached as String) }
        let request = makeRequest(path: "/repos/\(owner)/\(repo)/readme", raw: true)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
        try validate(response, data: data)
        guard let text = String(data: data, encoding: .utf8) else { throw GitHubError.invalidResponse }
        Self.textCache.setObject(text as NSString, forKey: cacheKey)
        return ("README", text)
    }

    /// Downloads image (or other binary) content. GitHub hosts get the auth header
    /// so images in private repositories load too; other hosts are fetched as-is.
    /// Results are cached so re-rendered Markdown doesn't re-download.
    func imageData(from url: URL) async throws -> (data: Data, mimeType: String) {
        if let cached = Self.imageCache.object(forKey: url as NSURL) {
            return (cached.data, cached.mimeType)
        }
        var request = URLRequest(url: url)
        if let host = url.host()?.lowercased(),
           host == "github.com" || host.hasSuffix(".githubusercontent.com") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GitHubError.invalidResponse
        }
        let mimeType = http.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";").first.map(String.init) ?? "image/png"
        Self.imageCache.setObject(CachedImage(data: data, mimeType: mimeType),
                                  forKey: url as NSURL, cost: data.count)
        return (data, mimeType)
    }

    // MARK: - GraphQL (contribution calendar)

    /// Fetches the green-square contribution calendar shown on GitHub profiles
    /// (last year). GraphQL-only — the REST API doesn't expose it.
    func contributionCalendar(username: String) async throws -> ContributionCalendar {
        let query = """
        query($login:String!){user(login:$login){contributionsCollection{contributionCalendar{totalContributions weeks{contributionDays{date contributionCount contributionLevel}}}}}}
        """
        var request = URLRequest(url: GitHubConfig.apiBase.appending(path: "graphql"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: ["login": username]))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        let decoded = try JSONDecoder().decode(GraphQLCalendarResponse.self, from: data)
        guard let calendar = decoded.data?.user.contributionsCollection.contributionCalendar else {
            throw GitHubError.invalidResponse
        }
        return ContributionCalendar(
            totalContributions: calendar.totalContributions,
            weeks: calendar.weeks.map { week in
                week.contributionDays.map { day in
                    ContributionCalendar.Day(date: day.date, count: day.contributionCount,
                                             level: day.contributionLevel.rawValue)
                }
            })
    }

    private struct GraphQLRequest: Encodable {
        let query: String
        let variables: [String: String]
    }

    private struct GraphQLCalendarResponse: Decodable {
        struct Data: Decodable {
            struct User: Decodable {
                struct ContributionsCollection: Decodable {
                    struct Calendar: Decodable {
                        struct Week: Decodable {
                            struct Day: Decodable {
                                enum Level: Int, Decodable {
                                    case none = 0, first, second, third, fourth

                                    init(from decoder: Decoder) throws {
                                        switch try decoder.singleValueContainer().decode(String.self) {
                                        case "FIRST_QUARTILE": self = .first
                                        case "SECOND_QUARTILE": self = .second
                                        case "THIRD_QUARTILE": self = .third
                                        case "FOURTH_QUARTILE": self = .fourth
                                        default: self = .none
                                        }
                                    }
                                }
                                let date: String
                                let contributionCount: Int
                                let contributionLevel: Level
                            }
                            let contributionDays: [Day]
                        }
                        let totalContributions: Int
                        let weeks: [Week]
                    }
                    let contributionCalendar: Calendar
                }
                let contributionsCollection: ContributionsCollection
            }
            let user: User
        }
        let data: Data?
    }
}
