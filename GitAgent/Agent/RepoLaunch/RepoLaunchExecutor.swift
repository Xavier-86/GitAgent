//
//  RepoLaunchExecutor.swift
//  GitAgent
//
//  Executes the same staged deployment plan locally or through SSH.
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

#if os(macOS)
  /// Serializes output arriving from FileHandle and process callbacks.
  nonisolated private final class RepoLaunchOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
      lock.lock()
      defer { lock.unlock() }
      data.append(chunk)
    }

    func string() -> String {
      lock.lock()
      defer { lock.unlock() }
      return String(decoding: data, as: UTF8.self)
    }
  }
#endif

@MainActor
enum RepoLaunchExecutor {
  typealias StageHandler = (RepoLaunchStage) -> Void
  typealias OutputHandler = (String) -> Void

  static func deploy(
    _ request: RepoLaunchRequest,
    host: SSHHostConfig?,
    password: String?,
    onStage: @escaping StageHandler,
    onOutput: @escaping OutputHandler
  ) async throws -> RepoLaunchResult {
    try validate(request)
    if request.isLocal {
      #if os(macOS)
        return try await deployLocal(request, onStage: onStage, onOutput: onOutput)
      #else
        throw RepoLaunchError.localDeploymentUnavailable
      #endif
    }

    guard let host, host.id == request.hostID else {
      throw RepoLaunchError.sshHostUnavailable
    }
    guard let password, !password.isEmpty else {
      throw RepoLaunchError.sshPasswordMissing
    }
    return try await deployRemote(
      request,
      host: host,
      password: password,
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
        GIT_TERMINAL_PROMPT=0 git -C "$destination" fetch --prune --tags origin
      else
        GIT_TERMINAL_PROMPT=0 git clone --recurse-submodules -- "$repository_url" "$destination"
      fi

      if [ -n "$reference" ]; then
        if commit=$(git -C "$destination" rev-parse --verify "$reference^{commit}" 2>/dev/null); then
          :
        elif commit=$(git -C "$destination" rev-parse --verify "origin/$reference^{commit}" 2>/dev/null); then
          :
        else
          GIT_TERMINAL_PROMPT=0 git -C "$destination" fetch origin "$reference"
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
      GIT_TERMINAL_PROMPT=0 git -C "$destination" submodule update --init --recursive
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

  private static func deployRemote(
    _ request: RepoLaunchRequest,
    host: SSHHostConfig,
    password: String,
    onStage: @escaping StageHandler,
    onOutput: @escaping OutputHandler
  ) async throws -> RepoLaunchResult {
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
      var verificationOutput = ""
      for (stage, script) in stageScripts(for: request) {
        try Task.checkCancellation()
        onStage(stage)
        let stream = try await client.executeCommandStream(script, inShell: false)
        for try await chunk in stream {
          try Task.checkCancellation()
          let text: String
          switch chunk {
          case .stdout(let buffer), .stderr(let buffer):
            text = String(decoding: buffer.readableBytesView, as: UTF8.self)
          }
          onOutput(text)
          if stage == .verify { verificationOutput.append(text) }
        }
      }
      try? await client.close()
      return try parseResult(verificationOutput, localBookmarkData: nil)
    } catch {
      try? await client.close()
      throw error
    }
  }

  #if os(macOS)
    private static func deployLocal(
      _ request: RepoLaunchRequest,
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

      var verificationOutput = ""
      for (stage, script) in stageScripts(for: request) {
        try Task.checkCancellation()
        onStage(stage)
        let output = try await runLocal(script, stage: stage, onOutput: onOutput)
        if stage == .verify { verificationOutput = output }
      }

      let destinationURL = URL(fileURLWithPath: request.destinationPath)
        .resolvingSymlinksInPath()
        .standardizedFileURL
      let deployedBookmark = try destinationURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      return try parseResult(verificationOutput, localBookmarkData: deployedBookmark)
    }

    private static func runLocal(
      _ script: String,
      stage: RepoLaunchStage,
      onOutput: @escaping OutputHandler
    ) async throws -> String {
      let process = Process()
      let pipe = Pipe()
      let output = RepoLaunchOutputBuffer()

      process.executableURL = URL(fileURLWithPath: "/bin/zsh")
      process.arguments = ["-lc", script]
      process.standardOutput = pipe
      process.standardError = pipe

      pipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty else { return }
        output.append(data)
        let text = String(decoding: data, as: UTF8.self)
        Task { @MainActor in onOutput(text) }
      }

      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          process.terminationHandler = { finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            let tail = pipe.fileHandleForReading.readDataToEndOfFile()
            if !tail.isEmpty {
              output.append(tail)
              let text = String(decoding: tail, as: UTF8.self)
              Task { @MainActor in onOutput(text) }
            }
            if finished.terminationStatus == 0 {
              continuation.resume()
            } else {
              continuation.resume(
                throwing: RepoLaunchCommandError(
                  stage: stage,
                  exitCode: finished.terminationStatus
                )
              )
            }
          }
          do {
            try process.run()
          } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            continuation.resume(throwing: error)
          }
        }
      } onCancel: {
        if process.isRunning { process.terminate() }
      }
      try Task.checkCancellation()
      return output.string()
    }
  #endif
}
