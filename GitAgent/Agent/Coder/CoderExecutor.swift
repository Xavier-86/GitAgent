//
//  CoderExecutor.swift
//  GitAgent
//
//  Creates, probes, and kills the detached tmux sessions that run Coder's
//  interactive coding CLIs, locally or over SSH. Unlike the RepoLaunch
//  executor there is no dispatch/poll lifecycle here: the CLI runs
//  interactively inside tmux, the user attaches through CoderTerminalView,
//  and this type only manages the session's existence and liveness.
//

import Citadel
import Foundation
import NIO

@MainActor
enum CoderExecutor {
  private static func sessionDirectory(for recordID: UUID) -> String {
    "$HOME/.gitagent/coder/\(recordID.uuidString.lowercased())"
  }

  private static func tmuxSession(for recordID: UUID) -> String {
    "ga-coder-\(recordID.uuidString.lowercased())"
  }

  private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  }

  // MARK: - Create

  /// Starts the CLI in a detached tmux session on the target. Throws on
  /// preflight or tmux failures; the session then never existed.
  static func createSession(record: CoderSessionRecord, route: SSHConnectionRoute?) async throws {
    if let route {
      guard route.target.id == record.hostID else {
        throw CoderError.sshHostUnavailable
      }
      let connection = try await SSHConnection.connect(route: route)
      do {
        try await preflightRemote(record.tool, using: connection)
        _ = try await runRemote(connection, sessionScript(record: record))
        await connection.close()
      } catch {
        await connection.close()
        throw error
      }
      return
    }
    #if os(macOS)
      let preflight = await runLocalShell(record.tool.preflightCommand)
      guard preflight.output.contains("tmux\tok") else { throw CoderError.tmuxUnavailable }
      guard preflight.output.contains("tool\tok") else { throw CoderError.toolUnavailable }
      let result = await runLocalShell(sessionScript(record: record))
      guard result.status == 0 else { throw CoderError.tmuxUnavailable }
    #else
      throw CoderError.localUnavailable
    #endif
  }

  private static func preflightRemote(_ tool: CoderTool, using connection: SSHConnection)
    async throws
  {
    let output = try await runRemote(connection, tool.preflightCommand)
    guard output.contains("tmux\tok") else { throw CoderError.tmuxUnavailable }
    guard output.contains("tool\tok") else { throw CoderError.toolUnavailable }
  }

  /// One shell script used on both channels: writes the hook files and
  /// starts the detached tmux session running the interactive CLI.
  private static func sessionScript(record: CoderSessionRecord) -> String {
    var commands: [String] = [
      "set -eu",
      CoderTool.pathExport,
      "dir=\"\(sessionDirectory(for: record.id))\"",
      "session='\(tmuxSession(for: record.id))'",
      "workdir=\(shellQuote(record.path))",
      "case \"$workdir\" in",
      "  \"~\") workdir=\"$HOME\" ;;",
      "  \"~/\"*) workdir=\"$HOME/${workdir#\\~/}\" ;;",
      "esac",
      "mkdir -p \"$dir\"",
    ]
    for file in record.tool.hookFiles() {
      let encoded = Data(file.content.utf8).base64EncodedString()
      commands.append("printf '%s' '\(encoded)' | base64 -d > \"$dir/\(file.name)\"")
    }
    if let settingsCommand = record.tool.claudeSettingsCommand {
      commands.append(settingsCommand)
    }
    commands.append(
      "if \(CoderTool.tmux) has-session -t \"$session\" 2>/dev/null; then \(CoderTool.tmux) kill-session -t \"$session\"; fi"
    )
    // The pane command is quoted once for this shell; tmux passes it to the
    // pane's `sh -c`, which strips the second layer (prompt included).
    let pane = record.tool.interactiveCommand(
      sessionID: record.id,
      prompt: record.initialPrompt
    )
    commands.append(
      "\(CoderTool.tmux) new-session -d -s \"$session\" -c \"$workdir\" \(shellQuote(pane))"
    )
    // Kimi's TUI only submits on Enter when the tmux server negotiates csi-u
    // extended keys. These are server options — setting them on the dedicated
    // socket never affects the user's own tmux (extended-keys-format needs
    // tmux 3.5+, hence the fallback).
    commands.append("\(CoderTool.tmux) set-option -s extended-keys on 2>/dev/null || true")
    commands.append("\(CoderTool.tmux) set-option -s extended-keys-format csi-u 2>/dev/null || true")
    return commands.joined(separator: "\n")
  }

  // MARK: - Probe

  /// One command returning the session's liveness, last pane-output
  /// timestamp, and CLI-hook completion count. Throws on transport failure;
  /// the caller keeps the previous state and retries on the next cycle.
  static func probe(record: CoderSessionRecord, route: SSHConnectionRoute?) async throws
    -> CoderProbe
  {
    let output: String
    if let route {
      let connection = try await SSHConnection.connect(route: route)
      do {
        output = try await runRemote(connection, probeCommand(recordID: record.id))
        await connection.close()
      } catch {
        await connection.close()
        throw error
      }
    } else {
      #if os(macOS)
        output = await runLocalShell(probeCommand(recordID: record.id)).output
      #else
        throw CoderError.localUnavailable
      #endif
    }
    return parseProbe(output)
  }

  private static func probeCommand(recordID: UUID) -> String {
    """
    \(CoderTool.pathExport)
    dir="\(sessionDirectory(for: recordID))"
    session='\(tmuxSession(for: recordID))'
    if \(CoderTool.tmux) has-session -t "$session" 2>/dev/null; then printf 'alive\\t1\\n'; else printf 'alive\\t0\\n'; fi
    activity=$(\(CoderTool.tmux) display-message -p -t "$session" '#{window_activity}' 2>/dev/null)
    printf 'activity\\t%s\\n' "${activity:-0}"
    if [ -f "$dir/turn-done" ]; then count=$(wc -l < "$dir/turn-done" | tr -d ' '); else count=0; fi
    printf 'done\\t%s\\n' "$count"
    """
  }

  private static func parseProbe(_ raw: String) -> CoderProbe {
    var alive = false
    var activity = 0
    var done = 0
    for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
      let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
      guard let key = fields.first, fields.count > 1 else { continue }
      let value = fields[1].trimmingCharacters(in: .whitespaces)
      switch key {
      case "alive": alive = value == "1"
      case "activity": activity = Int(value) ?? 0
      case "done": done = Int(value) ?? 0
      default: continue
      }
    }
    return CoderProbe(alive: alive, activity: activity, done: done)
  }

  // MARK: - Kill

  /// Best-effort teardown of the tmux session. The session directory stays
  /// (hook payloads and turn-done history belong to the record's lifetime).
  static func killSession(record: CoderSessionRecord, route: SSHConnectionRoute?) async {
    let command = """
      \(CoderTool.pathExport)
      \(CoderTool.tmux) kill-session -t '\(tmuxSession(for: record.id))' 2>/dev/null || true
      """
    if let route {
      guard let connection = try? await SSHConnection.connect(route: route) else { return }
      _ = try? await runRemote(connection, command)
      await connection.close()
      return
    }
    #if os(macOS)
      _ = await runLocalShell(command)
    #endif
  }

  // MARK: - Channels

  private static func runRemote(_ connection: SSHConnection, _ command: String) async throws
    -> String
  {
    let buffer = try await connection.client.executeCommand(
      command,
      maxResponseSize: 400_000,
      mergeStreams: false,
      inShell: false
    )
    return String(decoding: buffer.readableBytesView, as: UTF8.self)
  }

  #if os(macOS)
    /// Runs a command through the user's login shell and reports its exit
    /// status instead of throwing, so probes can branch on it. `-i` pulls in
    /// .zshrc as well — many users only put their Homebrew/npm PATH edits
    /// there, not in the login profile.
    private static func runLocalShell(_ command: String) async -> (
      status: Int32, output: String
    ) {
      await withCheckedContinuation { continuation in
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
          let data = pipe.fileHandleForReading.readDataToEndOfFile()
          continuation.resume(
            returning: (finished.terminationStatus, String(decoding: data, as: UTF8.self))
          )
        }
        do {
          try process.run()
        } catch {
          continuation.resume(returning: (-1, ""))
        }
      }
    }
  #endif
}
