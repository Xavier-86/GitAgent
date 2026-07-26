//
//  ChatReference.swift
//  GitAgent
//

import Foundation

/// A repository / folder / file the user attached to a chat message via @ or /.
struct ChatReference: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case repo, folder, file
    }

    let kind: Kind
    let owner: String
    let repo: String
    let branch: String
    /// Repository-relative path; empty for a whole-repository reference.
    let path: String

    var id: String { "\(kind.rawValue):\(owner)/\(repo)/\(path)" }
    var displayName: String { path.isEmpty ? "\(owner)/\(repo)" : "\(repo)/\(path)" }
    var icon: String {
        switch kind {
        case .repo: return "book.closed"
        case .folder: return "folder"
        case .file: return "doc.text"
        }
    }
}

/// Assembles the prompt sent to the model.
///
/// Template:
/// ```
/// <user text, verbatim>
///
/// ---
/// Referenced content:
///
/// ## Repository owner/name — README
/// <readme>
///
/// ## Folder owner/name/path — README
/// <readme of the folder, when it has one>
///
/// ## File owner/name/path
/// ```
/// <file content>
/// ```
/// ```
enum PromptBuilder {
    /// Guard against oversized files blowing up the context.
    private static let maxSectionLength = 20_000

    static func build(text: String, references: [ChatReference], client: GitHubClient?) async -> String {
        guard let client, !references.isEmpty else { return text }

        var sections: [String] = []
        for reference in references {
            switch reference.kind {
            case .repo:
                // A repository reference contributes its README.
                if let readme = try? await client.readme(owner: reference.owner, repo: reference.repo)?.text {
                    sections.append("## Repository \(reference.owner)/\(reference.repo) — README\n\n\(truncate(readme))")
                }
            case .folder:
                // A folder reference contributes its README, when it has one.
                if let readme = await folderREADME(reference, client: client) {
                    sections.append("## Folder \(reference.owner)/\(reference.repo)/\(reference.path) — README\n\n\(truncate(readme))")
                }
            case .file:
                // A file reference contributes the file itself.
                if let content = try? await client.fileText(owner: reference.owner, repo: reference.repo,
                                                            path: reference.path, ref: reference.branch) {
                    sections.append("## File \(reference.owner)/\(reference.repo)/\(reference.path)\n\n```\n\(truncate(content))\n```")
                }
            }
        }

        guard !sections.isEmpty else { return text }
        return text + "\n\n---\nReferenced content:\n\n" + sections.joined(separator: "\n\n")
    }

    private static func folderREADME(_ reference: ChatReference, client: GitHubClient) async -> String? {
        guard let items = try? await client.contents(owner: reference.owner, repo: reference.repo,
                                                     path: reference.path),
              let readmeItem = items.first(where: {
                  $0.type == .file && $0.isMarkdown && $0.name.lowercased().hasPrefix("readme")
              }) else { return nil }
        return try? await client.fileText(owner: reference.owner, repo: reference.repo,
                                          path: readmeItem.path, ref: reference.branch)
    }

    private static func truncate(_ text: String) -> String {
        guard text.count > maxSectionLength else { return text }
        return String(text.prefix(maxSectionLength)) + "\n… (truncated)"
    }
}
