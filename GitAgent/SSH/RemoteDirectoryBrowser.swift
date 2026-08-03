//
//  RemoteDirectoryBrowser.swift
//  GitAgent
//
//  Lists directories on an SSH host for the step-by-step path picker.
//

import Foundation
import Citadel
import NIO

enum RemoteDirectoryBrowser {
    enum BrowseError: Error {
        case pathMissing
        case listingFailed
    }

    /// Resolves `path` on the host (`~` is allowed) and lists its immediate
    /// subdirectories. Returns the canonical path and the folder names.
    static func listDirectories(
        route: SSHConnectionRoute,
        path: String
    ) async throws -> (path: String, directories: [String]) {
        let connection = try await SSHConnection.connect(route: route)

        do {
            let output = try await connection.client.executeCommand(
                listCommand(path: path),
                maxResponseSize: 1_000_000,
                mergeStreams: false,
                inShell: false
            )
            await connection.close()
            return try parse(String(decoding: output.readableBytesView, as: UTF8.self))
        } catch {
            await connection.close()
            throw error
        }
    }

    private static func listCommand(path: String) -> String {
        let path = shellQuote(path)
        return """
        dir=\(path)
        case "$dir" in
          "~") dir="$HOME" ;;
          "~/"*) dir="$HOME/${dir#\\~/}" ;;
        esac
        if [ ! -d "$dir" ]; then
          printf 'state\\tmissing\\n'
          exit 0
        fi
        cd "$dir" 2>/dev/null || {
          printf 'state\\tmissing\\n'
          exit 0
        }
        printf 'state\\tok\\n'
        printf 'path\\t%s\\n' "$(pwd -P)"
        for entry in */; do
          [ -d "$entry" ] || continue
          printf 'dir\\t%s\\n' "${entry%/}"
        done
        """
    }

    private static func parse(_ output: String) throws -> (path: String, directories: [String]) {
        var state: String?
        var path: String?
        var directories: [String] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                .map(String.init)
            guard let kind = fields.first else { continue }
            switch kind {
            case "state" where fields.count >= 2:
                state = fields[1]
            case "path" where fields.count >= 2:
                path = fields[1]
            case "dir" where fields.count >= 2:
                directories.append(fields[1])
            default:
                continue
            }
        }

        switch state {
        case "missing":
            throw BrowseError.pathMissing
        case "ok":
            guard let path, !path.isEmpty else { throw BrowseError.listingFailed }
            return (path, directories.sorted())
        default:
            throw BrowseError.listingFailed
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
