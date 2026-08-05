//
//  CoderStore.swift
//  GitAgent
//
//  Persists Coder session records and tracks their runtime state (liveness,
//  turn-finished marker) by probing the target's tmux every few seconds
//  while the app runs. Sessions themselves are detached on the target, so
//  no re-attach lifecycle is needed — a probe simply sees them again.
//

import Foundation
import Observation

@MainActor
@Observable
final class CoderStore {
  private(set) var records: [CoderSessionRecord] = []
  /// Probed runtime state, keyed by record id. Never persisted.
  private(set) var status: [CoderSessionRecord.ID: SessionRuntime] = [:]
  /// Set when session creation fails; presented by the view.
  var creationError: String?

  struct SessionRuntime {
    var alive = false
    var turnFinished = false
    var lastActivity = 0
    var lastDone = 0
    var lastOutputAt = Date.distantPast
    var sawOutput = false
    /// kimi only: an idle completion was already signalled for the current
    /// quiet period (reset when output advances or the user views the
    /// session), so notifications fire once per state transition.
    var notifiedIdle = false
    var probing = false
  }

  private let probeInterval: UInt64 = 5_000_000_000
  private let idleThreshold: TimeInterval = 10
  private var pollTask: Task<Void, Never>?
  /// Probing resolves routes autonomously, so the store keeps the app's
  /// host store (set once at launch).
  private var hosts: SSHHostStore?

  init() {
    load()
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.probeAll()
        try? await Task.sleep(nanoseconds: self?.probeInterval ?? 5_000_000_000)
      }
    }
  }

  /// Provides the SSH hosts used to resolve probe routes. Called once at
  /// app launch.
  func attach(hosts: SSHHostStore) {
    self.hosts = hosts
  }

  func record(_ id: CoderSessionRecord.ID) -> CoderSessionRecord? {
    records.first { $0.id == id }
  }

  func runtime(_ id: CoderSessionRecord.ID) -> SessionRuntime {
    status[id] ?? SessionRuntime()
  }

  // MARK: - Session lifecycle

  func createSession(
    tool: CoderTool,
    location: RepositoryLocation,
    initialPrompt: String,
    hosts: SSHHostStore
  ) {
    let prompt = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let record = CoderSessionRecord(
      id: UUID(),
      tool: tool,
      repositoryFullName: location.repositoryFullName,
      locationID: location.id,
      hostID: location.hostID,
      path: location.path,
      initialPrompt: prompt.isEmpty ? nil : prompt,
      createdAt: Date()
    )
    records.insert(record, at: 0)
    status[record.id] = SessionRuntime()
    save()
    Task { [weak self] in
      guard let self else { return }
      do {
        let route = try resolveRoute(for: record, hosts: hosts)
        try await CoderExecutor.createSession(record: record, route: route)
        var runtime = status[record.id] ?? SessionRuntime()
        runtime.alive = true
        status[record.id] = runtime
      } catch {
        records.removeAll { $0.id == record.id }
        status[record.id] = nil
        save()
        creationError = error.localizedDescription
      }
    }
  }

  func kill(record: CoderSessionRecord, hosts: SSHHostStore) {
    Task { [weak self] in
      await CoderExecutor.killSession(
        record: record,
        route: try? self?.resolveRoute(for: record, hosts: hosts)
      )
      guard let self else { return }
      var runtime = status[record.id] ?? SessionRuntime()
      runtime.alive = false
      runtime.turnFinished = false
      status[record.id] = runtime
    }
  }

  func delete(record: CoderSessionRecord, hosts: SSHHostStore) {
    Task { [weak self] in
      await CoderExecutor.killSession(
        record: record,
        route: try? self?.resolveRoute(for: record, hosts: hosts)
      )
    }
    records.removeAll { $0.id == record.id }
    status[record.id] = nil
    save()
  }

  /// The user is looking at the session: drop the completion marker without
  /// re-arming the idle notification until new output arrives.
  func clearTurnFinished(_ recordID: CoderSessionRecord.ID) {
    guard var runtime = status[recordID] else { return }
    runtime.turnFinished = false
    runtime.notifiedIdle = true
    status[recordID] = runtime
  }

  // MARK: - Probing

  private func probeAll() {
    guard let hosts else { return }
    for record in records {
      let runtime = status[record.id] ?? SessionRuntime()
      guard !runtime.probing else { continue }
      var updated = runtime
      updated.probing = true
      status[record.id] = updated
      Task { [weak self] in
        guard let self else { return }
        // Route and transport failures are connection problems: keep the
        // previous state and retry on the next cycle.
        let probe = try? await CoderExecutor.probe(
          record: record,
          route: try? self.resolveRoute(for: record, hosts: hosts)
        )
        if var current = self.status[record.id] {
          current.probing = false
          self.status[record.id] = current
        }
        guard let probe else { return }
        self.apply(probe, to: record)
      }
    }
  }

  private func apply(_ probe: CoderProbe, to record: CoderSessionRecord) {
    var runtime = status[record.id] ?? SessionRuntime()
    guard probe.alive else {
      // Externally killed or the CLI exited on its own.
      runtime.alive = false
      runtime.turnFinished = false
      status[record.id] = runtime
      return
    }
    runtime.alive = true
    if probe.activity > runtime.lastActivity {
      runtime.lastActivity = probe.activity
      runtime.lastOutputAt = Date()
      runtime.sawOutput = true
      runtime.turnFinished = false
      runtime.notifiedIdle = false
    }
    // claude/codex: the completion hooks appended to turn-done.
    if probe.done > runtime.lastDone {
      runtime.lastDone = probe.done
      if !runtime.turnFinished {
        runtime.turnFinished = true
        notifyTurnFinished(record)
      }
    }
    // kimi has no per-invocation hooks: output that advanced and then went
    // quiet for the idle threshold approximates a finished turn.
    if record.tool == .kimi,
      runtime.sawOutput,
      !runtime.notifiedIdle,
      !runtime.turnFinished,
      Date().timeIntervalSince(runtime.lastOutputAt) >= idleThreshold
    {
      runtime.turnFinished = true
      runtime.notifiedIdle = true
      notifyTurnFinished(record)
    }
    status[record.id] = runtime
  }

  private func notifyTurnFinished(_ record: CoderSessionRecord) {
    LocalNotifier.post(
      title: "\(record.repositoryFullName) · \(record.tool.displayName)",
      body: L10n.resolveCurrent(.coderTurnFinished)
    )
  }

  private func resolveRoute(
    for record: CoderSessionRecord,
    hosts: SSHHostStore
  ) throws -> SSHConnectionRoute? {
    guard let hostID = record.hostID else { return nil }
    guard let host = hosts.hosts.first(where: { $0.id == hostID }) else {
      throw CoderError.sshHostUnavailable
    }
    return try hosts.connectionRoute(for: host)
  }

  // MARK: - Persistence (Application Support, non-sensitive)

  private var fileURL: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appending(path: "GitAgent", directoryHint: .isDirectory)
      .appending(path: "coder-sessions.json")
  }

  private func save() {
    guard let fileURL else { return }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let retained = Array(records.prefix(50))
      try JSONEncoder().encode(retained).write(to: fileURL, options: .atomic)
    } catch {
      NSLog("GitAgent: failed to save coder sessions \(error)")
    }
  }

  private func load() {
    guard let fileURL,
      let data = try? Data(contentsOf: fileURL),
      let decoded = try? JSONDecoder().decode([CoderSessionRecord].self, from: data)
    else { return }
    records = decoded
  }
}
