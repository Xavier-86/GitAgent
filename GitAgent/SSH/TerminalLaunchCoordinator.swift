//
//  TerminalLaunchCoordinator.swift
//  GitAgent
//
//  Routes repository locations to the shared SSH terminal screen.
//

import Foundation
import Observation

enum TerminalLaunchTarget: Equatable {
    case ssh(SSHHostConfig.ID)
    case local(bookmarkData: Data?)
}

struct TerminalLaunchRequest: Identifiable, Equatable {
    let id = UUID()
    let target: TerminalLaunchTarget
    let directory: String
}

@Observable
final class TerminalLaunchCoordinator {
    private(set) var request: TerminalLaunchRequest?

    func open(hostID: SSHHostConfig.ID?, directory: String, bookmarkData: Data? = nil) {
        let target: TerminalLaunchTarget
        if let hostID {
            target = .ssh(hostID)
        } else {
            target = .local(bookmarkData: bookmarkData)
        }
        request = TerminalLaunchRequest(
            target: target,
            directory: directory
        )
    }

    @discardableResult
    func open(_ location: RepositoryLocation) -> Bool {
        guard location.isConnected else { return false }
        open(
            hostID: location.hostID,
            directory: location.path,
            bookmarkData: location.bookmarkData
        )
        return true
    }

    func consume(_ id: TerminalLaunchRequest.ID) {
        guard request?.id == id else { return }
        request = nil
    }
}
