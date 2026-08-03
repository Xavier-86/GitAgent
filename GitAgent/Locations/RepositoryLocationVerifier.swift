//
//  RepositoryLocationVerifier.swift
//  GitAgent
//
//  Verifies a working tree and its GitHub remote through the SSH exec channel.
//

import Foundation
import Citadel
import NIO

struct RepositoryLocationProbe {
    let canonicalPath: String
    let remoteName: String
    var bookmarkData: Data?
}

enum RepositoryLocationVerifier {
    enum VerificationError: Error {
        case pathMissing
        case notGitRepository
        case noGitHubRemote
        case repositoryMismatch(found: [String])
        case remoteUnreachable
        case invalidResponse
        case localAccessDenied

        func message(expectedRepository: String) -> String {
            switch self {
            case .pathMissing:
                return L10n.resolveCurrent(.repositoryPathMissing)
            case .notGitRepository:
                return L10n.resolveCurrent(.notGitRepository)
            case .noGitHubRemote:
                return L10n.resolveCurrent(.noGitHubRemote)
            case .repositoryMismatch(let found):
                return L10n.repositoryMismatch(
                    expected: expectedRepository,
                    found: found.isEmpty ? "unknown" : found.joined(separator: ", ")
                )
            case .remoteUnreachable:
                return L10n.resolveCurrent(.repositoryRemoteUnreachable)
            case .invalidResponse:
                return L10n.resolveCurrent(.invalidRepositoryProbe)
            case .localAccessDenied:
                return L10n.resolveCurrent(.localRepositoryAccessDenied)
            }
        }
    }

    static func verify(host: SSHHostConfig,
                       password: String,
                       path: String,
                       expectedRepository: String) async throws -> RepositoryLocationProbe {
        let settings = SSHClientSettings(
            host: host.host,
            port: host.port,
            authenticationMethod: {
                .passwordBased(username: host.username, password: password)
            },
            hostKeyValidator: HostKeyStore.validator(for: host.id)
        )
        let client = try await SSHClient.connect(to: settings)

        do {
            let output = try await client.executeCommand(
                probeCommand(path: path),
                maxResponseSize: 1_000_000,
                mergeStreams: false,
                inShell: false
            )
            let probe = try parse(
                String(decoding: output.readableBytesView, as: UTF8.self),
                expectedRepository: expectedRepository
            )
            let remoteOutput = try await client.executeCommand(
                remoteProbeCommand(
                    path: probe.canonicalPath,
                    remoteName: probe.remoteName
                ),
                maxResponseSize: 1_024,
                mergeStreams: false,
                inShell: false
            )
            try? await client.close()
            guard String(decoding: remoteOutput.readableBytesView, as: UTF8.self)
                .split(whereSeparator: \.isWhitespace)
                .contains("remote_ok")
            else {
                throw VerificationError.remoteUnreachable
            }
            return probe
        } catch {
            try? await client.close()
            throw error
        }
    }

    #if os(macOS)
    static func verifyLocal(bookmarkData: Data,
                            expectedRepository: String) throws -> RepositoryLocationProbe {
        var isStale = false
        let directoryURL: URL
        do {
            directoryURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw VerificationError.localAccessDenied
        }

        guard directoryURL.startAccessingSecurityScopedResource() else {
            throw VerificationError.localAccessDenied
        }
        defer { directoryURL.stopAccessingSecurityScopedResource() }

        var probe = try probeLocalDirectory(
            directoryURL,
            expectedRepository: expectedRepository
        )
        if isStale {
            probe.bookmarkData = try? directoryURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        return probe
    }
    #endif

    private static func probeCommand(path: String) -> String {
        let path = shellQuote(path)
        return """
        repo=\(path)
        case "$repo" in
          "~") repo="$HOME" ;;
          "~/"*) repo="$HOME/${repo#\\~/}" ;;
        esac
        if [ ! -d "$repo" ]; then
          printf 'state\\tpath_missing\\n'
          exit 0
        fi
        root=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || {
          printf 'state\\tnot_git\\n'
          exit 0
        }
        root=$(cd "$root" 2>/dev/null && pwd -P) || {
          printf 'state\\tnot_git\\n'
          exit 0
        }
        printf 'state\\tok\\n'
        printf 'root\\t%s\\n' "$root"
        git -C "$root" remote 2>/dev/null | while IFS= read -r remote_name; do
          remote_url=$(git -C "$root" remote get-url "$remote_name" 2>/dev/null) || continue
          printf 'remote\\t%s\\t%s\\n' "$remote_name" "$remote_url"
        done
        """
    }

    private static func remoteProbeCommand(path: String, remoteName: String) -> String {
        let path = shellQuote(path)
        let remoteName = shellQuote(remoteName)
        return """
        if GIT_TERMINAL_PROMPT=0 \
          GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1' \
          git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=10 \
          -C \(path) ls-remote \(remoteName) >/dev/null 2>&1
        then
          printf 'remote_ok\\n'
        else
          printf 'remote_failed\\n'
        fi
        """
    }

    private static func parse(_ output: String,
                              expectedRepository: String) throws -> RepositoryLocationProbe {
        var state: String?
        var root: String?
        var remotes: [(name: String, identity: String)] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                .map(String.init)
            guard let kind = fields.first else { continue }
            switch kind {
            case "state" where fields.count >= 2:
                state = fields[1]
            case "root" where fields.count >= 2:
                root = fields[1]
            case "remote" where fields.count >= 3:
                if let identity = GitHubRemoteIdentity.parse(fields[2]) {
                    remotes.append((fields[1], identity))
                }
            default:
                continue
            }
        }

        switch state {
        case "path_missing":
            throw VerificationError.pathMissing
        case "not_git":
            throw VerificationError.notGitRepository
        case "ok":
            break
        default:
            throw VerificationError.invalidResponse
        }

        guard let root, !root.isEmpty else {
            throw VerificationError.invalidResponse
        }

        let matched = try matchedRemote(
            remotes,
            expectedRepository: expectedRepository
        )
        return RepositoryLocationProbe(canonicalPath: root, remoteName: matched.name)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func matchedRemote(
        _ remotes: [(name: String, identity: String)],
        expectedRepository: String
    ) throws -> (name: String, identity: String) {
        let expected = expectedRepository.lowercased()
        if let matched = remotes.first(where: { $0.identity.lowercased() == expected }) {
            return matched
        }
        guard !remotes.isEmpty else {
            throw VerificationError.noGitHubRemote
        }
        throw VerificationError.repositoryMismatch(
            found: Array(Set(remotes.map(\.identity))).sorted()
        )
    }

    #if os(macOS)
    private static func probeLocalDirectory(
        _ selectedURL: URL,
        expectedRepository: String
    ) throws -> RepositoryLocationProbe {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw VerificationError.pathMissing
        }

        var candidate = selectedURL.resolvingSymlinksInPath().standardizedFileURL
        while true {
            let dotGitURL = candidate.appending(path: ".git")
            if fileManager.fileExists(atPath: dotGitURL.path) {
                let configURL = try gitConfigURL(dotGitURL: dotGitURL, workTreeURL: candidate)
                let remotes = try localRemotes(configURL: configURL)
                let matched = try matchedRemote(
                    remotes,
                    expectedRepository: expectedRepository
                )
                return RepositoryLocationProbe(
                    canonicalPath: candidate.path,
                    remoteName: matched.name
                )
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                throw VerificationError.notGitRepository
            }
            candidate = parent
        }
    }

