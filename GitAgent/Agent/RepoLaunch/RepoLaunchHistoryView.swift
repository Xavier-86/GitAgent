//
//  RepoLaunchHistoryView.swift
//  GitAgent
//
//  Deployment history rows and persisted log presentation.
//

import SwiftUI

struct RepoLaunchHistoryView: View {
  @Environment(AppSettings.self) private var settings
  @Environment(RepoLaunchStore.self) private var deployments

  @State private var showingNewDeployment = false
  @State private var selectedRecord: RepoLaunchRecord?

  var body: some View {
    List(deployments.records) { record in
      Button {
        selectedRecord = record
      } label: {
        RepoLaunchRecordRow(record: record)
      }
      .buttonStyle(.plain)
      .contextMenu {
        Button(role: .destructive) {
          deployments.delete(record.id)
        } label: {
          Label(settings.tr(.delete), systemImage: "trash")
        }
        .disabled(record.status == .running)
      }
    }
    .macTransparentScrollBackground()
    .navigationTitle(settings.tr(.repoLaunch))
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          showingNewDeployment = true
        } label: {
          Image(systemName: "plus")
        }
        .disabled(deployments.activeRecordID != nil)
      }
    }
    .sheet(isPresented: $showingNewDeployment) {
      RepoLaunchForm(repo: nil)
    }
    .sheet(item: $selectedRecord) { record in
      RepoLaunchLogView(record: record)
    }
  }
}

struct RepoLaunchRecordRow: View {
  @Environment(AppSettings.self) private var settings
  let record: RepoLaunchRecord

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: statusIcon)
        .foregroundStyle(statusColor)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 4) {
        Text(record.displayName)
          .font(.headline)
          .lineLimit(1)
        Text(record.destinationPath)
          .font(.callout.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
        HStack(spacing: 8) {
          Text(settings.tr(record.status.localizationKey))
            .foregroundStyle(statusColor)
          if record.status == .running {
            Text("·")
            Text(settings.tr(record.stage.localizationKey))
          }
          Text("·")
          Text(RelativeTime.short(record.startedAt))
        }
        .font(.caption)
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }

  private var statusIcon: String {
    switch record.status {
    case .running: return "arrow.trianglehead.2.clockwise.rotate.90"
    case .succeeded: return "checkmark.circle.fill"
    case .failed: return "xmark.circle.fill"
    case .cancelled: return "stop.circle.fill"
    }
  }

  private var statusColor: Color {
    switch record.status {
    case .running: return .blue
    case .succeeded: return .green
    case .failed: return .red
    case .cancelled: return .orange
    }
  }
}

struct RepoLaunchLogView: View {
  @Environment(AppSettings.self) private var settings
  @Environment(SSHHostStore.self) private var hosts
  @Environment(RepoLaunchStore.self) private var deployments
  @Environment(\.dismiss) private var dismiss

  let record: RepoLaunchRecord

  private var currentRecord: RepoLaunchRecord {
    deployments.records.first { $0.id == record.id } ?? record
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
          GridRow {
            Text(settings.tr(.repositoryURL)).foregroundStyle(.secondary)
            Text(currentRecord.repositoryURL)
              .lineLimit(2)
              .truncationMode(.middle)
              .textSelection(.enabled)
          }
          GridRow {
            Text(settings.tr(.destinationPath)).foregroundStyle(.secondary)
            Text(currentRecord.destinationPath)
              .font(.body.monospaced())
              .lineLimit(2)
              .truncationMode(.middle)
              .textSelection(.enabled)
          }
          if let hostID = currentRecord.hostID,
            let host = hosts.hosts.first(where: { $0.id == hostID })
          {
            GridRow {
              Text(settings.tr(.computer)).foregroundStyle(.secondary)
              Text(host.locationDisplayName)
            }
          }
          if let commit = currentRecord.resolvedCommit {
            GridRow {
              Text(settings.tr(.repoLaunchCommit)).foregroundStyle(.secondary)
              Text(commit).font(.body.monospaced()).textSelection(.enabled)
            }
          }
        }

        Divider()

        ScrollView {
          Text(currentRecord.log.isEmpty ? settings.tr(.deploying) : currentRecord.log)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
      }
      .padding()
      .navigationTitle(currentRecord.displayName)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(settings.tr(.done)) { dismiss() }
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 680, minHeight: 520)
    #endif
  }
}
