//
//  WorkspaceStore.swift
//  GitAgent
//

import Foundation
import Observation

/// Transient browser-style pages: toolbar tabs on macOS and a Safari-style
/// page switcher on iPhone. They deliberately are not persisted because a
/// page can refer to an unavailable working tree or a live agent terminal.
@Observable
final class WorkspaceStore {
    enum Page: Identifiable, Hashable {
        case newPage(UUID)
        case myRepositories(UUID)
        case starred(UUID)
        case chat(UUID)
        case agent(UUID)
        case coder(UUID)
        case coderTerminal(UUID, CoderSessionRecord.ID)
        case terminal(UUID)
        case profile(UUID)
        case settings(UUID)
        case repository(UUID, Repo)
        case localRepository(UUID, Repo, RepositoryLocation)
        case remoteRepository(UUID, Repo, RepositoryLocation)

        var id: UUID {
            switch self {
            case .newPage(let id), .myRepositories(let id), .starred(let id), .chat(let id), .agent(let id),
                 .coder(let id), .coderTerminal(let id, _), .terminal(let id),
                 .profile(let id), .settings(let id),
                 .repository(let id, _), .localRepository(let id, _, _),
                 .remoteRepository(let id, _, _):
                id
            }
        }

        var title: String {
            switch self {
            case .newPage: return L10n.resolveCurrent(.newPage)
            case .myRepositories: return L10n.resolveCurrent(.myRepos)
            case .starred: return L10n.resolveCurrent(.starred)
            case .chat: return L10n.resolveCurrent(.chat)
            case .agent: return L10n.resolveCurrent(.agent)
            case .coder: return L10n.resolveCurrent(.coder)
            case .coderTerminal: return L10n.resolveCurrent(.coder)
            case .terminal: return L10n.resolveCurrent(.terminal)
            case .profile: return L10n.resolveCurrent(.profile)
            case .settings: return L10n.resolveCurrent(.settings)
            case .repository(_, let repo): return repo.name
            case .localRepository(_, let repo, _):
                return "\(repo.name) (\(L10n.resolveCurrent(.thisMac)))"
            case .remoteRepository(_, let repo, _): return repo.name
            }
        }

        var icon: String {
            switch self {
            case .newPage: return "square.grid.2x2"
            case .myRepositories: return "books.vertical"
            case .starred: return "star"
            case .chat: return "bubble.left.and.bubble.right"
            case .agent: return "brain.head.profile"
            case .coder: return "chevron.left.forwardslash.chevron.right"
            case .coderTerminal: return "chevron.left.forwardslash.chevron.right"
            case .terminal: return "terminal"
            case .profile: return "person.crop.circle"
            case .settings: return "gearshape"
            case .repository: return "book.closed"
            case .localRepository: return "externaldrive"
            case .remoteRepository: return "server.rack"
            }
        }
    }

    var pages: [Page]
    var selectedID: UUID?
    private(set) var titleOverrides: [UUID: String] = [:]
    #if os(iOS)
    private(set) var pagePreviewData: [UUID: Data] = [:]
    #endif
    private var backHistory: [UUID: [HistoryEntry]] = [:]
    private var contextualBackActions: [UUID: () -> Bool] = [:]

    private struct HistoryEntry {
        let page: Page
        let titleOverride: String?
    }

    init() {
        // The app always starts with a real page, not an empty navigation shell.
        let initial = Page.newPage(UUID())
        pages = [initial]
        selectedID = initial.id
    }

    /// Restores the same clean browser state as a cold app launch.
    func resetToInitialPage() {
        let initial = Page.newPage(UUID())
        pages = [initial]
        selectedID = initial.id
        titleOverrides.removeAll()
        #if os(iOS)
        pagePreviewData.removeAll()
        #endif
        backHistory.removeAll()
        contextualBackActions.removeAll()
    }

    func openNewPage() {
        open(.newPage(UUID()))
    }

    func openMyRepositories() {
        open(.myRepositories(UUID()))
    }

    func openStarred() {
        open(.starred(UUID()))
    }

    func openChat() {
        open(.chat(UUID()))
    }

    func openAgent() {
        open(.agent(UUID()))
    }

    func openCoder() {
        open(.coder(UUID()))
    }

    func openTerminal() {
        open(.terminal(UUID()))
    }

    func openProfile() {
        open(.profile(UUID()))
    }

    func openSettings() {
        open(.settings(UUID()))
    }

    // MARK: - Current page navigation

    /// Regular app navigation replaces the selected page, just like following
    /// a link in a browser tab. Only `open…` methods create another tab.
    func showMyRepositories() {
        replace { .myRepositories($0) }
    }

    func showStarred() {
        replace { .starred($0) }
    }

    func showChat() {
        replace { .chat($0) }
    }

