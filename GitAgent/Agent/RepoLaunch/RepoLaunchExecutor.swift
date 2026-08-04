//
//  RepoLaunchExecutor.swift
//  GitAgent
//
//  Executes the staged deployment plan locally or, over SSH, detached on the
//  host inside tmux so deployments outlive the app's connection.
//

import Citadel
import Foundation
import NIO

private struct RepoLaunchCommandError: LocalizedError {
  let stage: RepoLaunchStage
  let exitCode: Int32

  var errorDescription: String? {
    "\(stage.rawValue.capitalized) failed with exit code \(exitCode)."
  }
}

@MainActor
enum RepoLaunchExecutor {
  typealias StageHandler = (RepoLaunchStage) -> Void
  typealias OutputHandler = (String) -> Void

  static func deploy(
    _ request: RepoLaunchRequest,
    route: SSHConnectionRoute?,
    deploymentID: UUID,
    onStage: @escaping StageHandler,
    onOutput: @escaping OutputHandler
  ) async throws -> RepoLaunchResult {
    try validate(request)
    if request.isLocal {
      #if os(macOS)
        return try await deployLocal(
          request,
          deploymentID: deploymentID,
          onStage: onStage,
          onOutput: onOutput
        )
      #else
        throw RepoLaunchError.localDeploymentUnavailable
      #endif
    }

    guard let route, route.target.id == request.hostID else {
      throw RepoLaunchError.sshHostUnavailable
    }
    return try await deployRemote(
      request,
      deploymentID: deploymentID,
      route: route,
      onStage: onStage,
      onOutput: onOutput
    )
  }

  private static func validate(_ request: RepoLaunchRequest) throws {
    let repositoryURL = request.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !repositoryURL.isEmpty,
      !repositoryURL.contains("\n"),
      !repositoryURL.contains("\r"),
      !repositoryURL.contains("\0"),
      isSupportedRepositoryURL(repositoryURL)
    else {
      throw RepoLaunchError.invalidRepositoryURL
    }

    let destination = request.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !destination.isEmpty,
      !destination.contains("\n"),
      !destination.contains("\r"),
      !destination.contains("\0")
    else {
      throw RepoLaunchError.invalidDestination
    }

    guard !request.reference.contains("\n"),
      !request.reference.contains("\r"),
      !request.reference.contains("\0")
    else {
      throw RepoLaunchError.invalidRepositoryURL
    }
  }

  private static func isSupportedRepositoryURL(_ value: String) -> Bool {
    if value.range(
      of: #"^[^/@\s]+@[^:/\s]+:.+$"#,
      options: .regularExpression) != nil
    {
      return true
    }
    guard let components = URLComponents(string: value),
      let scheme = components.scheme?.lowercased(),
      ["https", "http", "ssh", "git"].contains(scheme),
      components.host != nil,
      components.password == nil
    else { return false }
    // Credential-bearing clone URLs must never enter deployment history.
    if scheme == "https" || scheme == "http", components.user != nil {
      return false
    }
    return true
  }

  private static func stageScripts(for request: RepoLaunchRequest) -> [(RepoLaunchStage, String)] {
    var scripts: [(RepoLaunchStage, String)] = [
      (.preflight, preflightScript),
      (.checkout, checkoutScript(request)),
    ]
    appendCommands(request.setupCommands, stage: .setup, request: request, to: &scripts)
    appendCommands(request.buildCommands, stage: .build, request: request, to: &scripts)
    appendCommands(request.testCommands, stage: .test, request: request, to: &scripts)
    scripts.append((.verify, verifyScript(request)))
    return scripts
  }

  private static func appendCommands(
    _ commands: String,
    stage: RepoLaunchStage,
    request: RepoLaunchRequest,
    to scripts: inout [(RepoLaunchStage, String)]
  ) {
    let trimmed = commands.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    scripts.append(
      (
        stage,
        """
        set -eu
        \(destinationAssignment(request.destinationPath))
        cd "$destination"
        \(trimmed)
        """
      ))
  }

