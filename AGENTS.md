# GitAgent — Agent Guide

## Project overview

GitAgent is a native **SwiftUI app for iOS and macOS** (single Xcode target; Swift Packages: Citadel + swift-nio for the SSH layer). The long-term vision is a git-oriented AI agent that operates repositories on the local machine, on other LAN devices, or on GitHub — driven by natural language. Today's codebase is the foundation: a GitHub client with OAuth Device Flow sign-in, repository/file browsing with full Markdown rendering, a contribution-graph profile view, a wired-in multi-provider AI chat, and an SSH remote terminal (saved hosts, password auth, xterm.js shell).

- Language: Swift (SWIFT_VERSION = 5.0), SwiftUI with the Observation framework (`@Observable`)
- Toolchain: Xcode 26+; deployment targets iOS 26.2, macOS 15.7
- App Sandbox is enabled on macOS with the network-client entitlement only (`GitAgent/GitAgent.entitlements`)
- License: GPL-3.0 (`LICENSE`)
- App UI and all code comments are **English-only** — write comments and docs in English

## Build and test commands

There is **no test target** and no CI. Verification is "it builds and runs in Xcode."

- Build/run: open `GitAgent.xcodeproj` in Xcode, select **My Mac** or an iPhone simulator, ⌘R
- Command line: `xcodebuild -project GitAgent.xcodeproj -scheme GitAgent -configuration Debug build`
  (code-signing settings come from the xcconfig chain described below, so unsigned CI-style builds may need extra flags)
- Prerequisite secrets (see README "Setup"): the app compiles without them, but GitHub sign-in requires the OAuth Client ID in `GitAgent/Auth/LocalSecrets.swift`, and device builds need an Apple team ID in `Local.xcconfig`

## Configuration files

- `GitAgent.xcodeproj/project.pbxproj` — single native target `GitAgent`; all build settings are generated/embedded here. `GENERATE_INFOPLIST_FILE = YES` (no Info.plist).
- `Build.xcconfig` (tracked) — shared build settings; only does `#include? "Local.xcconfig"`. Never put personal data here.
- `Local.xcconfig` (gitignored) — per-machine Apple signing values (`DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY`).
- `GitAgent/Auth/LocalSecrets.swift` (gitignored) — GitHub OAuth App Client ID, as `enum GitAgentSecrets { static let clientID = "..." }`.
- `.gitignore` already excludes `Local.xcconfig` and `LocalSecrets.swift` — keep it that way; never commit personal account values or secrets.

## Code organization

All Swift sources live under `GitAgent/`, grouped by concern (folder ≈ layer):

- `GitAgentApp.swift` / `ContentView.swift` — entry point; creates `GitHubAuthManager`, `AppSettings`, `ChatStore` and injects them via `.environment(...)`.
- `Auth/` — GitHub OAuth Device Flow (`GitHubAuthManager`), endpoints (`GitHubConfig`), `KeychainHelper` (generic SecItem wrapper).
- `API/` — `GitHubClient` (REST + GraphQL wrapper with in-memory image/text caches) and `Models.swift` (Codable DTOs).
- `Chat/` — `ChatClient` (streaming: OpenAI Chat Completions protocol for all providers, Anthropic Messages API for Anthropic), `ChatStore` (multi-session history persisted as JSON in Application Support), `ChatView`/`ChatComposer`/`MarkdownBubbleView` (UI), `ChatReference` (@ repo / file-folder references + prompt template).
- `Views/` — screens: login, main navigation, repo list/search, repo detail, file browser/viewers, user profile, in-app web viewer, settings.
- `Rendering/WebMarkdownView.swift` — WKWebView-based Markdown renderer with link routing.
- `Settings/` — `AppSettings` (UserDefaults-backed, `@Observable`) and `Localization.swift` (`L10n` enum string table).
- `Utilities/` — cross-platform (`#if os(macOS)`) helpers, authenticated avatar loading.
- `SSH/` — SSH transport, the **only** remote-execution channel: `SSHTerminalSession` (Citadel connect + PTY shell), `SSHHostConfig`/`SSHHostStore` (hosts in UserDefaults, passwords in Keychain), `TerminalView` (xterm.js WKWebView bridge), `SSHView` (host list/editor/terminal). Used by iOS for LAN Mac/Linux and by macOS for localhost and remote hosts alike. Design notes and pending work (TOFU host keys, public-key auth, SFTP) in `SSH/SSH.md`.
- `Agent/` — (planned, design doc `Agent.md` only) agent orchestration: dispatches tasks to a headless coding CLI (`claude`, Kimi Code) over SSH, parses the NDJSON event stream into chat cards. The remote CLI is the brain; behavior is steered via system prompts, `AGENTS.md`/`CLAUDE.md`, skills, hooks, and tool allow-lists.
- `Resources/web/` — vendored JS/CSS/fonts (markdown-it, KaTeX, highlight.js, github-markdown CSS) bundled with the app.

## Architecture conventions

- **State:** plain `@Observable` classes injected through the SwiftUI environment (`@Environment`), not singletons or an external store.
- **Persistence tiers, strictly enforced:**
  - Secrets (GitHub OAuth token, LLM API keys) → **system Keychain only**, always user-entered, never bundled or hardcoded.
  - App settings (font sizes, provider, base URL, model) → UserDefaults.
  - Chat sessions and installed web assets → JSON/files under Application Support.
- **Navigation:** iPhone uses a single `NavigationStack` deliberately — do not switch to a collapsed split view on iPhone (it pops two levels per back swipe).
- **Web assets:** `Resources/web/` is installed to Application Support on first launch. When you change anything under `Resources/web/`, bump `WebAssets.version` in `Rendering/WebMarkdownView.swift` (currently `9`) to force re-installation. Note the file-system-synchronized group flattens resources into the bundle root — two files with the same basename anywhere under `GitAgent/` collide at build time.
- **UI strings:** add user-facing text to `L10n` in `Settings/Localization.swift`, not inline literals.
- **Provider support:** new LLM providers extend the `ChatProvider` enum in `Chat/ChatClient.swift` (display name, default base URL, default model); all non-Anthropic providers must speak the OpenAI Chat Completions protocol.
- Keep platform differences in `#if os(macOS)` / `#if os(iOS)` blocks, following `Utilities/PlatformHelpers.swift`.

## Security considerations

- Never commit `Local.xcconfig`, `LocalSecrets.swift`, or any token/API key — the whole config design exists to keep personal values out of git.
- Do not store credentials anywhere but the Keychain (`Auth/KeychainHelper.swift`); UserDefaults and Application Support are for non-sensitive data only. SSH host passwords follow the same rule (keyed by host UUID).
- GitHub auth uses OAuth Device Flow precisely so no client secret is needed — do not introduce one.
- WKWebView content is rendered from bundled assets and API data; keep link routing inside the app (`WebMarkdownView`, `WebPageView`) rather than opening arbitrary URLs in an uncontrolled context.

## Where things are headed (README roadmap)

Chosen route: **the remote coding CLI is the brain, SSH is the only transport** — iOS SSH-es to a Mac/Linux running headless `claude`/Kimi Code; macOS uses the same SSH path (localhost for itself, LAN hosts for others). Build order: `SSH/` transport → `Agent/` orchestration → remote CLI relay → confirmation/safety loop → GitHub write actions (Git Data API) → libgit2 local engine (deferred). Keep new code compatible with that direction, but do not build these features unless asked.
