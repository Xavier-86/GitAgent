//
//  AvatarView.swift
//  GitAgent
//

import SwiftUI

/// GitHub avatar loaded with URLSession (auth added for GitHub CDN hosts) —
/// more reliable than AsyncImage, with a placeholder fallback.
struct AvatarView: View {
    @Environment(GitHubAuthManager.self) private var auth

    let url: URL?
    var size: CGFloat = 36

    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        var request = URLRequest(url: url)
        if let token = auth.client?.token,
           let host = url.host()?.lowercased(),
           host == "github.com" || host.hasSuffix(".githubusercontent.com") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) { image = Image(uiImage: uiImage) }
        #elseif canImport(AppKit)
        if let nsImage = NSImage(data: data) { image = Image(nsImage: nsImage) }
        #endif
    }
}