  private static let preflightScript = """
    set -eu
    command -v git >/dev/null 2>&1 || {
      printf 'Git is required on the deployment computer.\n' >&2
      exit 127
    }
    git --version
    """

  private static func checkoutScript(_ request: RepoLaunchRequest) -> String {
    let repositoryURL = shellQuote(
      request.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    let reference = shellQuote(
      request.reference.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    return """
      set -eu
      repository_url=\(repositoryURL)
      reference=\(reference)
      \(destinationAssignment(request.destinationPath))
      parent=$(dirname "$destination")
      mkdir -p "$parent"

      if [ -e "$destination" ]; then
        git -C "$destination" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
          printf 'Destination exists but is not a Git working tree: %s\n' "$destination" >&2
          exit 2
        }
        actual_remote=$(git -C "$destination" remote get-url origin 2>/dev/null || true)
        if [ "$actual_remote" != "$repository_url" ]; then
          printf 'Destination origin does not match the requested repository.\nExpected: %s\nFound: %s\n' \
            "$repository_url" "$actual_remote" >&2
          exit 3
        fi
        if [ -n "$(git -C "$destination" status --porcelain --untracked-files=no)" ]; then
          printf 'Destination has tracked changes; refusing to overwrite them.\n' >&2
          exit 4
        fi
        GIT_TERMINAL_PROMPT=0 git -C "$destination" fetch --progress --prune --tags origin
      else
        GIT_TERMINAL_PROMPT=0 git clone --progress --recurse-submodules -- "$repository_url" "$destination"
      fi

      if [ -n "$reference" ]; then
        if commit=$(git -C "$destination" rev-parse --verify "$reference^{commit}" 2>/dev/null); then
          :
        elif commit=$(git -C "$destination" rev-parse --verify "origin/$reference^{commit}" 2>/dev/null); then
          :
        else
          GIT_TERMINAL_PROMPT=0 git -C "$destination" fetch --progress origin "$reference"
          commit=$(git -C "$destination" rev-parse --verify FETCH_HEAD^{commit})
        fi
        git -C "$destination" checkout --detach "$commit"
      else
        branch=$(git -C "$destination" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
        if [ -n "$branch" ] && git -C "$destination" rev-parse --verify "origin/$branch^{commit}" >/dev/null 2>&1; then
          git -C "$destination" merge --ff-only "origin/$branch"
        fi
      fi

      git -C "$destination" submodule sync --recursive
      GIT_TERMINAL_PROMPT=0 git -C "$destination" submodule update --init --recursive --progress
      """
  }

  private static func verifyScript(_ request: RepoLaunchRequest) -> String {
    """
    set -eu
    \(destinationAssignment(request.destinationPath))
    root=$(git -C "$destination" rev-parse --show-toplevel)
    root=$(cd "$root" && pwd -P)
    remote_url=$(git -C "$root" remote get-url origin)
    commit=$(git -C "$root" rev-parse HEAD)
    printf 'root\t%s\n' "$root"
    printf 'remote\t%s\n' "$remote_url"
    printf 'commit\t%s\n' "$commit"
    """
  }

  private static func destinationAssignment(_ path: String) -> String {
    """
    destination=\(shellQuote(path.trimmingCharacters(in: .whitespacesAndNewlines)))
    case "$destination" in
      "~") destination="$HOME" ;;
      "~/"*) destination="$HOME/${destination#\\~/}" ;;
    esac
    """
  }

  private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  }

  private static func parseResult(
    _ output: String,
    localBookmarkData: Data?
  ) throws -> RepoLaunchResult {
    var root: String?
    var remote: String?
    var commit: String?
    for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
      let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
      guard fields.count == 2 else { continue }
      switch fields[0] {
      case "root": root = String(fields[1])
      case "remote": remote = String(fields[1])
      case "commit": commit = String(fields[1])
      default: continue
      }
    }
    guard let root, !root.isEmpty,
      let remote, !remote.isEmpty,
      let commit, !commit.isEmpty
    else {
      throw RepoLaunchError.invalidVerificationResponse
    }
    return RepoLaunchResult(
      canonicalPath: root,
      commit: commit,
      localBookmarkData: localBookmarkData
    )
  }

