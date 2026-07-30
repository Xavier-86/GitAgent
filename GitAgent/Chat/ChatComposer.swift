//
//  ChatComposer.swift
//  GitAgent
//

import SwiftUI

/// Chat input bar with @ / reference pickers:
/// - Type `@` to open the full-screen repository picker (search + arrow keys +
///   Return on macOS, touch on iOS). Only one repository per message.
/// - Type `/` (after choosing a repository) to browse and attach files/folders
///   — drill into folders without limit, attach as many as you like.
struct ChatComposer: View {
    @Environment(AppSettings.self) private var settings

    let isStreaming: Bool
    let onSend: (String, [ChatReference]) -> Void
    let onStop: () -> Void

    @State private var input = ""
    @State private var references: [ChatReference] = []
    /// The repository chosen via @ — unlocks / file browsing.
    @State private var repoContext: Repo?
    @State private var showRepoPicker = false
    @State private var showFilePicker = false
    /// Keyboard state forwarded to the file picker (the text field keeps focus).
    @State private var fileHighlight = 0
    @State private var fileKey: FilePickerPanel.Key?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showFilePicker, let repoContext {
                FilePickerPanel(
                    repo: repoContext,
                    highlight: $fileHighlight,
                    key: $fileKey,
                    onAdd: { reference in
                        if !references.contains(reference) { references.append(reference) }
                        // Keep the reference in the user's text verbatim.
                        input += "/\(reference.path) "
                        inputFocused = true
                    },
                    onClose: { showFilePicker = false })
            }

            if !references.isEmpty {
                chipsRow
            }

            HStack(spacing: 8) {
                // Plain field inside a padded container — applying padding to
                // the TextField itself is ignored by AppKit on macOS.
                TextField(settings.tr(.agentPlaceholder), text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onChange(of: input) { _, newValue in
                        // "@" opens the full-screen repository picker…
                        if repoContext == nil, newValue.hasSuffix("@") {
                            input.removeLast()
                            showRepoPicker = true
                        }
                        // …and "/" (after a repo was chosen) opens the file picker.
                        if repoContext != nil, newValue.hasSuffix("/") {
                            input.removeLast()
                            fileHighlight = 0
                            showFilePicker = true
                        }
                    }
                    .onKeyPress(.upArrow) {
                        if showFilePicker { fileHighlight -= 1; return .handled }
                        return .ignored
                    }
                    .onKeyPress(.downArrow) {
                        if showFilePicker { fileHighlight += 1; return .handled }
                        return .ignored
                    }
                    .onKeyPress(.leftArrow) {
                        guard showFilePicker else { return .ignored }
                        fileKey = .back
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        guard showFilePicker else { return .ignored }
                        fileKey = .forward
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        guard showFilePicker else { return .ignored }
                        showFilePicker = false
                        return .handled
                    }
                    .onKeyPress(.return) {
                        if showFilePicker {
                            fileKey = .select
                            return .handled
                        }
                        return .ignored
                    }
                    .onSubmit { send() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                if isStreaming {
                    Button(role: .cancel, action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { send() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                    }
                    .buttonStyle(.plain)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showRepoPicker) {
            RepoPickerView(onSelect: selectRepo, onCancel: { showRepoPicker = false })
        }
        #else
        .sheet(isPresented: $showRepoPicker) {
            RepoPickerView(onSelect: selectRepo, onCancel: { showRepoPicker = false })
                .frame(minWidth: 480, minHeight: 560)
        }
        #endif
    }

    private func selectRepo(_ repo: Repo) {
        repoContext = repo
        references.append(ChatReference(kind: .repo, owner: repo.owner.login, repo: repo.name,
                                        branch: repo.defaultBranch, path: ""))
        // Keep the mention in the user's text verbatim.
        if !input.isEmpty, !input.hasSuffix(" "), !input.hasSuffix("\n") {
            input += " "
        }
        input += "@\(repo.fullName) "
        showRepoPicker = false
        inputFocused = true
    }

    // MARK: - Reference chips

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(references) { reference in
                    HStack(spacing: 4) {
                        Image(systemName: reference.icon)
                        Text(reference.displayName)
                            .lineLimit(1)
                        Button { removeReference(reference) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: CGFloat(settings.uiFontSize) - 4))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }

    private func removeReference(_ reference: ChatReference) {
        references.removeAll { $0.id == reference.id }
        if reference.kind == .repo {
            // Removing the repo also drops its file/folder references.
            repoContext = nil
            references.removeAll { $0.kind != .repo }
        }
    }

    // MARK: - Sending

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        let attached = references
        input = ""
        references = []
        repoContext = nil
        showFilePicker = false
        onSend(text, attached)
    }
}

// MARK: - @ repository picker (full screen)

/// Full-screen repository picker with its own search field. macOS: ↑↓ move,
/// Return selects, Esc cancels. iOS: touch. Shows a progress state while the
/// repository list loads.
private struct RepoPickerView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let onSelect: (Repo) -> Void
    let onCancel: () -> Void

    @State private var repos: [Repo]?
    @State private var query = ""
    @State private var highlight = 0
    @FocusState private var searchFocused: Bool

    private var filtered: [Repo] {
        guard let repos else { return [] }
        if query.isEmpty { return repos }
        return repos.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField(settings.tr(.searchKeywordPrompt), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.return) {
                        guard !filtered.isEmpty else { return .ignored }
                        onSelect(filtered[highlight])
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        onCancel()
                        return .handled
                    }
                    .onChange(of: query) { _, _ in highlight = 0 }
                    .padding()

                if repos != nil {
                    List(Array(filtered.enumerated()), id: \.element.id) { index, repo in
                        Button { onSelect(repo) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repo.fullName).lineLimit(1)
                                    if let description = repo.description, !description.isEmpty {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .listRowBackground(index == highlight ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                } else {
                    Spacer()
                    ProgressView(settings.tr(.loading))
                    Spacer()
                }
            }
            .navigationTitle(settings.tr(.repositories))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.tr(.cancel), action: onCancel)
                }
            }
            .onAppear { searchFocused = true }
            .task { await load() }
        }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !filtered.isEmpty else { return .ignored }
        highlight = (highlight + delta + filtered.count) % filtered.count
        return .handled
    }

    private func load() async {
        guard repos == nil, let client = auth.client else { return }
        repos = (try? await client.myRepos()) ?? []
        highlight = 0
    }
}

