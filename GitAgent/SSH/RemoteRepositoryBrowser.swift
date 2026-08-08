//
//  RemoteRepositoryBrowser.swift
//  GitAgent
//
//  Read-only directory and file access inside a verified SSH working tree.
//

import Citadel
import Foundation
import NIO

enum RemoteRepositoryBrowser {
    enum BrowserError: Error {
        case pathMissing
        case outsideRepository
        case fileTooLarge
        case invalidResponse
    }

    enum ItemKind: String, Hashable {
        case directory
        case file
    }

    struct Item: Identifiable, Hashable {
        let name: String
        let relativePath: String
        let kind: ItemKind
        let size: Int

        var id: String { relativePath }
    }

    static func listItems(
        route: SSHConnectionRoute,
        rootPath: String,
        relativePath: String
    ) async throws -> [Item] {
        let connection = try await SSHConnection.connect(route: route)
        do {
            let output = try await connection.client.executeCommand(
                listCommand(rootPath: rootPath, relativePath: relativePath),
                maxResponseSize: 4_000_000,
                mergeStreams: false,
                inShell: false
            )
            await connection.close()
            return try parseItems(String(decoding: output.readableBytesView, as: UTF8.self),
                                  parentPath: relativePath)
        } catch {
            if SSHConnection.isTransientFailure(error) {
                await connection.invalidate()
            } else {
                await connection.close()
            }
            throw error
        }
    }

    static func kind(
        route: SSHConnectionRoute,
        rootPath: String,
        relativePath: String
    ) async throws -> ItemKind {
        let connection = try await SSHConnection.connect(route: route)
        do {
            let output = try await connection.client.executeCommand(
                kindCommand(rootPath: rootPath, relativePath: relativePath),
                maxResponseSize: 4_096,
                mergeStreams: false,
                inShell: false
            )
            await connection.close()
            let response = String(decoding: output.readableBytesView, as: UTF8.self)
            switch state(in: response) {
            case "directory": return .directory
            case "file": return .file
            case "missing": throw BrowserError.pathMissing
            case "outside": throw BrowserError.outsideRepository
            default: throw BrowserError.invalidResponse
            }
        } catch {
            if SSHConnection.isTransientFailure(error) {
                await connection.invalidate()
            } else {
                await connection.close()
            }
            throw error
        }
    }

    static func readFile(
        route: SSHConnectionRoute,
        rootPath: String,
        relativePath: String,
        maximumBytes: Int = 16_000_000
    ) async throws -> Data {
        let connection = try await SSHConnection.connect(route: route)
        do {
            let output = try await connection.client.executeCommand(
                readCommand(
                    rootPath: rootPath,
                    relativePath: relativePath,
                    maximumBytes: maximumBytes
                ),
                maxResponseSize: maximumBytes * 2 + 4_096,
                mergeStreams: false,
                inShell: false
            )
            await connection.close()
            return try parseFile(String(decoding: output.readableBytesView, as: UTF8.self))
        } catch {
            if SSHConnection.isTransientFailure(error) {
                await connection.invalidate()
            } else {
                await connection.close()
            }
            throw error
        }
    }

    private static func listCommand(rootPath: String, relativePath: String) -> String {
        let root = shellQuote(rootPath)
        let relative = shellQuote(relativePath)
        return """
        root=\(root)
        relative=\(relative)
        root=$(cd "$root" 2>/dev/null && pwd -P) || {
          printf 'state\\tmissing\\n'
          exit 0
        }
        case "$relative" in
          "") candidate="$root" ;;
          /*|..|../*|*/../*|*/..) printf 'state\\toutside\\n'; exit 0 ;;
          *) candidate="$root/$relative" ;;
        esac
        dir=$(cd "$candidate" 2>/dev/null && pwd -P) || {
          printf 'state\\tmissing\\n'
          exit 0
        }
        if [ "$root" != "/" ]; then
          case "$dir" in
            "$root"|"$root"/*) ;;
            *) printf 'state\\toutside\\n'; exit 0 ;;
          esac
        fi
        printf 'state\\tok\\n'
        for entry in "$dir"/*; do
          [ -e "$entry" ] || continue
          [ -L "$entry" ] && continue
          name=${entry##*/}
          encoded=$(printf '%s' "$name" | base64 | tr -d '\\r\\n')
          if [ -d "$entry" ]; then
            printf 'item\\tdirectory\\t0\\t%s\\n' "$encoded"
          elif [ -f "$entry" ]; then
            size=$(wc -c < "$entry" | tr -d '[:space:]')
            printf 'item\\tfile\\t%s\\t%s\\n' "$size" "$encoded"
          fi
        done
        """
    }