  // MARK: - Remote deployment (tmux dispatch/poll)
  //
  // SSH deployments run detached on the host: a short exec writes the stage
  // scripts plus a runner into ~/.gitagent/repolaunch/<id>/ and starts the
  // runner inside a tmux session. The app then polls the session, the runner's
  // status files, and run.log over short-lived exec calls, so the deployment
  // survives the app being closed or iOS suspending the socket. The store
  // re-attaches with `attachRemote` after a connection drop or an app restart.

  private static let remotePollInterval: UInt64 = 2_000_000_000
  private static let remoteLogFetchLimit = 250_000
  private static let remoteLogMarker = "__GITAGENT_LOG__"

  private static func remoteDirectory(for deploymentID: UUID) -> String {
    "$HOME/.gitagent/repolaunch/\(deploymentID.uuidString.lowercased())"
  }

  private static func tmuxSession(for deploymentID: UUID) -> String {
    "ga-rl-\(deploymentID.uuidString.lowercased())"
  }

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

  private static func deployRemote(
    _ request: RepoLaunchRequest,
    deploymentID: UUID,
    route: SSHConnectionRoute,
    onStage: @escaping StageHandler,
    onOutput: @escaping OutputHandler
  ) async throws -> RepoLaunchResult {
    let connection = try await SSHConnection.connect(route: route)
    do {
      try await ensureTmux(connection)
      try Task.checkCancellation()
      try await dispatch(request, deploymentID: deploymentID, using: connection)
      await connection.close()
    } catch {
      // Dispatch failed (or was cancelled) — make sure nothing half-started
      // keeps running under this deployment's session name.
      _ = try? await runRemote(connection, killCommand(deploymentID: deploymentID))
      await connection.close()
      throw error
    }
    return try await pollRemote(
      deploymentID: deploymentID,
      route: route,
      resume: false,
      onStage: onStage,
      onOutput: onOutput,
      onLogReset: nil
    )
  }

  /// Re-attaches to a detached remote run that is already on the host,
  /// replacing the local log with the remote one before tailing it.
  static func attachRemote(
    deploymentID: UUID,
    route: SSHConnectionRoute,
    onStage: @escaping StageHandler,
    onOutput: @escaping OutputHandler,
    onLogReset: @escaping OutputHandler
  ) async throws -> RepoLaunchResult {
    try await pollRemote(
      deploymentID: deploymentID,
      route: route,
      resume: true,
      onStage: onStage,
      onOutput: onOutput,
      onLogReset: onLogReset
    )
  }

  private static func ensureTmux(_ connection: SSHConnection) async throws {
    let output = try await runRemote(
      connection,
      "command -v tmux >/dev/null 2>&1 && printf 'tmux\\tok\\n' || printf 'tmux\\tmissing\\n'"
    )
    guard output.contains("tmux\tok") else {
      throw RepoLaunchError.tmuxUnavailable
    }
  }

  private static func dispatch(
    _ request: RepoLaunchRequest,
    deploymentID: UUID,
    using connection: SSHConnection
  ) async throws {
    let stages = stageScripts(for: request)
    var commands: [String] = [
      "set -eu",
      "dir=\"\(remoteDirectory(for: deploymentID))\"",
      "session='\(tmuxSession(for: deploymentID))'",
      "rm -rf \"$dir\"",
      "mkdir -p \"$dir\"",
    ]
    for (stage, script) in stages {
      let encoded = Data(script.utf8).base64EncodedString()
      commands.append("printf '%s' '\(encoded)' | base64 -d > \"$dir/\(stage.rawValue).sh\"")
    }
    let runner = Data(runnerScript(stages: stages.map(\.0)).utf8).base64EncodedString()
    commands.append("printf '%s' '\(runner)' | base64 -d > \"$dir/runner.sh\"")
    commands.append(
      "if tmux has-session -t \"$session\" 2>/dev/null; then tmux kill-session -t \"$session\"; fi"
    )
    commands.append("tmux new-session -d -s \"$session\" \"bash \\\"$dir/runner.sh\\\"\"")
    _ = try await runRemote(connection, commands.joined(separator: "\n"))
  }

