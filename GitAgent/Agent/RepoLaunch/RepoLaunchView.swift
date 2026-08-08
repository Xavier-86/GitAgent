//
//  RepoLaunchView.swift
//  GitAgent
//
//  Repository deployment history and the local/SSH deployment form.
//

import SwiftUI

#if os(macOS)
  import AppKit
#endif

private enum RepoLaunchTargetChoice: Hashable {
  case local
  case remote(SSHHostConfig.ID)
}

struct RepoLaunchView: View {
  @State private var showsInitialDeploymentForm: Bool

  init(startsWithDeploymentForm: Bool = false) {
    _showsInitialDeploymentForm = State(initialValue: startsWithDeploymentForm)
  }

  @ViewBuilder
  var body: some View {
    if showsInitialDeploymentForm {
      RepoLaunchForm(repo: nil, presentation: .navigation)
        .sidebarToggleButton()
    } else {
      RepoLaunchHistoryView()
        .sidebarToggleButton()
    }
  }
}

enum RepoLaunchFormPresentation: Equatable {
  case sheet
  case navigation
}

struct RepoLaunchForm: View {
  @Environment(AppSettings.self) private var settings
  @Environment(RepoLaunchStore.self) private var deployments
  @Environment(RepositoryLocationStore.self) private var locations
  @Environment(SSHHostStore.self) private var hosts
  @Environment(TerminalLaunchCoordinator.self) private var terminalLauncher
  @Environment(\.dismiss) private var dismiss

  let repo: Repo?
  private let presentation: RepoLaunchFormPresentation

  @State private var repositoryURL: String
  @State private var reference: String
  @State private var destinationName: String
  @State private var remoteDestination = ""
  @State private var setupCommands = ""
  @State private var buildCommands = ""
  @State private var testCommands = ""
  @State private var showsAdvancedOptions = false
  @State private var deploymentTask: Task<Void, Never>?
  @State private var didStart = false
  @State private var browseContext: RemoteBrowseContext?
  @State private var browseError: String?

  #if os(macOS)
    @State private var selectedTarget: RepoLaunchTargetChoice? = .local
    @State private var localParentPath = ""
    @State private var localBookmarkData: Data?
    @State private var folderError: String?
  #else
    @State private var selectedTarget: RepoLaunchTargetChoice?
  #endif

  init(
    repo: Repo?,
    presentation: RepoLaunchFormPresentation = .sheet
  ) {
    self.repo = repo
    self.presentation = presentation
    let url = repo.map { "https://github.com/\($0.fullName).git" } ?? ""
    _repositoryURL = State(initialValue: url)
    _reference = State(initialValue: repo?.defaultBranch ?? "")
    _destinationName = State(initialValue: repo?.name ?? "")
  }

