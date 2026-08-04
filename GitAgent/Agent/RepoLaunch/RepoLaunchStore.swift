//
//  RepoLaunchStore.swift
//  GitAgent
//
//  Persists deployment history and owns the active deployment lifecycle.
//

import Foundation
import Observation

@MainActor
@Observable
final class RepoLaunchStore {
  private(set) var records: [RepoLaunchRecord] = []
  private(set) var activeRecordID: RepoLaunchRecord.ID?

  private let maxLogCharacters = 250_000
  private let maxResumeAttempts = 12
  private var resumeTasks: [RepoLaunchRecord.ID: Task<Void, Never>] = [:]
  private var resumeAttempts: [RepoLaunchRecord.ID: Int] = [:]

  init() {
    load()
    // Running records (local and remote alike) are detached tmux runs on the
    // target machine and outlive the app; resumeInterruptedDeployments(hosts:)
    // re-attaches to them after launch.
  }

  /// Re-attaches to deployments that were still running when the app last
  /// exited. Their tmux sessions kept going on the target machine meanwhile.
  func resumeInterruptedDeployments(hosts: SSHHostStore) {
    for record in records where record.status == .running {
      guard resumeTasks[record.id] == nil else { continue }
      guard let hostID = record.hostID else {
        scheduleResume(recordID: record.id, route: nil, immediate: true)
        continue
      }
      guard let host = hosts.hosts.first(where: { $0.id == hostID }) else {
        finish(
          record.id,
          status: .failed,
          result: nil,
          error: L10n.resolveCurrent(.repoLaunchInterrupted)
        )
        continue
      }
      do {
        let route = try hosts.connectionRoute(for: host)
        scheduleResume(recordID: record.id, route: route, immediate: true)
      } catch {
        finish(record.id, status: .failed, result: nil, error: error.localizedDescription)
      }
    }
  }

  private func scheduleResume(
    recordID: RepoLaunchRecord.ID,
    route: SSHConnectionRoute?,
    immediate: Bool = false
  ) {
    resumeTasks[recordID]?.cancel()
    activeRecordID = recordID
    resumeTasks[recordID] = Task { [weak self] in
      if !immediate {
        try? await Task.sleep(nanoseconds: 10_000_000_000)
      }
      guard !Task.isCancelled, let self else { return }
      await self.resume(recordID: recordID, route: route)
    }
  }

  private func resume(recordID: RepoLaunchRecord.ID, route: SSHConnectionRoute?) async {
    do {
      let result: RepoLaunchResult
      if let route {
        result = try await RepoLaunchExecutor.attachRemote(
          deploymentID: recordID,
          route: route,
          onStage: { [weak self] stage in
            self?.setStage(stage, for: recordID)
          },
          onOutput: { [weak self] output in
            self?.append(output, to: recordID)
          },
          onLogReset: { [weak self] log in
            self?.replaceLog(log, for: recordID)
          }
        )
      } else {
        #if os(macOS)
          result = try await RepoLaunchExecutor.attachLocal(
            deploymentID: recordID,
            onStage: { [weak self] stage in
              self?.setStage(stage, for: recordID)
            },
            onOutput: { [weak self] output in
              self?.append(output, to: recordID)
            },
            onLogReset: { [weak self] log in
              self?.replaceLog(log, for: recordID)
            }
          )
        #else
          throw RepoLaunchError.localDeploymentUnavailable
        #endif
      }
      resumeAttempts[recordID] = nil
      finish(recordID, status: .succeeded, result: result, error: nil)
    } catch is CancellationError {
      finish(
        recordID,
        status: .cancelled,
        result: nil,
        error: L10n.resolveCurrent(.repoLaunchCancelled)
      )
    } catch RepoLaunchError.connectionLost {
      // The detached tmux run keeps going on the host; retry with backoff.
      let attempts = (resumeAttempts[recordID] ?? 0) + 1
      resumeAttempts[recordID] = attempts
      if attempts <= maxResumeAttempts {
        scheduleResume(recordID: recordID, route: route)
      } else {
        finish(
          recordID,
          status: .failed,
          result: nil,
          error: L10n.resolveCurrent(.repoLaunchConnectionLost)
        )
      }
    } catch {
      finish(recordID, status: .failed, result: nil, error: error.localizedDescription)
    }
  }