  /// Runs every stage in order on the host, keeping run.log self-contained
  /// (stage headers included) so a re-attaching app can adopt it wholesale.
  private static func runnerScript(stages: [RepoLaunchStage]) -> String {
    var lines: [String] = [
      "cd \"$(dirname \"$0\")\" || exit 1",
      "dir=$PWD",
      ": > run.log",
      "run_stage() {",
      "  printf '%s\\n' \"$1\" > current",
      "  printf '\\n[%s]\\n' \"$(printf '%s' \"$1\" | tr '[:lower:]' '[:upper:]')\" >> run.log",
      "  bash \"$dir/$1.sh\" >> run.log 2>&1",
      "  code=$?",
      "  if [ \"$code\" -ne 0 ]; then",
      "    printf 'failed\\t%s\\t%s\\n' \"$1\" \"$code\" > result",
      "    exit \"$code\"",
      "  fi",
      "}",
    ]
    for stage in stages where stage != .verify {
      lines.append("run_stage \(stage.rawValue)")
    }
    if stages.contains(.verify) {
      // The verify stage's stdout is the machine-readable result, so it is
      // captured separately and only mirrored into run.log afterwards.
      lines.append(contentsOf: [
        "printf 'verify\\n' > current",
        "printf '\\n[VERIFY]\\n' >> run.log",
        "bash \"$dir/verify.sh\" > verify.out 2>> run.log",
        "code=$?",
        "cat verify.out >> run.log",
        "if [ \"$code\" -ne 0 ]; then",
        "  printf 'failed\\tverify\\t%s\\n' \"$code\" > result",
        "  exit \"$code\"",
        "fi",
      ])
    }
    lines.append("printf 'succeeded\\n' > result")
    return lines.joined(separator: "\n")
  }

  private static func killCommand(deploymentID: UUID) -> String {
    """
    tmux kill-session -t '\(tmuxSession(for: deploymentID))' 2>/dev/null || true
    rm -rf "\(remoteDirectory(for: deploymentID))"
    """
  }

  /// Best-effort teardown of a detached run after the user cancels.
  private static func killRemoteRun(deploymentID: UUID, route: SSHConnectionRoute) async {
    guard let connection = try? await SSHConnection.connect(route: route) else { return }
    _ = try? await runRemote(connection, killCommand(deploymentID: deploymentID))
    await connection.close()
  }

  private struct RemotePoll {
    enum Outcome {
      case succeeded
      case failed(stage: RepoLaunchStage, exitCode: Int32)
    }

    let sessionAlive: Bool
    let stage: RepoLaunchStage?
    let outcome: Outcome?
    let size: Int
    let logChunk: String
  }

  private static func pollCommand(deploymentID: UUID, offset: Int) -> String {
    """
    dir="\(remoteDirectory(for: deploymentID))"
    session='\(tmuxSession(for: deploymentID))'
    if tmux has-session -t "$session" 2>/dev/null; then
      printf 'session\\talive\\n'
    else
      printf 'session\\tdead\\n'
    fi
    if [ -f "$dir/current" ]; then printf 'stage\\t%s\\n' "$(cat "$dir/current")"; fi
    if [ -f "$dir/result" ]; then printf 'result\\t%s\\n' "$(cat "$dir/result")"; fi
    size=$(wc -c < "$dir/run.log" 2>/dev/null | tr -d ' ')
    size=${size:-0}
    printf 'size\\t%s\\n' "$size"
    printf '\(remoteLogMarker)\\n'
    if [ \(offset) -lt 0 ]; then
      start=$(( size > \(remoteLogFetchLimit) ? size - \(remoteLogFetchLimit - 1) : 1 ))
    else
      start=$(( \(offset) + 1 ))
    fi
    if [ "$size" -gt 0 ] && [ "$start" -le "$size" ]; then
      tail -c +"$start" "$dir/run.log"
    fi
    """
  }

