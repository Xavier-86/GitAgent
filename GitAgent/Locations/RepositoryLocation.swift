//
//  RepositoryLocation.swift
//  GitAgent
//
//  Persisted links between GitHub repositories and local or remote working trees.
//

import Foundation
import Observation

enum RepositoryLocationVerification: String, Codable {
    case unchecked
    case connected
    case failed
}

struct RepositoryLocation: Codable, Identifiable, Hashable {
    static let currentVerificationVersion = 2

    let id: UUID
    let repositoryID: Int
    var repositoryFullName: String
    let hostID: UUID?
    var path: String
    var bookmarkData: Data?
    var verification: RepositoryLocationVerification
    var matchedRemoteName: String?
    var lastError: String?
    var lastVerifiedAt: Date?
    var verificationVersion: Int?

    var isLocal: Bool {
        hostID == nil
    }

    var isConnected: Bool {
        verification == .connected &&
        verificationVersion == Self.currentVerificationVersion
    }

    /// UI status is the most recent completed verification result. An older
    /// verification version still remains green while a background refresh
    /// determines whether the location can be used with the current rules.
    var lastConnectionWasSuccessful: Bool {
        verification == .connected
    }

    init(repository: Repo, hostID: UUID?, path: String, bookmarkData: Data? = nil) {
        id = UUID()
        repositoryID = repository.id
        repositoryFullName = repository.fullName
        self.hostID = hostID
        self.path = path
        self.bookmarkData = bookmarkData
        verification = .unchecked
    }
}

@Observable
final class RepositoryLocationStore {
    private(set) var locations: [RepositoryLocation] = []

    init() {
        load()
    }

    func locations(for repositoryID: Int) -> [RepositoryLocation] {
        locations
            .filter { $0.repositoryID == repositoryID }
            .sorted {
                ($0.lastVerifiedAt ?? .distantPast) > ($1.lastVerifiedAt ?? .distantPast)
            }
    }

    func location(id: UUID) -> RepositoryLocation? {
        locations.first { $0.id == id }
    }

    func hasConnectedLocation(for repositoryID: Int) -> Bool {
        locations.contains {
            $0.repositoryID == repositoryID && $0.lastConnectionWasSuccessful
        }
    }

    @discardableResult
    func add(repository: Repo, hostID: UUID, path: String) -> RepositoryLocation.ID {
        let location = RepositoryLocation(
            repository: repository,
            hostID: hostID,
            path: path.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        locations.append(location)
        save()
        return location.id
    }

    #if os(macOS)
    @discardableResult
    func addLocal(repository: Repo, path: String, bookmarkData: Data) -> RepositoryLocation.ID {
        let location = RepositoryLocation(
            repository: repository,
            hostID: nil,
            path: path,
            bookmarkData: bookmarkData
        )
        locations.append(location)
        save()
        return location.id
    }
    #endif

    func markConnected(_ id: RepositoryLocation.ID,
                       canonicalPath: String,
                       remoteName: String,
                       bookmarkData: Data? = nil) {
        update(id) { location in
            location.path = canonicalPath
            if let bookmarkData {
                location.bookmarkData = bookmarkData
            }
            location.verification = .connected
            location.verificationVersion = RepositoryLocation.currentVerificationVersion
            location.matchedRemoteName = remoteName
            location.lastError = nil
            location.lastVerifiedAt = Date()
        }

        // Adding the same checkout once through "~" and once through its
        // canonical path should still result in one repository location.
        guard let connected = location(id: id) else { return }
        locations.removeAll {
            $0.id != id &&
            $0.repositoryID == connected.repositoryID &&
            $0.hostID == connected.hostID &&
            $0.path == connected.path
        }
        save()
    }

    func markFailed(_ id: RepositoryLocation.ID, error: String) {
        update(id) { location in
            location.verification = .failed
            location.verificationVersion = RepositoryLocation.currentVerificationVersion
            location.matchedRemoteName = nil
            location.lastError = error
            location.lastVerifiedAt = Date()
        }
    }

    /// Records a temporary transport/API error without replacing the last
    /// completed verification result. A previously connected location stays
    /// green; a never-verified location remains unchecked/red.
    func markTemporarilyUnavailable(_ id: RepositoryLocation.ID, error: String) {
        update(id) { location in
            location.lastError = error
        }
    }

    func delete(_ id: RepositoryLocation.ID) {
        locations.removeAll { $0.id == id }
        save()
    }

    private func update(_ id: RepositoryLocation.ID,
                        _ transform: (inout RepositoryLocation) -> Void) {
        guard let index = locations.firstIndex(where: { $0.id == id }) else { return }
        transform(&locations[index])
        save()
    }

    private var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "GitAgent", directoryHint: .isDirectory)
            .appending(path: "repository-locations.json")
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(locations).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("GitAgent: failed to save repository locations \(error)")
        }
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([RepositoryLocation].self, from: data)
        else { return }
        locations = decoded

        // Older builds persisted `unchecked` as soon as a refresh began. If
        // that task was then cancelled, the previous successful result was
        // lost even though its matched remote and timestamp remained. Repair
        // that interrupted-check state once on load.
        var repairedInterruptedCheck = false
        for index in locations.indices
        where locations[index].verification == .unchecked
            && locations[index].matchedRemoteName != nil
            && locations[index].lastVerifiedAt != nil
            && locations[index].lastError == nil
        {
            locations[index].verification = .connected
            locations[index].verificationVersion = RepositoryLocation.currentVerificationVersion
            repairedInterruptedCheck = true
        }
        if repairedInterruptedCheck { save() }
    }
}
