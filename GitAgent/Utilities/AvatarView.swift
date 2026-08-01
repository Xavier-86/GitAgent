//
//  AvatarView.swift
//  GitAgent
//

import CryptoKit
import SwiftUI

/// Two-level avatar cache: in-memory (instant within a session) and on disk
/// under Application Support (instant across launches). The network is always
/// re-fetched — callers show the cached image first and replace it when the
/// download lands, even if the bytes are identical.
private enum AvatarCache {
    #if canImport(UIKit)
    typealias PlatformImage = UIImage
    #elseif canImport(AppKit)
    typealias PlatformImage = NSImage
    #endif

    private static let memory: NSCache<NSURL, PlatformImage> = {
        let cache = NSCache<NSURL, PlatformImage>()
        cache.countLimit = 200
        return cache
    }()

    private static let directory: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appending(path: "AvatarCache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func file(for url: URL) -> URL? {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory?.appending(path: name)
    }

    static func image(of platformImage: PlatformImage) -> Image {
        #if canImport(UIKit)
        return Image(uiImage: platformImage)
        #else
        return Image(nsImage: platformImage)
        #endif
    }

    /// Memory first, then disk (a disk hit is promoted back into memory).
    static func cachedImage(for url: URL) -> Image? {
        if let img = memory.object(forKey: url as NSURL) { return image(of: img) }
        guard let file = file(for: url),
              let data = try? Data(contentsOf: file),
              let img = PlatformImage(data: data) else { return nil }
        memory.setObject(img, forKey: url as NSURL, cost: data.count)
        return image(of: img)
    }

    static func store(_ data: Data, for url: URL) {
        guard let img = PlatformImage(data: data) else { return }
        memory.setObject(img, forKey: url as NSURL, cost: data.count)
        if let file = file(for: url) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

/// GitHub avatar: shows the cached copy immediately, then swaps in the fresh
/// download when it arrives. Auth added for GitHub CDN hosts.
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
        if let cached = AvatarCache.cachedImage(for: url) {
            image = cached
        } else if image != nil {
            // The URL changed to an uncached one — don't keep showing the
            // previous avatar while the new one downloads.
            image = nil
        }

        var request = URLRequest(url: url)
        if let token = auth.client?.token,
           let host = url.host()?.lowercased(),
           host == "github.com" || host.hasSuffix(".githubusercontent.com") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let platformImage = AvatarCache.PlatformImage(data: data) else { return }
        AvatarCache.store(data, for: url)
        image = AvatarCache.image(of: platformImage)
    }
}