  /// Parses the runner's `result` file: `succeeded` or `failed\t<stage>\t<code>`.
  private static func parseOutcome(_ content: String) -> RemotePoll.Outcome? {
    let fields = content.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\t", omittingEmptySubsequences: false)
    guard let first = fields.first else { return nil }
    if first == "succeeded" { return .succeeded }
    if first == "failed" {
      let stage = fields.count > 1 ? RepoLaunchStage(rawValue: String(fields[1])) : nil
      let exitCode = fields.count > 2 ? Int32(fields[2]) ?? 1 : 1
      return .failed(stage: stage ?? .preflight, exitCode: exitCode)
    }
    return nil
  }

  private static func parsePoll(_ raw: String) throws -> RemotePoll {
    guard let markerRange = raw.range(of: remoteLogMarker + "\n") else {
      throw RepoLaunchError.connectionLost
    }
    let header = raw[raw.startIndex..<markerRange.lowerBound]
    let logChunk = String(raw[markerRange.upperBound...])
    var sessionAlive = false
    var stage: RepoLaunchStage?
    var outcome: RemotePoll.Outcome?
    var size = 0
    for line in header.split(separator: "\n", omittingEmptySubsequences: true) {
      let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
      guard let key = fields.first, fields.count > 1 else { continue }
      switch key {
      case "session":
        sessionAlive = fields[1] == "alive"
      case "stage":
        stage = RepoLaunchStage(rawValue: String(fields[1]))
      case "result":
        outcome = parseOutcome(String(fields[1]))
      case "size":
        size = Int(fields[1]) ?? 0
      default:
        continue
      }
    }
    return RemotePoll(
      sessionAlive: sessionAlive,
      stage: stage,
      outcome: outcome,
      size: size,
      logChunk: logChunk
    )
  }

  private static func pollRemote(
    deploymentID: UUID,
    route: SSHConnectionRoute,
    resume: Bool,
    onStage: @escaping StageHandler,
    onOutput: @escaping OutputHandler,
    onLogReset: OutputHandler?
  ) async throws -> RepoLaunchResult {
    let connection: SSHConnection
    do {
      connection = try await SSHConnection.connect(route: route)
    } catch {
      throw RepoLaunchError.connectionLost
    }
    var offset = resume ? -1 : 0
    var currentStage: RepoLaunchStage?
    do {
      while true {
        try Task.checkCancellation()
        let raw: String
        do {
          raw = try await runRemote(connection, pollCommand(deploymentID: deploymentID, offset: offset))
        } catch {
          throw RepoLaunchError.connectionLost
        }
        let poll = try parsePoll(raw)
        if !poll.logChunk.isEmpty {
          if offset < 0 {
            (onLogReset ?? onOutput)(poll.logChunk)
          } else {
            onOutput(poll.logChunk)
          }
        }
        offset = poll.size
        if let stage = poll.stage, stage != currentStage {
          currentStage = stage
          onStage(stage)
        }
        switch poll.outcome {
        case .succeeded:
          let verification: String
          do {
            verification = try await runRemote(
              connection,
              "cat \"\(remoteDirectory(for: deploymentID))/verify.out\" 2>/dev/null || true"
            )
          } catch {
            throw RepoLaunchError.connectionLost
          }
          _ = try? await runRemote(connection, killCommand(deploymentID: deploymentID))
          await connection.close()
          return try parseResult(verification, localBookmarkData: nil)
        case .failed(let stage, let exitCode):
          _ = try? await runRemote(connection, killCommand(deploymentID: deploymentID))
          throw RepoLaunchCommandError(stage: stage, exitCode: exitCode)
        case nil where !poll.sessionAlive:
          // The tmux session is gone without a result file: the host lost the
          // run (reboot, manual kill) rather than the app losing the socket.
          _ = try? await runRemote(connection, killCommand(deploymentID: deploymentID))
          throw RepoLaunchError.remoteRunInterrupted
        case nil:
          break
        }
        try await Task.sleep(nanoseconds: remotePollInterval)
      }
    } catch {
      await connection.close()
      if error is CancellationError {
        await killRemoteRun(deploymentID: deploymentID, route: route)
      }
      throw error
    }
  }

