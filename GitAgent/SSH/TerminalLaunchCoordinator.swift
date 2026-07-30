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

    func open(hostID: SSHHostConfig.ID, directory: String) {
        request = TerminalLaunchRequest(
            target: .ssh(hostID),
            directory: directory
        )
    }

    func openLocal(directory: String, bookmarkData: Data?) {
        request = TerminalLaunchRequest(
            target: .local(bookmarkData: bookmarkData),
            directory: directory
        )
    }

    func consume(_ id: TerminalLaunchRequest.ID) {
        guard request?.id == id else { return }
        request = nil
    }
}