    func showAgent() {
        replace { .agent($0) }
    }

    func showCoder() {
        replace { .coder($0) }
    }

    func showCoderTerminal(_ record: CoderSessionRecord) {
        replace { .coderTerminal($0, record.id) }
        updateSelectedTitle(record.repositoryFullName)
    }

    /// Selects an existing page for a Coder session, or creates one when a
    /// notification opens a session that is not currently represented.
    func focusCoderTerminal(_ record: CoderSessionRecord) {
        if let page = pages.first(where: {
            if case .coderTerminal(_, let recordID) = $0 {
                return recordID == record.id
            }
            return false
        }) {
            selectedID = page.id
            return
        }
        open(.coderTerminal(UUID(), record.id))
        updateSelectedTitle(record.repositoryFullName)
    }

    func showTerminal() {
        replace { .terminal($0) }
    }

    func showProfile() {
        replace { .profile($0) }
    }

    func showSettings() {
        replace { .settings($0) }
    }

    func showRepository(_ repo: Repo) {
        replace { .repository($0, repo) }
    }

    func showLocalRepository(_ repo: Repo, location: RepositoryLocation) {
        replace { .localRepository($0, repo, location) }
    }

    func showRemoteRepository(
        _ repo: Repo,
        location: RepositoryLocation,
        host: SSHHostConfig
    ) {
        replace { .remoteRepository($0, repo, location) }
        updateSelectedTitle("\(repo.name) (\(host.locationDisplayName))")
    }

    func title(for page: Page) -> String {
        titleOverrides[page.id] ?? page.title
    }

    func updateSelectedTitle(_ title: String) {
        guard let selectedID else { return }
        titleOverrides[selectedID] = title
    }

    #if os(iOS)
    func updatePagePreview(_ data: Data, for pageID: UUID) {
        guard pages.contains(where: { $0.id == pageID }) else { return }
        pagePreviewData[pageID] = data
    }
    #endif

    var canGoBack: Bool {
        guard let selectedID else { return false }
        if contextualBackActions[selectedID] != nil { return true }
        return !(backHistory[selectedID] ?? []).isEmpty
    }

    /// Returns to the previous destination inside the selected page. Every
    /// page begins at New Page, so exhausting this stack always stops there.
    @discardableResult
    func goBack() -> Bool {
        if let selectedID,
           let contextualBackAction = contextualBackActions[selectedID],
           contextualBackAction() {
            return true
        }
        guard let selectedID,
              let index = pages.firstIndex(where: { $0.id == selectedID }),
              var history = backHistory[selectedID],
              let entry = history.popLast() else { return false }
        backHistory[selectedID] = history
        pages[index] = entry.page
        titleOverrides[selectedID] = entry.titleOverride
        return true
    }

    /// Lets a stateful page route the fixed toolbar Back button through its
    /// own file/directory history before the page-level history is popped.
    func setContextualBackAction(
        for pageID: UUID,
        isAvailable: Bool,
        action: @escaping () -> Bool
    ) {
        contextualBackActions[pageID] = isAvailable ? action : nil
    }

    func clearContextualBackAction(for pageID: UUID) {
        contextualBackActions[pageID] = nil
    }

    func isShowingCoderTerminal(_ recordID: CoderSessionRecord.ID) -> Bool {
        guard let selectedID,
              let page = pages.first(where: { $0.id == selectedID }),
              case .coderTerminal(_, let currentRecordID) = page else { return false }
        return currentRecordID == recordID
    }

    func close(_ id: UUID) {
        pages.removeAll { $0.id == id }
        titleOverrides[id] = nil
        #if os(iOS)
        pagePreviewData[id] = nil
        #endif
        backHistory[id] = nil
        contextualBackActions[id] = nil
        if selectedID == id { selectedID = pages.last?.id }
        #if os(iOS)
        if pages.isEmpty {
            let initial = Page.newPage(UUID())
            pages = [initial]
            selectedID = initial.id
        }
        #endif
    }

    private func open(_ page: Page) {
        pages.append(page)
        backHistory[page.id] = []
        selectedID = page.id
    }

    private func replace(_ makePage: (UUID) -> Page) {
        guard let selectedID,
              let index = pages.firstIndex(where: { $0.id == selectedID }) else {
            open(makePage(UUID()))
            return
        }
        let current = pages[index]
        let replacement = makePage(selectedID)
        guard replacement != current else { return }
        backHistory[selectedID, default: []].append(
            HistoryEntry(page: current, titleOverride: titleOverrides[selectedID])
        )
        contextualBackActions[selectedID] = nil
        titleOverrides[selectedID] = nil
        #if os(iOS)
        pagePreviewData[selectedID] = nil
        #endif
        pages[index] = replacement
    }
}
