//
//  AddRepositoryLocationView.swift
//  GitAgent
//
//  Connects an existing local or SSH working tree to a GitHub repository.
//

import SwiftUI

#if os(macOS)
  import AppKit
#endif

private enum RepositoryComputerChoice: Hashable {
  case local
  case remote(SSHHostConfig.ID)
}

struct AddRepositoryLocationView: View {
  @Environment(AppSettings.self) private var settings
  @Environment(SSHHostStore.self) private var hosts

  let onBack: () -> Void
  let onSave: (SSHHostConfig.ID?, String, Data?) -> Void

  #if os(macOS)
    @State private var selectedComputer: RepositoryComputerChoice? = .local
    @State private var bookmarkData: Data?
    @State private var selectionError: String?
  #else
    @State private var selectedComputer: RepositoryComputerChoice?
  #endif
  @State private var path = ""
  @State private var browseContext: RemoteBrowseContext?
  @State private var browseError: String?

  private var trimmedPath: String {
    path.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canSave: Bool {
    guard let selectedComputer, !trimmedPath.isEmpty else { return false }
    #if os(macOS)
      if selectedComputer == .local { return bookmarkData != nil }
    #endif
    return true
  }

  var body: some View {
    Group {
      if let browseContext {
        RemotePathPickerView(
          route: browseContext.route,
          initialPath: trimmedPath,
          onBack: { self.browseContext = nil }
        ) { selected in
          path = selected
          self.browseContext = nil
        }
      } else {
        locationForm
      }
    }
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
    #if os(macOS)
      .frame(minWidth: 560, idealWidth: 560, minHeight: 280)
    #endif
  }

  private var locationForm: some View {
    Form {
      Section(settings.tr(.computer)) {
        Picker(settings.tr(.computer), selection: $selectedComputer) {
          Text(settings.tr(.selectComputer))
            .tag(Optional<RepositoryComputerChoice>.none)
          #if os(macOS)
            Text(settings.tr(.thisMac))
              .tag(Optional(RepositoryComputerChoice.local))
          #endif
          ForEach(hosts.hosts) { host in
            Text(host.locationDisplayName)
              .tag(Optional(RepositoryComputerChoice.remote(host.id)))
          }
        }
        .labelsHidden()
        .onChange(of: selectedComputer) {
          #if os(macOS)
            if selectedComputer != .local {
              bookmarkData = nil
              selectionError = nil
              path = ""
            }
          #endif
        }
      }

      Section {
        repositoryPathField
      } header: {
        Text(settings.tr(.repositoryPath))
      } footer: {
        Text(pathFooter)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .formStyle(.grouped)
    .navigationTitle(settings.tr(.addRepositoryLocation))
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(settings.tr(.back), action: onBack)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button(settings.tr(.saveAndVerify), action: save)
          .disabled(!canSave)
      }
    }
  }

  @ViewBuilder
  private var repositoryPathField: some View {
    #if os(macOS)
      if selectedComputer == .local {
        HStack(spacing: 10) {
          Text(path.isEmpty ? settings.tr(.localRepositoryPathFooter) : path)
            .foregroundStyle(path.isEmpty ? .tertiary : .primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
          Button(settings.tr(.chooseFolder)) {
            Task { await chooseLocalFolder() }
          }
          .fixedSize()
        }
        if let selectionError {
          Text(selectionError)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      } else {
        pathTextField
      }
    #else
      pathTextField
    #endif
  }

  private var pathTextField: some View {
    HStack(spacing: 8) {
      TextField("", text: $path, prompt: Text(settings.tr(.repositoryPathHint)))
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        #if os(iOS)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        #endif
      if case .remote(let hostID)? = selectedComputer,
        let host = hosts.hosts.first(where: { $0.id == hostID })
      {
        Button {
          browse(host)
        } label: {
          Image(systemName: "folder")
        }
        .help(settings.tr(.browse))
      }
    }
  }

  private func browse(_ host: SSHHostConfig) {
    do {
      browseContext = RemoteBrowseContext(route: try hosts.connectionRoute(for: host))
    } catch {
      browseError = error.localizedDescription
    }
  }

  private var pathFooter: String {
    #if os(macOS)
      settings.tr(
        selectedComputer == .local ? .localRepositoryPathFooter : .repositoryPathFooter)
    #else
      settings.tr(.repositoryPathFooter)
    #endif
  }

  private func save() {
    guard let selectedComputer else { return }
    switch selectedComputer {
    case .local:
      #if os(macOS)
        guard let bookmarkData else { return }
        onSave(nil, trimmedPath, bookmarkData)
      #endif
    case .remote(let hostID):
      onSave(hostID, trimmedPath, nil)
    }
  }

  #if os(macOS)
    @MainActor
    private func chooseLocalFolder() async {
      let panel = NSOpenPanel()
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = false
      panel.prompt = settings.tr(.chooseFolder)

      guard await panel.begin() == .OK, let directoryURL = panel.url else { return }
      do {
        bookmarkData = try directoryURL.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        path = directoryURL.path
        selectionError = nil
      } catch {
        bookmarkData = nil
        selectionError = "\(settings.tr(.folderSelectionFailed)): \(error.localizedDescription)"
      }
    }
  #endif
}