  #if os(macOS)
    // MARK: - Local deployment (tmux dispatch/poll)
    //
    // Local deployments use the same detached model as SSH ones: the runner
    // script runs inside a local tmux session, so quitting the app does not
    // kill the deployment, and the store re-attaches on the next launch.
    // Status files and run.log live under ~/.gitagent/repolaunch/<id>/.

    private static func localDirectoryURL(for deploymentID: UUID) -> URL {
      FileManager.default.homeDirectoryForCurrentUser
        .appending(
          path: ".gitagent/repolaunch/\(deploymentID.uuidString.lowercased())",
          directoryHint: .isDirectory
        )
    }

    /// Runs a command through the user's login shell and reports its exit
    /// status instead of throwing, so probes can branch on it.
    private static func runLocalShell(_ command: String) async -> (
      status: Int32, output: String
    ) {
      await withCheckedContinuation { continuation in
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
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

    /// Locates tmux through the login shell (Homebrew is not on the default
    /// PATH of a GUI app) and returns its absolute path.
    private static func resolveLocalTmux() async throws -> String {
      let result = await runLocalShell("command -v tmux")
      let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
      guard result.status == 0, !path.isEmpty else {
        throw RepoLaunchError.tmuxUnavailable
      }
      return path
    }

    private static func deployLocal(
      _ request: RepoLaunchRequest,
      deploymentID: UUID,
      onStage: @escaping StageHandler,
      onOutput: @escaping OutputHandler
    ) async throws -> RepoLaunchResult {
      guard let bookmarkData = request.localBookmarkData else {
        throw RepoLaunchError.localAccessDenied
      }
      var isStale = false
      let parentURL = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      guard parentURL.startAccessingSecurityScopedResource() else {
        throw RepoLaunchError.localAccessDenied
      }
      defer { parentURL.stopAccessingSecurityScopedResource() }

      let tmux = try await resolveLocalTmux()
      try Task.checkCancellation()
      try await dispatchLocal(request, deploymentID: deploymentID, tmuxPath: tmux)
      let verification = try await pollLocal(
        deploymentID: deploymentID,
        tmuxPath: tmux,
        resume: false,
        onStage: onStage,
        onOutput: onOutput,
        onLogReset: nil
      )

      let destinationURL = URL(fileURLWithPath: request.destinationPath)
        .resolvingSymlinksInPath()
        .standardizedFileURL
      let deployedBookmark = try destinationURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      return try parseResult(verification, localBookmarkData: deployedBookmark)
    }

    /// Re-attaches to a detached local run that survived an app restart.
    static func attachLocal(
      deploymentID: UUID,
      onStage: @escaping StageHandler,
      onOutput: @escaping OutputHandler,
      onLogReset: @escaping OutputHandler
    ) async throws -> RepoLaunchResult {
      let tmux = try await resolveLocalTmux()
      let verification = try await pollLocal(
        deploymentID: deploymentID,
        tmuxPath: tmux,
        resume: true,
        onStage: onStage,
        onOutput: onOutput,
        onLogReset: onLogReset
      )
      let result = try parseResult(verification, localBookmarkData: nil)
      let bookmark = try? URL(fileURLWithPath: result.canonicalPath)
        .bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
      return RepoLaunchResult(
        canonicalPath: result.canonicalPath,
        commit: result.commit,
        localBookmarkData: bookmark
      )
    }

    private static func dispatchLocal(
      _ request: RepoLaunchRequest,
      deploymentID: UUID,
      tmuxPath: String
    ) async throws {
      let dirURL = localDirectoryURL(for: deploymentID)
      let fileManager = FileManager.default
      try? fileManager.removeItem(at: dirURL)
      try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
      let stages = stageScripts(for: request)
      for (stage, script) in stages {
        try script.write(
          to: dirURL.appending(path: "\(stage.rawValue).sh"),
          atomically: true,
          encoding: .utf8
        )
      }
      try runnerScript(stages: stages.map(\.0)).write(
        to: dirURL.appending(path: "runner.sh"),
        atomically: true,
        encoding: .utf8
      )
      let session = tmuxSession(for: deploymentID)
      let status = await runLocalShell(
        """
        '\(tmuxPath)' kill-session -t '\(session)' 2>/dev/null
        '\(tmuxPath)' new-session -d -s '\(session)' \
          "bash '\(dirURL.path(percentEncoded: false))/runner.sh'"
        """
      ).status
      guard status == 0 else { throw RepoLaunchError.tmuxUnavailable }
    }

    private static func cleanupLocalRun(deploymentID: UUID, tmuxPath: String?) async {
      if let tmuxPath {
        _ = await runLocalShell(
          "'\(tmuxPath)' kill-session -t '\(tmuxSession(for: deploymentID))' 2>/dev/null"
        )
      }
      try? FileManager.default.removeItem(at: localDirectoryURL(for: deploymentID))
    }

    private static func readLocalPoll(
      dirURL: URL,
      tmuxPath: String,
      session: String,
      offset: Int
    ) async -> RemotePoll {
      let logURL = dirURL.appending(path: "run.log")
      let size =
        (try? FileManager.default.attributesOfItem(
          atPath: logURL.path(percentEncoded: false)
        )[.size] as? Int) ?? 0
      var chunk = ""
      let start = offset < 0 ? max(0, size - remoteLogFetchLimit) : min(offset, size)
      if size > start, let handle = try? FileHandle(forReadingFrom: logURL) {
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(start))
        if let data = try? handle.readToEnd() {
          chunk = String(decoding: data, as: UTF8.self)
        }
      }
      let alive =
        await runLocalShell("'\(tmuxPath)' has-session -t '\(session)' 2>/dev/null").status == 0
      let stageText = try? String(
        contentsOf: dirURL.appending(path: "current"),
        encoding: .utf8
      )
      .trimmingCharacters(in: .whitespacesAndNewlines)
      let resultText = try? String(
        contentsOf: dirURL.appending(path: "result"),
        encoding: .utf8
      )
      return RemotePoll(
        sessionAlive: alive,
        stage: stageText.flatMap { RepoLaunchStage(rawValue: $0) },
        outcome: resultText.flatMap(parseOutcome),
        size: size,
        logChunk: chunk
      )
    }

    private static func pollLocal(
      deploymentID: UUID,
      tmuxPath: String,
      resume: Bool,
      onStage: @escaping StageHandler,
      onOutput: @escaping OutputHandler,
      onLogReset: OutputHandler?
    ) async throws -> String {
      let dirURL = localDirectoryURL(for: deploymentID)
      let session = tmuxSession(for: deploymentID)
      var offset = resume ? -1 : 0
      var currentStage: RepoLaunchStage?
      do {
        while true {
          try Task.checkCancellation()
          let poll = await readLocalPoll(
            dirURL: dirURL,
            tmuxPath: tmuxPath,
            session: session,
            offset: offset
          )
          if !poll.logChunk.isEmpty {
            if offset < 0 {
              (onLogReset ?? onOutput)(poll.logChunk)
            } else {
              onOutput(poll.logChunk)
            }
          }
          offset = poll.size
          if let stage = poll.stage, stage != currentStage {
            currentStage = stage
            onStage(stage)
          }
          switch poll.outcome {
          case .succeeded:
            let verification =
              (try? String(
                contentsOf: dirURL.appending(path: "verify.out"),
                encoding: .utf8
              )) ?? ""
            await cleanupLocalRun(deploymentID: deploymentID, tmuxPath: nil)
            return verification
          case .failed(let stage, let exitCode):
            await cleanupLocalRun(deploymentID: deploymentID, tmuxPath: nil)
            throw RepoLaunchCommandError(stage: stage, exitCode: exitCode)
          case nil where !poll.sessionAlive:
            await cleanupLocalRun(deploymentID: deploymentID, tmuxPath: nil)
            throw RepoLaunchError.remoteRunInterrupted
          case nil:
            break
          }
          try await Task.sleep(nanoseconds: remotePollInterval)
        }
      } catch {
        if error is CancellationError {
          await cleanupLocalRun(deploymentID: deploymentID, tmuxPath: tmuxPath)
        }
        throw error
      }
    }
  #endif
}