    private static func gitConfigURL(dotGitURL: URL, workTreeURL: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: dotGitURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return dotGitURL.appending(path: "config")
        }

        guard let marker = try? String(contentsOf: dotGitURL, encoding: .utf8),
              let gitDirLine = marker.split(separator: "\n").first,
              gitDirLine.lowercased().hasPrefix("gitdir:")
        else {
            throw VerificationError.notGitRepository
        }

        let rawPath = gitDirLine.dropFirst("gitdir:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let gitDirectory = URL(
            fileURLWithPath: rawPath,
            relativeTo: workTreeURL
        ).standardizedFileURL
        let commonDirectoryMarker = gitDirectory.appending(path: "commondir")

        if let commonPath = try? String(contentsOf: commonDirectoryMarker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !commonPath.isEmpty {
            return URL(
                fileURLWithPath: commonPath,
                relativeTo: gitDirectory
            ).standardizedFileURL.appending(path: "config")
        }
        return gitDirectory.appending(path: "config")
    }

    private static func localRemotes(
        configURL: URL
    ) throws -> [(name: String, identity: String)] {
        guard let config = try? String(contentsOf: configURL, encoding: .utf8) else {
            throw VerificationError.noGitHubRemote
        }

        var currentRemoteName: String?
        var remotes: [(name: String, identity: String)] = []
        for rawLine in config.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                currentRemoteName = remoteName(fromSection: line)
                continue
            }
            guard let currentRemoteName,
                  let equals = line.firstIndex(of: "="),
                  line[..<equals].trimmingCharacters(in: .whitespaces).lowercased() == "url"
            else { continue }

            var value = line[line.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.first == "\"", value.last == "\"" {
                value.removeFirst()
                value.removeLast()
            }
            if let identity = GitHubRemoteIdentity.parse(value) {
                remotes.append((currentRemoteName, identity))
            }
        }
        return remotes
    }

    private static func remoteName(fromSection section: String) -> String? {
        let prefix = "[remote \""
        guard section.lowercased().hasPrefix(prefix),
              section.hasSuffix("\"]"),
              section.count > prefix.count + 2
        else { return nil }
        return String(section.dropFirst(prefix.count).dropLast(2))
    }
    #endif
}

private enum GitHubRemoteIdentity {
    static func parse(_ rawValue: String) -> String? {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: raw),
           let host = url.host?.lowercased(),
           host == "github.com" || host == "www.github.com" {
            return identity(fromPath: url.path)
        }

        // SCP-style SSH remote: git@github.com:owner/repository.git
        guard let separator = raw.firstIndex(of: ":") else { return nil }
        let hostPart = raw[..<separator].lowercased()
        guard hostPart == "github.com" || hostPart.hasSuffix("@github.com") else { return nil }
        return identity(fromPath: String(raw[raw.index(after: separator)...]))
    }

    private static func identity(fromPath path: String) -> String? {
        var components = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard components.count == 2 else { return nil }
        if components[1].lowercased().hasSuffix(".git") {
            components[1] = String(components[1].dropLast(4))
        }
        guard !components[0].isEmpty, !components[1].isEmpty else { return nil }
        return "\(components[0])/\(components[1])"
    }
}
