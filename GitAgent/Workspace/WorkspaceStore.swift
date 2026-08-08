//
//  WorkspaceStore.swift
//  GitAgent
//

import Foundation
import Observation

/// Transient macOS pages, similar to browser tabs. They deliberately are not
/// persisted: a page can refer to an unavailable local security bookmark or a
/// live agent terminal, both of which must be reopened explicitly.
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

        var id: UUID {
            switch self {
            case .newPage(let id), .myRepositories(let id), .starred(let id), .chat(let id), .agent(let id),
                 .coder(let id), .coderTerminal(let id, _), .terminal(let id),
                 .profile(let id), .settings(let id),
                 .repository(let id, _), .localRepository(let id, _, _):
                id
            }
        }

        var title: String {
            switch self {
            case .newPage: return "New Page"
            case .myRepositories: return "My Repositories"
            case .starred: return "Starred"
            case .chat: return "Chat"
            case .agent: return "Agent"
            case .coder: return "Coder"
            case .coderTerminal: return "Coder"
            case .terminal: return "Terminal"
            case .profile: return L10n.resolveCurrent(.profile)
            case .settings: return L10n.resolveCurrent(.settings)
            case .repository(_, let repo): return repo.name
            case .localRepository(_, let repo, _): return "\(repo.name) (Local)"
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
            }
        }
    }

    var pages: [Page]
    var selectedID: UUID?
    private(set) var titleOverrides: [UUID: String] = [:]
    private var backHistory: [UUID: [HistoryEntry]] = [:]

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

    func openNewPage() {
        open(.newPage(UUID()))
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

    func title(for page: Page) -> String {
        titleOverrides[page.id] ?? page.title
    }

    func updateSelectedTitle(_ title: String) {
        guard let selectedID else { return }
        titleOverrides[selectedID] = title
    }

    var canGoBack: Bool {
        guard let selectedID else { return false }
        return !(backHistory[selectedID] ?? []).isEmpty
    }

    /// Returns to the previous destination inside the selected page. Every
    /// page begins at New Page, so exhausting this stack always stops there.
    @discardableResult
    func goBack() -> Bool {
        guard let selectedID,
              let index = pages.firstIndex(where: { $0.id == selectedID }),
              var history = backHistory[selectedID],
              let entry = history.popLast() else { return false }
        backHistory[selectedID] = history
        pages[index] = entry.page
        titleOverrides[selectedID] = entry.titleOverride
        return true
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
        backHistory[id] = nil
        if selectedID == id { selectedID = pages.last?.id }
    }

    private func open(_ page: Page) {
        pages.append(page)
        backHistory[page.id] = []
        selectedID = page.id
    }

    private func replace(_ makePage: (UUID) -> Page) {
        guard let selectedID,
              let index = pages.firstIndex(where: { $0.id == selectedID }) else {
            return
        }
        let current = pages[index]
        let replacement = makePage(selectedID)
        guard replacement != current else { return }
        backHistory[selectedID, default: []].append(
            HistoryEntry(page: current, titleOverride: titleOverrides[selectedID])
        )
        titleOverrides[selectedID] = nil
        pages[index] = replacement
    }
}
