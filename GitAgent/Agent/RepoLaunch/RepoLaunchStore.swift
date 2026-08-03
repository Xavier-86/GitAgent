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

  init() {
    load()
    var recoveredInterruptedRun = false
    for index in records.indices where records[index].status == .running {
      records[index].status = .failed
      records[index].finishedAt = Date()
      records[index].errorMessage = L10n.resolveCurrent(.repoLaunchInterrupted)
      recoveredInterruptedRun = true
    }
    if recoveredInterruptedRun { save() }
  }

  func deploy(
    _ request: RepoLaunchRequest,
    host: SSHHostConfig?,
    password: String?
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
        host: host,
        password: password,
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
    update(id) { record in
      record.stage = stage
      if !record.log.isEmpty, !record.log.hasSuffix("\n") {
        record.log.append("\n")
      }
      record.log.append("\n[\(stage.rawValue.uppercased())]\n")
    }
  }

  private func append(_ output: String, to id: RepoLaunchRecord.ID) {
    update(id) { record in
      record.log.append(output)
      if record.log.count > maxLogCharacters {
        record.log = String(record.log.suffix(maxLogCharacters))
      }
    }
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
