//
//  CoderView.swift
//  GitAgent
//
//  Coder agent: create interactive coding-CLI sessions on connected working
//  copies, and reopen them in a full terminal. Styled after the Terminal
//  page's host list.
//

import SwiftUI

struct CoderView: View {
  private static let formLabelWidth: CGFloat = 110

  @Environment(AppSettings.self) private var settings
  @Environment(CoderStore.self) private var coder
  @Environment(RepositoryLocationStore.self) private var locations
  @Environment(SSHHostStore.self) private var hosts
  @Environment(WorkspaceStore.self) private var workspace
  @Environment(\.isWorkspacePage) private var isWorkspacePage

  @State private var selectedTool: CoderTool?
  @State private var selectedLocationID: RepositoryLocation.ID?
  @State private var initialPrompt = ""

  private var tool: CoderTool {
    selectedTool ?? settings.coderTool
  }

  private var connectedLocations: [RepositoryLocation] {
    locations.locations.filter(\.isConnected)
  }

  private var selectedLocation: RepositoryLocation? {
    if let selectedLocationID,
      let location = connectedLocations.first(where: { $0.id == selectedLocationID })
    {
      return location
    }
    return connectedLocations.count == 1 ? connectedLocations.first : nil
  }

  /// Connected working copies grouped by host: this Mac is just one host
  /// among the saved SSH hosts, not a separate category.
  private var locationGroups: [(title: String, locations: [RepositoryLocation])] {
    var groups: [(title: String, locations: [RepositoryLocation])] = []
    for location in connectedLocations {
      let title: String
      if let hostID = location.hostID {
        title = hosts.hosts.first { $0.id == hostID }?.locationDisplayName ?? "SSH"
      } else {
        title = settings.tr(.thisMac)
      }
      if let index = groups.firstIndex(where: { $0.title == title }) {
        groups[index].locations.append(location)
      } else {
        groups.append((title, [location]))
      }
    }
    // "This Mac" first, then the other hosts alphabetically.
    return groups.sorted {
      ($0.locations.first?.hostID == nil) != ($1.locations.first?.hostID == nil)
        ? $0.locations.first?.hostID == nil
        : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  var body: some View {
    List {
      newSessionSection
      sessionsSection
    }
    .macTransparentScrollBackground()
    .sidebarToggleButton()
    .navigationTitle(settings.tr(.coder))
    .onAppear {
      if isWorkspacePage { workspace.updateSelectedTitle(settings.tr(.coder)) }
    }
    .alert(
      settings.tr(.coderCreateFailed),
      isPresented: Binding(
        get: { coder.creationError != nil },
        set: { if !$0 { coder.creationError = nil } }
      )
    ) {
      Button(settings.tr(.done)) { coder.creationError = nil }
    } message: {
      Text(coder.creationError ?? "")
    }
  }

  private var newSessionSection: some View {
    Section(settings.tr(.coderNewSession)) {
      HStack {
        Text(settings.tr(.coderTool))
          .foregroundStyle(.secondary)
          .frame(width: Self.formLabelWidth, alignment: .leading)
        Picker(settings.tr(.coderTool), selection: Binding(
          get: { tool },
          set: { selectedTool = $0 }
        )) {
          ForEach(CoderTool.allCases) { tool in
            Text(tool.displayName).tag(tool)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        Spacer()
      }

      if connectedLocations.isEmpty {
        Text(settings.tr(.coderNoLocations))
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        workingCopyPicker
      }

      HStack(alignment: .bottom) {
        TextField(
          "",
          text: $initialPrompt,
          prompt: Text(settings.tr(.coderInitialPromptHint)),
          axis: .vertical
        )
        .lineLimit(1...4)
        .textFieldStyle(.roundedBorder)
        #if os(iOS)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        #endif

        Button(settings.tr(.coderStartSession)) { startSession() }
          .buttonStyle(.borderedProminent)
          .disabled(selectedLocation == nil)
      }
    }
  }

  private var workingCopyPicker: some View {
    HStack {
      Text(settings.tr(.coderWorkingCopy))
        .foregroundStyle(.secondary)
        .frame(width: Self.formLabelWidth, alignment: .leading)
      Picker(settings.tr(.coderWorkingCopy), selection: $selectedLocationID) {
        Text(settings.tr(.coderSelectLocation))
          .tag(Optional<RepositoryLocation.ID>.none)
        ForEach(locationGroups, id: \.title) { group in
          Section(group.title) {
            ForEach(group.locations) { location in
              locationLabel(location)
                .tag(Optional(location.id))
            }
          }
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      Spacer()
    }
  }

  private var sessionsSection: some View {
    Section(settings.tr(.coderSessions)) {
      if coder.records.isEmpty {
        Text(settings.tr(.coderNoSessions))
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        ForEach(coder.records) { record in
          sessionEntry(record)
        }
      }
    }
  }

  private func sessionEntry(_ record: CoderSessionRecord) -> some View {
    Group {
      if isWorkspacePage {
        Button {
          workspace.showCoderTerminal(record)
        } label: {
          CoderSessionRow(record: record, runtime: coder.runtime(record.id))
        }
        .buttonStyle(.plain)
      } else {
        NavigationLink {
          CoderTerminalView(recordID: record.id)
        } label: {
          CoderSessionRow(record: record, runtime: coder.runtime(record.id))
        }
      }
    }
    .contextMenu {
      Button(role: .destructive) {
        coder.kill(record: record, hosts: hosts)
      } label: {
        Label(settings.tr(.coderKillSession), systemImage: "stop.circle")
      }
      .disabled(!coder.runtime(record.id).alive)
      Button(role: .destructive) {
        coder.delete(record: record, hosts: hosts)
      } label: {
        Label(settings.tr(.delete), systemImage: "trash")
      }
    }
  }

  private func locationLabel(_ location: RepositoryLocation) -> some View {
    HStack {
      Text(location.repositoryFullName)
      if let hostID = location.hostID,
        let host = hosts.hosts.first(where: { $0.id == hostID })
      {
        Text("· \(host.locationDisplayName)")
          .foregroundStyle(.secondary)
      }
    }
  }

  private func startSession() {
    guard let location = selectedLocation else { return }
    coder.createSession(
      tool: tool,
      location: location,
      initialPrompt: initialPrompt,
      hosts: hosts
    )
    initialPrompt = ""
  }
}

struct CoderSessionRow: View {
  @Environment(AppSettings.self) private var settings
  let record: CoderSessionRecord
  let runtime: CoderStore.SessionRuntime

  var body: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(runtime.alive ? .green : .gray.opacity(0.5))
        .frame(width: 10, height: 10)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 8) {
          Text(record.repositoryFullName)
            .font(.headline)
            .lineLimit(1)
          if runtime.turnFinished {
            Text(settings.tr(.coderTurnFinished))
              .font(.caption.weight(.medium))
              .foregroundStyle(.blue)
              .padding(.horizontal, 7)
              .padding(.vertical, 2)
              .background(.blue.opacity(0.12), in: Capsule())
          }
        }
        Text(record.path)
          .font(.callout.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
        HStack(spacing: 8) {
          Text(record.tool.displayName)
          Text("·")
          Text(RelativeTime.short(record.createdAt))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.vertical, 4)
  }
}