  func deploy(
    _ request: RepoLaunchRequest,
    route: SSHConnectionRoute?
  ) async -> RepoLaunchResult? {
    guard activeRecordID == nil else { return nil }

    let record = RepoLaunchRecord(
      id: UUID(),
      repositoryURL: request.repositoryURL,
      repositoryFullName: request.repositoryFullName,
      destinationPath: request.destinationPath,
      hostID: request.hostID,
      reference: request.reference,
      startedAt: Date(),
      stage: .preflight,
      status: .running,
      log: ""
    )
    records.insert(record, at: 0)
    activeRecordID = record.id
    save()

    do {
      let result = try await RepoLaunchExecutor.deploy(
        request,
        route: route,
        deploymentID: record.id,
        onStage: { [weak self] stage in
          self?.setStage(stage, for: record.id)
        },
        onOutput: { [weak self] output in
          self?.append(output, to: record.id)
        }
      )
      finish(record.id, status: .succeeded, result: result, error: nil)
      return result
    } catch is CancellationError {
      finish(
        record.id,
        status: .cancelled,
        result: nil,
        error: L10n.resolveCurrent(.repoLaunchCancelled)
      )
      return nil
    } catch RepoLaunchError.connectionLost {
      // The detached tmux run continues on the host; re-attach with backoff.
      resumeAttempts[record.id] = 1
      if let route { scheduleResume(recordID: record.id, route: route) }
      return nil
    } catch {
      finish(record.id, status: .failed, result: nil, error: error.localizedDescription)
      return nil
    }
  }

  func delete(_ id: RepoLaunchRecord.ID) {
    guard activeRecordID != id else { return }
    records.removeAll { $0.id == id }
    save()
  }

  private func setStage(_ stage: RepoLaunchStage, for id: RepoLaunchRecord.ID) {
    // Stage headers come from the runner script's run.log on both local and
    // remote deployments; this only tracks the current stage for the UI.
    update(id) { record in
      record.stage = stage
    }
  }

  private func append(_ output: String, to id: RepoLaunchRecord.ID) {
    update(id) { record in
      record.log.append(Self.normalizingCarriageReturns(output))
      if record.log.count > maxLogCharacters {
        record.log = String(record.log.suffix(maxLogCharacters))
      }
    }
  }

  private func replaceLog(_ log: String, for id: RepoLaunchRecord.ID) {
    update(id) { record in
      let normalized = Self.normalizingCarriageReturns(log)
      record.log =
        normalized.count > maxLogCharacters
        ? String(normalized.suffix(maxLogCharacters)) : normalized
    }
  }

  /// `git --progress` updates a single line with carriage returns; turn each
  /// update into its own log line so progress stays readable in the log view.
  private static func normalizingCarriageReturns(_ text: String) -> String {
    text.replacingOccurrences(of: "\r", with: "\n")
  }

  private func finish(
    _ id: RepoLaunchRecord.ID,
    status: RepoLaunchStatus,
    result: RepoLaunchResult?,
    error: String?
  ) {
    guard let index = records.firstIndex(where: { $0.id == id }) else { return }
    records[index].status = status
    records[index].finishedAt = Date()
    records[index].resolvedCommit = result?.commit
    records[index].errorMessage = error
    if let error {
      if !records[index].log.hasSuffix("\n") { records[index].log.append("\n") }
      records[index].log.append("\n\(error)\n")
    }
    activeRecordID = nil
    save()
  }

  private func update(
    _ id: RepoLaunchRecord.ID,
    _ transform: (inout RepoLaunchRecord) -> Void
  ) {
    guard let index = records.firstIndex(where: { $0.id == id }) else { return }
    transform(&records[index])
    save()
  }

  private var fileURL: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appending(path: "GitAgent", directoryHint: .isDirectory)
      .appending(path: "repository-deployments.json")
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
      NSLog("GitAgent: failed to save repository deployments \(error)")
    }
  }

  private func load() {
    guard let fileURL,
      let data = try? Data(contentsOf: fileURL),
      let decoded = try? JSONDecoder().decode([RepoLaunchRecord].self, from: data)
    else { return }
    records = decoded
  }
}
