//
//  AgentView.swift
//  GitAgent
//
//  Entry point for the app's repository agents.
//

import SwiftUI

struct AgentView: View {
  @Environment(AppSettings.self) private var settings
  @Environment(RepoLaunchStore.self) private var deployments
  @Environment(WorkspaceStore.self) private var workspace
  @Environment(\.isWorkspacePage) private var isWorkspacePage

  var body: some View {
    List {
      Section(settings.tr(.availableAgents)) {
        NavigationLink {
          RepoLaunchView(startsWithDeploymentForm: deployments.records.isEmpty)
        } label: {
          HStack(spacing: 14) {
            Image(systemName: "shippingbox.and.arrow.backward")
              .font(.title2)
              .foregroundStyle(.blue)
              .frame(width: 36, height: 36)
              .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
              Text(settings.tr(.repoLaunch))
                .font(.headline)
              Text(settings.tr(.repoLaunchDescription))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 5)
          .contentShape(Rectangle())
        }

        if isWorkspacePage {
          Button {
            workspace.showCoder()
          } label: {
            coderLabel
          }
          .buttonStyle(.plain)
        } else {
          NavigationLink {
            CoderView()
          } label: {
            coderLabel
          }
        }
      }
    }
    .macTransparentScrollBackground()
    .navigationTitle(settings.tr(.agent))
    .onAppear {
      if isWorkspacePage { workspace.updateSelectedTitle(settings.tr(.agent)) }
    }
  }

  private var coderLabel: some View {
    HStack(spacing: 14) {
      Image(systemName: "chevron.left.forwardslash.chevron.right")
        .font(.title2)
        .foregroundStyle(.purple)
        .frame(width: 36, height: 36)
        .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

      VStack(alignment: .leading, spacing: 3) {
        Text(settings.tr(.coder))
          .font(.headline)
        Text(settings.tr(.coderDescription))
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 5)
    .contentShape(Rectangle())
  }
}
