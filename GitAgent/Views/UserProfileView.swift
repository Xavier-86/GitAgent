//
//  UserProfileView.swift
//  GitAgent
//

import SwiftUI

/// Signed-in user's profile, embedded in a workspace page on macOS and shown
/// modally on iOS.
struct UserProfileView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(\.isWorkspacePage) private var isWorkspacePage
    @Environment(\.dismiss) private var dismiss

    let user: GitHubUser

    @State private var calendar: ContributionCalendar?
    @State private var calendarFailed = false

    var body: some View {
        Group {
            if isWorkspacePage {
                profileContent
            } else {
                NavigationStack {
                    profileContent
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(settings.tr(.done)) { dismiss() }
                            }
                        }
                }
            }
        }
        .task { await loadCalendar() }
    }

    private var profileContent: some View {
        List {
                Section {
                    HStack(spacing: 16) {
                        AvatarView(url: user.avatarURL, size: 64)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.name ?? user.login)
                                .font(.title2.bold())
                            Text("@\(user.login)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let bio = user.bio, !bio.isEmpty {
                    Section {
                        Text(bio)
                    }
                }

                // Everything the API offers, shown when present.
                Section {
                    if let company = user.company, !company.isEmpty {
                        LabeledContent(settings.tr(.company), value: company)
                    }
                    if let location = user.location, !location.isEmpty {
                        LabeledContent(settings.tr(.location), value: location)
                    }
                    if let blog = user.blog, !blog.isEmpty {
                        LabeledContent(settings.tr(.website), value: blog)
                            .textSelection(.enabled)
                    }
                    if let twitter = user.twitterUsername, !twitter.isEmpty {
                        LabeledContent(settings.tr(.twitter), value: "@\(twitter)")
                    }
                    if let email = user.email, !email.isEmpty {
                        LabeledContent(settings.tr(.email), value: email)
                            .textSelection(.enabled)
                    }
                    if let createdAt = user.createdAt {
                        LabeledContent(settings.tr(.joined),
                                       value: createdAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }

                Section {
                    LabeledContent(settings.tr(.repositories), value: "\(user.publicRepos)")
                    LabeledContent(settings.tr(.gists), value: "\(user.publicGists)")
                    LabeledContent(settings.tr(.followers), value: "\(user.followers)")
                    LabeledContent(settings.tr(.following), value: "\(user.following)")
                }

                if let calendar {
                    Section {
                        ContributionGraphView(calendar: calendar)
                        Text("\(calendar.totalContributions) \(settings.tr(.contributionsLastYear))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(settings.tr(.contributions))
                    }
                } else if !calendarFailed {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } header: {
                        Text(settings.tr(.contributions))
                    }
                }
        }
        .navigationTitle(settings.tr(.profile))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func loadCalendar() async {
        guard let client = auth.client else { return }
        do {
            calendar = try await client.contributionCalendar(username: user.login)
        } catch {
            calendarFailed = true
        }
    }
}

/// The green-square contribution heatmap from GitHub profiles (last year).
private struct ContributionGraphView: View {
    @Environment(\.colorScheme) private var colorScheme
    let calendar: ContributionCalendar

    /// GitHub's contribution colors, level 0…4, per appearance.
    private static let lightColors: [Color] = [
        Color(red: 0.922, green: 0.933, blue: 0.941), // #ebedf0
        Color(red: 0.608, green: 0.914, blue: 0.659), // #9be9a8
        Color(red: 0.251, green: 0.769, blue: 0.388), // #40c463
        Color(red: 0.188, green: 0.631, blue: 0.306), // #30a14e
        Color(red: 0.129, green: 0.431, blue: 0.224), // #216e39
    ]
    private static let darkColors: [Color] = [
        Color(red: 0.086, green: 0.106, blue: 0.133), // #161b22
        Color(red: 0.055, green: 0.267, blue: 0.161), // #0e4429
        Color(red: 0.000, green: 0.427, blue: 0.196), // #006d32
        Color(red: 0.149, green: 0.651, blue: 0.255), // #26a641
        Color(red: 0.224, green: 0.827, blue: 0.325), // #39d353
    ]

    private func color(for level: Int) -> Color {
        let palette = colorScheme == .dark ? Self.darkColors : Self.lightColors
        return palette[max(0, min(4, level))]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(calendar.weeks.indices, id: \.self) { week in
                        VStack(spacing: 3) {
                            ForEach(calendar.weeks[week].indices, id: \.self) { day in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color(for: calendar.weeks[week][day].level))
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .id(week)
                    }
                }
                .padding(.vertical, 4)
            }
            // Start at the most recent week (right edge).
            .onAppear { proxy.scrollTo(calendar.weeks.count - 1, anchor: .trailing) }
        }
    }
}

#Preview {
    UserProfileView(user: GitHubUser(login: "octocat", name: "The Octocat",
                                     avatarURL: nil, bio: "GitHub mascot",
                                     publicRepos: 8, followers: 4000, following: 9))
        .environment(AppSettings())
}
