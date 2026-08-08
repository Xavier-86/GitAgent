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
    var lastOutputSignature = 0
    var lastDone = 0
    /// Highest hook completion count already handed to LocalNotifier.
    var lastNotifiedDone = 0
    var completionHookEnabled = false
    var lastOutputAt = Date.distantPast
    var sawOutput = false
    /// kimi only: an idle completion was already signalled for the current
    /// quiet period (reset when output advances or the user views the
    /// session), so notifications fire once per state transition.
    var notifiedIdle = false
    var probing = false
    /// Loaded sessions establish their existing counters before new
    /// completions are eligible to notify.
    var hasBaseline = false
  }

  private let probeInterval: UInt64 = 5_000_000_000
  private let idleThreshold: TimeInterval = 10
  private var pollTask: Task<Void, Never>?
  private var completionWatchTasks: [CoderSessionRecord.ID: Task<Void, Never>] = [:]
  /// Probing resolves routes autonomously, so the store keeps the app's
  /// host store (set once at launch).
  private var hosts: SSHHostStore?
  private var settings: AppSettings?

  init() {
    load()
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        self?.probeAll()
        try? await Task.sleep(nanoseconds: self?.probeInterval ?? 5_000_000_000)
      }
    }
  }

  /// Provides the SSH hosts used to resolve probe routes. Called once at
  /// app launch.
  func attach(hosts: SSHHostStore, settings: AppSettings) {
    self.hosts = hosts
    self.settings = settings
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
        runtime.hasBaseline = true
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
    completionWatchTasks[record.id]?.cancel()
    completionWatchTasks[record.id] = nil
    var runtime = status[record.id] ?? SessionRuntime()
    runtime.alive = false
    runtime.turnFinished = false
    status[record.id] = runtime
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
    completionWatchTasks[record.id]?.cancel()
    completionWatchTasks[record.id] = nil
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
      completionWatchTasks[record.id]?.cancel()
      completionWatchTasks[record.id] = nil
      runtime.alive = false
      runtime.turnFinished = false
      status[record.id] = runtime
      return
    }
    runtime.alive = true
    if !runtime.hasBaseline {
      runtime.lastActivity = probe.activity
      runtime.lastOutputSignature = probe.outputSignature
      runtime.lastDone = probe.done
      runtime.lastNotifiedDone = probe.done
      runtime.completionHookEnabled = probe.completionHookEnabled
      runtime.hasBaseline = true
      status[record.id] = runtime
      startCompletionWatchIfNeeded(for: record)
      return
    }
    if probe.activity > runtime.lastActivity ||
      probe.outputSignature != runtime.lastOutputSignature
    {
      runtime.lastActivity = probe.activity
      runtime.lastOutputSignature = probe.outputSignature
      runtime.lastOutputAt = Date()
      runtime.sawOutput = true
      runtime.turnFinished = false
      runtime.notifiedIdle = false
    }
    runtime.completionHookEnabled = probe.completionHookEnabled
    // Supported CLIs append an exact completion marker from their hook.
    if probe.done > runtime.lastDone {
      runtime.lastDone = probe.done
      runtime.turnFinished = true
      if probe.done > runtime.lastNotifiedDone {
        runtime.lastNotifiedDone = probe.done
        notifyTurnFinished(record)
      }
    }
    // Older Kimi versions cannot load Stop hooks. Only those sessions use
    // output idleness as a compatibility fallback.
    if record.tool == .kimi,
      !runtime.completionHookEnabled,
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
    startCompletionWatchIfNeeded(for: record)
  }

  /// Exact CLI hooks are watched on a lightweight long-lived channel so
  /// notification latency is not tied to the five-second full probe.
  private func startCompletionWatchIfNeeded(for record: CoderSessionRecord) {
    guard completionWatchTasks[record.id] == nil,
      let runtime = status[record.id],
      runtime.alive,
      runtime.completionHookEnabled
    else { return }
    let baseline = runtime.lastDone
    completionWatchTasks[record.id] = Task { [weak self] in
      guard let self else { return }
      await self.watchCompletions(for: record, startingAfter: baseline)
    }
  }

  private func watchCompletions(for record: CoderSessionRecord, startingAfter baseline: Int) async {
    var observedDone = baseline
    defer { completionWatchTasks[record.id] = nil }

    while !Task.isCancelled {
      guard records.contains(where: { $0.id == record.id }),
        let runtime = status[record.id],
        runtime.alive,
        runtime.completionHookEnabled,
        let hosts
      else { return }
      observedDone = max(observedDone, runtime.lastDone)

      do {
        let result = try await CoderExecutor.waitForCompletion(
          record: record,
          afterDone: observedDone,
          route: try resolveRoute(for: record, hosts: hosts)
        )
        switch result {
        case .completed(let count):
          observedDone = max(observedDone, count)
          guard var current = status[record.id] else { return }
          // The full probe owns lastDone, while lastNotifiedDone arbitrates
          // notification delivery between both detection paths.
          if count > current.lastNotifiedDone {
            current.lastNotifiedDone = count
            current.turnFinished = true
            status[record.id] = current
            notifyTurnFinished(record)
          }
        case .timedOut:
          continue
        case .sessionEnded:
          if var current = status[record.id] {
            current.alive = false
            current.turnFinished = false
            status[record.id] = current
          }
          return
        case .hookUnavailable:
          if var current = status[record.id] {
            current.completionHookEnabled = false
            status[record.id] = current
          }
          return
        }
      } catch {
        guard !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
  }

  private func notifyTurnFinished(_ record: CoderSessionRecord) {
    guard settings?.coderCompletionNotifications ?? true else { return }
    let title = "\(record.tool.displayName) · \(record.repositoryFullName)"
    LocalNotifier.post(
      title: title,
      body: L10n.resolveCurrent(.coderTurnFinished),
      coderSessionID: record.id
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
