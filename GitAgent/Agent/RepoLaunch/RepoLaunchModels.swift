//
//  RepoLaunchModels.swift
//  GitAgent
//
//  Swift-native repository deployment models inspired by RepoLaunch.
//

import Foundation

enum RepoLaunchStage: String, Codable {
  case preflight
  case checkout
  case setup
  case build
  case test
  case verify
}

enum RepoLaunchStatus: String, Codable {
  case running
  case succeeded
  case failed
  case cancelled
}

extension RepoLaunchStage {
  var localizationKey: L10n.Key {
    switch self {
    case .preflight: return .stagePreflight
    case .checkout: return .stageCheckout
    case .setup: return .stageSetup
    case .build: return .stageBuild
    case .test: return .stageTest
    case .verify: return .stageVerify
    }
  }
}

extension RepoLaunchStatus {
  var localizationKey: L10n.Key {
    switch self {
    case .running: return .repoLaunchRunning
    case .succeeded: return .repoLaunchSucceeded
    case .failed: return .repoLaunchFailed
    case .cancelled: return .repoLaunchCancelled
    }
  }
}

struct RepoLaunchRequest {
  let repositoryURL: String
  let repositoryFullName: String?
  let reference: String
  let destinationPath: String
  let hostID: SSHHostConfig.ID?
  let localBookmarkData: Data?
  let setupCommands: String
  let buildCommands: String
  let testCommands: String

  var isLocal: Bool { hostID == nil }
}

struct RepoLaunchResult {
  let canonicalPath: String
  let commit: String
  let localBookmarkData: Data?
}

struct RepoLaunchRecord: Codable, Identifiable {
  let id: UUID
  let repositoryURL: String
  let repositoryFullName: String?
  let destinationPath: String
  let hostID: SSHHostConfig.ID?
  let reference: String
  let startedAt: Date
  var finishedAt: Date?
  var stage: RepoLaunchStage
  var status: RepoLaunchStatus
  var resolvedCommit: String?
  var log: String
  var errorMessage: String?

  var displayName: String {
    if let repositoryFullName, !repositoryFullName.isEmpty {
      return repositoryFullName
    }
    var name =
      repositoryURL
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      .split(separator: "/")
      .last
      .map(String.init) ?? repositoryURL
    if name.hasSuffix(".git") { name.removeLast(4) }
    return name.isEmpty ? repositoryURL : name
  }
}

enum RepoLaunchError: LocalizedError {
  case invalidRepositoryURL
  case invalidDestination
  case localDeploymentUnavailable
  case localAccessDenied
  case sshHostUnavailable
  case sshPasswordMissing
  case invalidVerificationResponse

  var errorDescription: String? {
    switch self {
    case .invalidRepositoryURL:
      return L10n.resolveCurrent(.repoLaunchInvalidURL)
    case .invalidDestination:
      return L10n.resolveCurrent(.repoLaunchInvalidDestination)
    case .localDeploymentUnavailable:
      return L10n.resolveCurrent(.repoLaunchLocalUnavailable)
    case .localAccessDenied:
      return L10n.resolveCurrent(.localRepositoryAccessDenied)
    case .sshHostUnavailable:
      return L10n.resolveCurrent(.computerUnavailable)
    case .sshPasswordMissing:
      return L10n.resolveCurrent(.sshPasswordMissing)
    case .invalidVerificationResponse:
      return L10n.resolveCurrent(.repoLaunchInvalidResult)
    }
  }
}
