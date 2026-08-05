//
//  CoderModels.swift
//  GitAgent
//
//  Models for the Coder agent: interactive coding-CLI sessions (Kimi Code,
//  Claude Code, or Codex) running inside tmux on a connected repository
//  working tree. The app creates and probes the tmux sessions; interaction
//  happens in a full terminal (xterm.js) that attaches to them.
//
//  The CLIs run in yolo mode (`--yolo` / `--dangerously-skip-permissions` /
//  `--dangerously-bypass-approvals-and-sandbox`): fully automatic, no
//  confirmation loop, as explicitly requested by the user. This deliberately
//  differs from the confirmation-loop route laid out in Docs/Agent.md.
//

import Foundation

/// Supported coding CLIs. All command construction lives here so a CLI
/// version bump only requires touching this enum.
enum CoderTool: String, Codable, CaseIterable, Identifiable {
  case kimi
  case claude
  case codex

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .kimi: return "Kimi Code"
    case .claude: return "Claude Code"
    case .codex: return "Codex"
    }
  }

  var commandName: String { rawValue }

  /// Prepended wherever the app probes for or launches a CLI/tmux: GUI apps
  /// and non-login SSH shells miss the Homebrew/npm/user bin directories.
  static let pathExport =
    "export PATH=\"$HOME/.kimi-code/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\""

  /// All Coder tmux sessions live on a dedicated tmux server socket, so
  /// server options (extended keys) and session names never collide with the
  /// user's own tmux sessions.
  static let tmux = "tmux -L gitagent"

  /// Preflight probe: tmux and the CLI itself must be reachable.
  var preflightCommand: String {
    """
    \(Self.pathExport)
    if command -v tmux >/dev/null 2>&1; then printf 'tmux\\tok\\n'; else printf 'tmux\\tmissing\\n'; fi
    if command -v \(commandName) >/dev/null 2>&1; then printf 'tool\\tok\\n'; else printf 'tool\\tmissing\\n'; fi
    """
  }

  /// The pane command for `tmux new-session`: starts the interactive CLI in
  /// yolo mode with the optional initial prompt as a positional argument.
  /// `dir` (the session directory) is defined by the first line, so hook
  /// paths expand in the pane's shell — the whole string is later quoted
  /// once more for the shell that runs tmux (one layer per shell).
  func interactiveCommand(sessionID: UUID, prompt: String?) -> String {
    let promptArgument: String
    if let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
      promptArgument = " \(Self.shellQuote(prompt))"
    } else {
      promptArgument = ""
    }
    let cli: String
    switch self {
    case .kimi:
      // Kimi has no per-invocation hooks; completion is approximated from
      // tmux output activity instead.
      cli = "kimi --yolo\(promptArgument)"
    case .claude:
      cli =
        "claude --dangerously-skip-permissions --settings \"$dir/settings.json\"\(promptArgument)"
    case .codex:
      cli =
        "codex --dangerously-bypass-approvals-and-sandbox"
        + " -c \"notify=[\\\"bash\\\",\\\"$dir/notify.sh\\\"]\"\(promptArgument)"
    }
    return [
      "dir=\"$HOME/.gitagent/coder/\(sessionID.uuidString.lowercased())\"",
      Self.pathExport,
      cli,
    ].joined(separator: "; ")
  }

  /// Companion scripts installed next to the session for CLIs that support
  /// per-invocation completion hooks. Each script locates the session
  /// directory via `$0` and appends a timestamp to `turn-done`, which the
  /// probe counts. Claude's settings.json cannot be written this way (it
  /// needs the concrete hook path) — the executor emits it with shell
  /// expansion instead, see `claudeSettingsCommand`.
  func hookFiles() -> [(name: String, content: String)] {
    switch self {
    case .kimi:
      return []
    case .claude:
      return [
        (
          "hook-stop.sh",
          """
          #!/bin/bash
          dir="$(cd "$(dirname "$0")" && pwd)"
          cat > "$dir/hook-stop.json"
          date +%s >> "$dir/turn-done"
          """
        )
      ]
    case .codex:
      return [
        (
          "notify.sh",
          """
          #!/bin/bash
          dir="$(cd "$(dirname "$0")" && pwd)"
          printf '%s' "${@: -1}" > "$dir/notify.json"
          date +%s >> "$dir/turn-done"
          """
        )
      ]
    }
  }

  /// Shell fragment that writes claude's per-invocation Stop-hook settings;
  /// runs where `$dir` is defined so the hook path comes out absolute.
  var claudeSettingsCommand: String? {
    guard self == .claude else { return nil }
    return
      "printf '%s\\n' '{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"bash '\"$dir\"'/hook-stop.sh\"}]}]}}' > \"$dir/settings.json\""
  }

  private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  }
}

/// A managed tmux session running a coding CLI on a working tree. Runtime
/// state (alive, turn-finished) is probed, not persisted.
struct CoderSessionRecord: Codable, Identifiable {
  let id: UUID
  var tool: CoderTool
  var repositoryFullName: String
  let locationID: RepositoryLocation.ID
  /// nil means the session runs on this Mac.
  let hostID: SSHHostConfig.ID?
  var path: String
  var initialPrompt: String?
  let createdAt: Date
}

/// Snapshot of a session's on-target state from one probe.
struct CoderProbe {
  let alive: Bool
  /// tmux `#{window_activity}`: timestamp of the last pane output.
  let activity: Int
  /// Number of completion timestamps appended by the CLI hooks.
  let done: Int
}

enum CoderError: LocalizedError {
  case localUnavailable
  case sshHostUnavailable
  case tmuxUnavailable
  case toolUnavailable

  var errorDescription: String? {
    switch self {
    case .localUnavailable:
      return L10n.resolveCurrent(.coderLocalUnavailable)
    case .sshHostUnavailable:
      return L10n.resolveCurrent(.computerUnavailable)
    case .tmuxUnavailable:
      return L10n.resolveCurrent(.repoLaunchTmuxUnavailable)
    case .toolUnavailable:
      return L10n.resolveCurrent(.coderToolUnavailable)
    }
  }
}