// MARK: - / file & folder picker

/// Browses the selected repository. Tap a folder to enter it (no depth limit),
/// tap the ⊕ on a folder to attach it, tap a file to attach it.
/// Keyboard (macOS): ↑↓ move, Return attaches, → enters a folder, ← goes up,
/// Esc closes. Keys arrive via bindings from the focused text field.
private struct FilePickerPanel: View {
    enum Key { case select, forward, back }

    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings

    let repo: Repo
    @Binding var highlight: Int
    @Binding var key: Key?
    let onAdd: (ChatReference) -> Void
    let onClose: () -> Void

    @State private var path = ""
    @State private var items: [RepoContent] = []
    @State private var isLoading = true

    /// Rows shown, in display order.
    private var selectable: [RepoContent] {
        items.filter { $0.type == .dir || $0.type == .file }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if !path.isEmpty {
                    Button {
                        goUp()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                Text(path.isEmpty ? repo.fullName : path)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button(settings.tr(.done), action: onClose)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(settings.tr(.loading))
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(selectable.enumerated()), id: \.element.id) { index, item in
                            row(for: item)
                                .background(index == highlight ? Color.accentColor.opacity(0.15) : .clear)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 6)
        .task(id: path) { await load() }
        .onChange(of: highlight) { _, _ in clampHighlight() }
        .onChange(of: key) { _, newKey in
            guard let newKey else { return }
            defer { key = nil }
            handle(newKey)
        }
    }

    // MARK: - Keyboard

    private func clampHighlight() {
        guard !selectable.isEmpty else { highlight = 0; return }
        highlight = max(0, min(highlight, selectable.count - 1))
    }

    private func handle(_ key: Key) {
        switch key {
        case .back:
            goUp()
        case .forward, .select:
            guard !selectable.isEmpty else { return }
            clampHighlight()
            let item = selectable[highlight]
            switch (key, item.type) {
            case (.forward, .dir):
                path = item.path
                highlight = 0
            case (.select, .dir):
                add(item, kind: .folder)
            case (.select, .file):
                add(item, kind: .file)
            default:
                break
            }
        }
    }

    private func goUp() {
        guard !path.isEmpty else { return }
        path = (path as NSString).deletingLastPathComponent
        highlight = 0
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for item: RepoContent) -> some View {
        switch item.effectiveType {
        case .dir:
            HStack {
                Button { path = item.path; highlight = 0 } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(item.name).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                Button { add(item, kind: .folder) } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        case .file:
            Button { add(item, kind: .file) } label: {
                HStack(spacing: 8) {
                    Image(systemName: item.isMarkdown ? "doc.richtext" : "doc.text")
                        .foregroundStyle(.secondary)
                    Text(item.name).lineLimit(1)
                    Spacer()
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        default:
            EmptyView()
        }
    }

    private func add(_ item: RepoContent, kind: ChatReference.Kind) {
        onAdd(ChatReference(kind: kind, owner: repo.owner.login, repo: repo.name,
                            branch: repo.defaultBranch, path: item.path))
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        items = (try? await client.contents(owner: repo.owner.login, repo: repo.name, path: path)) ?? []
        isLoading = false
    }
}