    private static func kindCommand(rootPath: String, relativePath: String) -> String {
        targetPrelude(rootPath: rootPath, relativePath: relativePath) + "\n" + """
        if [ -d "$target" ]; then
          resolved=$(cd "$target" 2>/dev/null && pwd -P) || {
            printf 'state\\tmissing\\n'; exit 0
          }
          if [ "$root" != "/" ]; then
            case "$resolved" in
              "$root"|"$root"/*) ;;
              *) printf 'state\\toutside\\n'; exit 0 ;;
            esac
          fi
          printf 'state\\tdirectory\\n'
        elif [ -f "$target" ]; then
          printf 'state\\tfile\\n'
        else
          printf 'state\\tmissing\\n'
        fi
        """
    }

    private static func readCommand(
        rootPath: String,
        relativePath: String,
        maximumBytes: Int
    ) -> String {
        targetPrelude(rootPath: rootPath, relativePath: relativePath) + "\n" + """
        [ -f "$target" ] || {
          printf 'state\\tmissing\\n'
          exit 0
        }
        size=$(wc -c < "$target" | tr -d '[:space:]')
        if [ "$size" -gt \(maximumBytes) ]; then
          printf 'state\\ttoo_large\\n'
          exit 0
        fi
        printf 'state\\tok\\n'
        printf 'data\\t'
        base64 < "$target" | tr -d '\\r\\n'
        printf '\\n'
        """
    }

    /// Resolves a non-symlink file target and verifies that its parent remains
    /// within the working tree. Directories receive an additional canonical
    /// containment check in `kindCommand` and `listCommand`.
    private static func targetPrelude(rootPath: String, relativePath: String) -> String {
        let root = shellQuote(rootPath)
        let relative = shellQuote(relativePath)
        return """
        root=\(root)
        relative=\(relative)
        root=$(cd "$root" 2>/dev/null && pwd -P) || {
          printf 'state\\tmissing\\n'; exit 0
        }
        case "$relative" in
          ""|/*|..|../*|*/../*|*/..) printf 'state\\toutside\\n'; exit 0 ;;
        esac
        target="$root/$relative"
        [ -L "$target" ] && {
          printf 'state\\toutside\\n'; exit 0
        }
        parent=$(dirname "$target")
        parent=$(cd "$parent" 2>/dev/null && pwd -P) || {
          printf 'state\\tmissing\\n'; exit 0
        }
        if [ "$root" != "/" ]; then
          case "$parent" in
            "$root"|"$root"/*) ;;
            *) printf 'state\\toutside\\n'; exit 0 ;;
          esac
        fi
        """
    }

    private static func parseItems(_ response: String, parentPath: String) throws -> [Item] {
        switch state(in: response) {
        case "missing": throw BrowserError.pathMissing
        case "outside": throw BrowserError.outsideRepository
        case "ok": break
        default: throw BrowserError.invalidResponse
        }

        var items: [Item] = []
        for line in response.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\t", maxSplits: 3,
                                    omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, fields[0] == "item",
                  let kind = ItemKind(rawValue: fields[1]),
                  let size = Int(fields[2]),
                  let nameData = Data(base64Encoded: fields[3]),
                  let name = String(data: nameData, encoding: .utf8),
                  !name.isEmpty else { continue }
            let relativePath = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
            items.append(Item(name: name, relativePath: relativePath, kind: kind, size: size))
        }
        return items.sorted {
            if $0.kind != $1.kind { return $0.kind == .directory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func parseFile(_ response: String) throws -> Data {
        switch state(in: response) {
        case "missing": throw BrowserError.pathMissing
        case "outside": throw BrowserError.outsideRepository
        case "too_large": throw BrowserError.fileTooLarge
        case "ok": break
        default: throw BrowserError.invalidResponse
        }
        guard let dataLine = response.split(separator: "\n", omittingEmptySubsequences: false)
            .first(where: { $0.hasPrefix("data\t") }),
              let data = Data(base64Encoded: String(dataLine.dropFirst(5))) else {
            throw BrowserError.invalidResponse
        }
        return data
    }

    private static func state(in response: String) -> String? {
        for line in response.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\t", maxSplits: 1,
                                    omittingEmptySubsequences: false)
            if fields.count == 2, fields[0] == "state" {
                return String(fields[1])
            }
        }
        return nil
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
