# GitAgent

A GitHub client for macOS and iOS focused on **reading repositories, especially Markdown** — and the future home of an integrated AI agent.

Browse your own (or anyone's) repositories, navigate the file tree, and read Markdown documents rendered with GitHub-grade fidelity — including math formulas, tables, code highlighting, and images. Every link stays inside the app: repositories and files open as native pages, everything else in the built-in web viewer.

## Features

- **GitHub sign-in via OAuth Device Flow** — authorization happens in an in-app page, no password handling, token stored in the system Keychain
- **My repositories** (including private), **global repository search**, and **view any user's public repos**
- **Repository browser** — README shown by default, plus a full file tree with Markdown and plain-text preview
- **Fully in-app navigation** — nothing ever opens the system browser:
  - Links to repositories and files (relative or absolute `github.com` / `raw.githubusercontent.com`) resolve to native in-app pages
  - All other web links open in the built-in web viewer
  - OAuth authorization is completed in-app as well
- **High-fidelity Markdown rendering** powered by markdown-it + KaTeX + highlight.js + github-markdown-css, all bundled locally (works offline, no CDN dependency):
  - Math formulas (`$...$`, `$$...$$`, ` ```math ` blocks) via KaTeX
  - Tables, task lists, code syntax highlighting, blockquotes, images
  - Relative image/link resolution
  - Automatic light/dark mode
- **English UI**

## Roadmap

GitAgent is being evolved into an **agent-powered GitHub client**: an integrated AI agent will be able to explore repositories, answer questions about the code, and assist with reading and understanding projects — all within the same in-app experience.

## Requirements

- Xcode 26+
- macOS 15.7+ / iOS 26+

## Setup

The app signs in through GitHub's OAuth Device Flow, which requires your own OAuth App:

1. Go to <https://github.com/settings/developers> → **OAuth Apps** → **New OAuth App**
   (any name; Homepage and Callback URLs can be placeholders)
2. In the app's settings, enable **Device Flow**
3. Copy the **Client ID** into `GitAgent/Auth/GitHubConfig.swift`:

   ```swift
   static let clientID = "Ov23..."
   ```

4. Open `GitAgent.xcodeproj`, select **My Mac** or an iPhone simulator, and run (⌘R)

No client secret is needed — that is the point of the Device Flow. Do not commit a generated secret.

## Project structure

```
GitAgent/
├── GitAgentApp.swift         # App entry point
├── ContentView.swift         # Root view (login vs. main)
├── Auth/
│   ├── GitHubConfig.swift    # OAuth Client ID and endpoints
│   ├── GitHubAuthManager.swift  # Device Flow sign-in, token lifecycle
│   └── KeychainHelper.swift  # Keychain storage for the access token
├── API/
│   ├── GitHubClient.swift    # GitHub REST API wrapper
│   └── Models.swift          # Codable models
├── Views/
│   ├── LoginView.swift       # Device-code login screen (in-app authorization)
│   ├── MainView.swift        # Split view: sidebar + detail
│   ├── RepoListView.swift    # Repo lists, search, user lookup
│   ├── RepoDetailView.swift  # README + file browser + file viewers + link routing
│   ├── WebPageView.swift     # In-app web viewer (external links, OAuth page)
│   └── SettingsView.swift    # Settings window (reading font size)
├── Rendering/
│   └── WebMarkdownView.swift # WKWebView Markdown renderer + in-app link routing
├── Settings/
│   └── Localization.swift    # UI strings and reading settings
├── Utilities/
│   └── PlatformHelpers.swift # Cross-platform helpers
└── Resources/web/            # Bundled JS/CSS/fonts (markdown-it, KaTeX, highlight.js)
```

## Notes

- Rendering assets are bundled in the app and installed to Application Support on first launch. If you update files under `Resources/web/`, bump `WebAssets.version` in `Rendering/WebMarkdownView.swift` to force re-installation.
- The OAuth token is only ever stored in the system Keychain.