  private var destinationPath: String {
    guard let selectedTarget else { return "" }
    switch selectedTarget {
    case .local:
      #if os(macOS)
        guard !localParentPath.isEmpty, !destinationName.isEmpty else { return "" }
        return (localParentPath as NSString).appendingPathComponent(destinationName)
      #else
        return ""
      #endif
    case .remote:
      return remoteDestination.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  private var canDeploy: Bool {
    guard deployments.activeRecordID == nil,
      deploymentTask == nil,
      selectedTarget != nil,
      !repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !destinationPath.isEmpty
    else { return false }
    #if os(macOS)
      if selectedTarget == .local { return localBookmarkData != nil }
    #endif
    return true
  }

  private var latestRecord: RepoLaunchRecord? {
    guard didStart else { return nil }
    return deployments.records.first {
      $0.repositoryURL == repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        && $0.destinationPath == destinationPath
    }
  }

  var body: some View {
    presentedForm
      .onChange(of: repositoryURL) { oldValue, value in
        guard repo == nil else { return }
        let previousName = Self.repositoryName(from: oldValue)
        let derived = Self.repositoryName(from: value)
        guard !derived.isEmpty else { return }
        if destinationName.isEmpty || destinationName == previousName {
          destinationName = derived
        }
        if case .some(.remote) = selectedTarget,
          remoteDestination.isEmpty || remoteDestination == "~/Developer/\(previousName)"
        {
          remoteDestination = "~/Developer/\(derived)"
        }
      }
      // Dismissing the form deliberately does NOT cancel the deployment:
      // remote runs are detached in tmux on the host and keep going in the
      // background; only the explicit Cancel button stops them.
      .alert(
        settings.tr(.browse),
        isPresented: Binding(
          get: { browseError != nil },
          set: { if !$0 { browseError = nil } }
        )
      ) {
        Button(settings.tr(.done)) { browseError = nil }
      } message: {
        Text(browseError ?? "")
      }
  }

  @ViewBuilder
  private var presentedForm: some View {
    switch presentation {
    case .sheet:
      NavigationStack {
        activeContent
      }
      #if os(macOS)
        .frame(
          minWidth: 560, idealWidth: 620, maxWidth: 720,
          minHeight: 520, idealHeight: 620)
      #endif
    case .navigation:
      activeContent
    }
  }

  @ViewBuilder
  private var activeContent: some View {
    if let browseContext {
      RemotePathPickerView(
        route: browseContext.route,
        initialPath: remoteDestination.trimmingCharacters(in: .whitespacesAndNewlines),
        onBack: { self.browseContext = nil }
      ) { selected in
        remoteDestination = selected
        self.browseContext = nil
      }
    } else {
      deploymentForm
    }
  }

  private var deploymentForm: some View {
    Form {
      Section {
        formTextField(
          settings.tr(.repositoryURL),
          prompt: settings.tr(.repositoryURLHint),
          text: $repositoryURL
        )
        #if os(iOS)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)
        #endif
        .disabled(repo != nil || deploymentTask != nil)
      }

      Section(settings.tr(.deploymentTarget)) {
        HStack(spacing: 12) {
          Text(settings.tr(.computer))
          Spacer(minLength: 12)
          Picker("", selection: $selectedTarget) {
            Text(settings.tr(.selectComputer))
              .tag(Optional<RepoLaunchTargetChoice>.none)
            #if os(macOS)
              Text(settings.tr(.thisMac))
                .tag(Optional(RepoLaunchTargetChoice.local))
            #endif
            ForEach(hosts.hosts) { host in
              Text(host.locationDisplayName)
                .tag(Optional(RepoLaunchTargetChoice.remote(host.id)))
            }
          }
          .labelsHidden()
          .fixedSize()
        }
        .disabled(deploymentTask != nil)
        .onChange(of: selectedTarget) { _, target in
          if case .some(.remote) = target,
            remoteDestination.isEmpty,
            !destinationName.isEmpty
          {
            remoteDestination = "~/Developer/\(destinationName)"
          }
        }

        destinationFields
      }

      Section {
        DisclosureGroup(
          settings.tr(.advancedOptions),
          isExpanded: $showsAdvancedOptions
        ) {
          VStack(alignment: .leading, spacing: 12) {
            formTextField(
              settings.tr(.gitReference),
              prompt: settings.tr(.gitReferenceHint),
              text: $reference
            )
            #if os(iOS)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
            #endif

            #if os(macOS)
              if selectedTarget == .local {
                formTextField(
                  settings.tr(.destinationName),
                  prompt: Self.repositoryName(from: repositoryURL),
                  text: $destinationName
                )
              }
            #endif

            Divider()
            Text(settings.tr(.deploymentCommands))
              .font(.callout.weight(.semibold))
            commandEditor(settings.tr(.setupCommands), text: $setupCommands)
            commandEditor(settings.tr(.buildCommands), text: $buildCommands)
            commandEditor(settings.tr(.testCommands), text: $testCommands)
            Text(settings.tr(.commandsOptionalHint))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.top, 8)
        }
      }
      .disabled(deploymentTask != nil)

      if didStart {
        deploymentStatus
      }
    }
    .formStyle(.grouped)
    .navigationTitle(settings.tr(.deployRepository))
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        if deploymentTask != nil {
          Button(settings.tr(.cancel), role: .destructive) {
            deploymentTask?.cancel()
          }
        } else {
          Button(settings.tr(presentation == .navigation ? .back : .cancel)) { dismiss() }
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button(settings.tr(.deploy)) { startDeployment() }
          .disabled(!canDeploy)
      }
    }
  }

  @ViewBuilder
  private var destinationFields: some View {
    switch selectedTarget {
    case .local:
      #if os(macOS)
        VStack(alignment: .leading, spacing: 6) {
          Text(settings.tr(.destinationFolder))
            .font(.callout)
            .foregroundStyle(.secondary)
          HStack(spacing: 10) {
            Text(localParentPath.isEmpty ? settings.tr(.noFolderSelected) : localParentPath)
              .foregroundStyle(localParentPath.isEmpty ? .tertiary : .primary)
              .lineLimit(1)
              .truncationMode(.middle)
              .frame(maxWidth: .infinity, alignment: .leading)
            Button(settings.tr(.chooseParentFolder)) { chooseLocalParent() }
              .fixedSize()
              .disabled(deploymentTask != nil)
          }
        }
        if !destinationPath.isEmpty {
          Text(destinationPath)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }
        if let folderError {
          Text(folderError).font(.caption).foregroundStyle(.red)
        }
      #endif
    case .remote:
      HStack(alignment: .bottom, spacing: 8) {
        formTextField(
          settings.tr(.destinationPath),
          prompt: settings.tr(.repositoryPathHint),
          text: $remoteDestination
        )
        #if os(iOS)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        #endif
        .disabled(deploymentTask != nil)
        Button {
          browseRemoteDestination()
        } label: {
          Image(systemName: "folder")
        }
        .disabled(deploymentTask != nil)
        .help(settings.tr(.browse))
      }
    case nil:
      EmptyView()
    }
  }

  private func browseRemoteDestination() {
    guard case .remote(let hostID) = selectedTarget,
      let host = hosts.hosts.first(where: { $0.id == hostID })
    else { return }
    do {
      browseContext = RemoteBrowseContext(route: try hosts.connectionRoute(for: host))
    } catch {
      browseError = error.localizedDescription
    }
  }

  private func formTextField(
    _ title: String,
    prompt: String,
    text: Binding<String>
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.callout)
        .foregroundStyle(.secondary)
      TextField("", text: text, prompt: Text(prompt))
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity)
    }
  }

  private func commandEditor(_ title: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.callout).foregroundStyle(.secondary)
      TextEditor(text: text)
        .font(.system(.callout, design: .monospaced))
        .frame(minHeight: 62)
    }
  }

  @ViewBuilder
  private var deploymentStatus: some View {
    Section {
      if let record = latestRecord {
        HStack {
          if record.status == .running { ProgressView().controlSize(.small) }
          Text(settings.tr(record.status.localizationKey))
          if record.status == .running {
            Spacer()
            Text(settings.tr(record.stage.localizationKey))
              .foregroundStyle(.secondary)
          }
        }
        if let error = record.errorMessage {
          Text(error).foregroundStyle(.red)
        }
        if !record.log.isEmpty {
          ScrollView {
            Text(record.log)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .topLeading)
          }
          .frame(maxHeight: 180)
        }
      } else {
        ProgressView(settings.tr(.deploying))
      }
    }
  }

  private func startDeployment() {
    guard let selectedTarget else { return }
    let hostID: SSHHostConfig.ID?
    switch selectedTarget {
    case .local: hostID = nil
    case .remote(let id): hostID = id
    }
    let host = hostID.flatMap { id in hosts.hosts.first { $0.id == id } }
    let route: SSHConnectionRoute?
    do {
      route = try host.map { try hosts.connectionRoute(for: $0) }
    } catch {
      browseError = error.localizedDescription
      return
    }
    let request = RepoLaunchRequest(
      repositoryURL: repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines),
      repositoryFullName: repo?.fullName,
      reference: reference.trimmingCharacters(in: .whitespacesAndNewlines),
      destinationPath: destinationPath,
      hostID: hostID,
      localBookmarkData: localBookmark,
      setupCommands: setupCommands,
      buildCommands: buildCommands,
      testCommands: testCommands
    )
    didStart = true
    deploymentTask = Task {
      let deployed = await deployments.deploy(request, route: route)
      guard !Task.isCancelled else {
        deploymentTask = nil
        return
      }
      if let deployed {
        registerLocation(for: request, result: deployed)
        deploymentTask = nil
        dismiss()
        await Task.yield()
        openTerminal(for: request, result: deployed)
        return
      }
      deploymentTask = nil
    }
  }

  private func openTerminal(for request: RepoLaunchRequest, result: RepoLaunchResult) {
    terminalLauncher.open(
      hostID: request.hostID,
      directory: result.canonicalPath,
      bookmarkData: result.localBookmarkData
    )
  }

  private var localBookmark: Data? {
    #if os(macOS)
      localBookmarkData
    #else
      nil
    #endif
  }

  private func registerLocation(for request: RepoLaunchRequest, result: RepoLaunchResult) {
    guard let repo else { return }
    if let hostID = request.hostID {
      let id = locations.add(repository: repo, hostID: hostID, path: result.canonicalPath)
      locations.markConnected(id, canonicalPath: result.canonicalPath, remoteName: "origin")
      return
    }
    #if os(macOS)
      guard let bookmarkData = result.localBookmarkData else { return }
      let id = locations.addLocal(
        repository: repo,
        path: result.canonicalPath,
        bookmarkData: bookmarkData
      )
      locations.markConnected(
        id,
        canonicalPath: result.canonicalPath,
        remoteName: "origin",
        bookmarkData: bookmarkData
      )
    #endif
  }

  #if os(macOS)
    private func chooseLocalParent() {
      let panel = NSOpenPanel()
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = true
      panel.prompt = settings.tr(.chooseParentFolder)
      guard panel.runModal() == .OK, let url = panel.url else { return }
      do {
        localBookmarkData = try url.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        localParentPath = url.path
        folderError = nil
      } catch {
        localBookmarkData = nil
        folderError = "\(settings.tr(.folderSelectionFailed)): \(error.localizedDescription)"
      }
    }
  #endif

  private static func repositoryName(from value: String) -> String {
    var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    var name = trimmed.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
    if name.hasSuffix(".git") { name.removeLast(4) }
    return name
  }
}
