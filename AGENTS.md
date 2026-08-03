# GitAgent — Agent Guide

## Project overview

GitAgent is a native **SwiftUI app for iOS and macOS** (single Xcode target; Swift Packages: Citadel + swift-nio for the SSH layer). The long-term vision is a git-oriented AI agent that operates repositories on the local machine, on other LAN devices, or on GitHub — driven by natural language. Today's codebase is the foundation: a GitHub client with OAuth Device Flow sign-in, repository/file browsing with full Markdown rendering, a contribution-graph profile view, a wired-in multi-provider AI chat, a terminal layer (SSH remote shells via xterm.js plus a native local shell on macOS), repository locations that link GitHub repos to verified local/SSH working trees, and a Swift-native RepoLaunch deployment layer for cloning and preparing repositories locally or over SSH.

- Language: Swift (SWIFT_VERSION = 5.0), SwiftUI with the Observation framework (`@Observable`)
- Toolchain: Xcode 26+; deployment targets iOS 26.2, macOS 15.7
- App Sandbox is **disabled** on macOS (`ENABLE_APP_SANDBOX = NO` in the pbxproj — with `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = YES` this build setting, not the entitlements file, controls the injected sandbox entitlement; `GitAgent/GitAgent.entitlements` stays intentionally empty): a sandboxed child shell cannot read the user's dotfiles or run tools outside the container (Homebrew, conda), so a sandboxed local terminal could never behave like Terminal.app. Folders are still picked via `NSOpenPanel` and persisted as security-scoped bookmarks.
- License: GPL-3.0 (`LICENSE`)
- App UI and all code comments are **English-only** — write comments and docs in English

## Build and test commands

There is **no test target** and no CI. Verification is "it builds and runs in Xcode."

- Build/run: open `GitAgent.xcodeproj` in Xcode, select **My Mac** or an iPhone simulator, ⌘R
- Command line: `xcodebuild -project GitAgent.xcodeproj -scheme GitAgent -configuration Debug build`
  (code-signing settings come from the xcconfig chain described below, so unsigned CI-style builds may need extra flags)
- Prerequisite secrets (see README "Setup"): the app compiles without them, but GitHub sign-in requires the OAuth Client ID in `GitAgent/Auth/LocalSecrets.swift`, and device builds need an Apple team ID in `Local.xcconfig`

## Configuration files

- `GitAgent.xcodeproj/project.pbxproj` — single native target `GitAgent`; all build settings are generated/embedded here. `GENERATE_INFOPLIST_FILE = YES` (no Info.plist; the iOS Local Network permission string is set via `INFOPLIST_KEY_NSLocalNetworkUsageDescription` in build settings).
- `Build.xcconfig` (tracked) — shared build settings; only does `#include? "Local.xcconfig"`. Never put personal data here.
- `Local.xcconfig` (gitignored) — per-machine Apple signing values (`DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY`).
- `GitAgent/Auth/LocalSecrets.swift` (gitignored) — GitHub OAuth App Client ID, as `enum GitAgentSecrets { static let clientID = "..." }`.
- `.gitignore` excludes `Local.xcconfig` and `LocalSecrets.swift` — keep it that way; never commit personal account values or secrets. Note it re-includes `GitAgent.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` — the app's dependency pins (Citadel 0.12.1 etc.) are committed on purpose.
- SSH dependency note: Citadel 0.12.x resolves swift-nio-ssh from the `Wellz26/swift-nio-ssh` fork; the Xcode package reference intentionally points at the same URL (details in `GitAgent/SSH/SSH.md`).

## Code organization

All Swift sources live under `GitAgent/`, grouped by concern (folder ≈ layer):

- `GitAgentApp.swift` / `ContentView.swift` — entry point; creates `GitHubAuthManager`, `AppSettings`, `ChatStore`, `SSHHostStore`, `RepositoryLocationStore`, `RepoLaunchStore`, `TerminalLaunchCoordinator` and injects them via `.environment(...)`.
- `Auth/` — GitHub OAuth Device Flow (`GitHubAuthManager`), endpoints (`GitHubConfig`), `KeychainHelper` (generic SecItem wrapper).
- `API/` — `GitHubClient` (REST + GraphQL wrapper with in-memory image/text caches) and `Models.swift` (Codable DTOs).
- `Chat/` — `ChatClient` (streaming: OpenAI Chat Completions protocol for all providers, Anthropic Messages API for Anthropic), `ChatStore` (multi-session history persisted as JSON in Application Support), `ChatView`/`ChatComposer`/`MarkdownBubbleView` (UI), `ChatReference` (@ repo / file-folder references + prompt template).
- `Views/` — screens: login, main navigation, repo list/search (with per-repo Terminal location status), repo detail, file browser/viewers, user profile, in-app web viewer, settings.
- `Locations/` — repository locations: `RepositoryLocation`/`RepositoryLocationStore` (GitHub repo ↔ working-tree links persisted as JSON in Application Support, macOS folder access as security-scoped bookmarks), `RepositoryLocationVerifier` (local: process-free Git metadata + remote match + uncached GitHub API probe; SSH: exec channels running `git rev-parse`/`git ls-remote` on the host), `RepositoryLocationsView` (list/verify/delete/open), and `AddRepositoryLocationView` (link an existing local/SSH working tree).
- `Agent/RepoLaunch/` — Swift-native repository deployment: staged preflight/checkout/setup/build/test/verify workflow, macOS `Process` executor, Citadel SSH executor, Application Support history/log persistence, and separate form/history SwiftUI components. Successful deployments open Terminal at the verified working tree. Explicit setup/build/test commands are user-visible and user-triggered; a later remote coding CLI may propose them.
- `Rendering/WebMarkdownView.swift` — WKWebView-based Markdown renderer with link routing; also owns `WebAssets` (installs bundled web assets to Application Support).
- `Settings/` — `AppSettings` (UserDefaults-backed, `@Observable`) and `Localization.swift` (`L10n` enum string table).
- `Utilities/` — cross-platform (`#if os(macOS)`) helpers, authenticated avatar loading.
- `SSH/` — terminal + SSH transport, the **only** remote-execution channel: `SSHTerminalSession` (Citadel connect + PTY shell), `LocalTerminalSession` (macOS login shell via `forkpty`, bookmark retained for the session), `SSHHostConfig`/`SSHHostStore` (hosts in UserDefaults, passwords in Keychain), `HostKeyStore` (automatic TOFU exact-key pinning), `TerminalView` (xterm.js WKWebView bridge), `TerminalLaunchCoordinator` (one-shot route from a repository location or deployment to the right terminal), `RemoteDirectoryBrowser`/`RemotePathPickerView` (step-by-step SSH directory picker for path-entry forms), `SSHView` (host list/editor/terminal). iOS uses SSH for LAN Mac/Linux; macOS uses SSH for other hosts and the native local shell for itself. Design notes and pending work (fingerprint confirmation UI, public-key auth, SFTP) in `SSH/SSH.md`.
- `Docs/` — design documents for planned features (docs only, no code yet):
  - `Docs/Agent.md` + `Docs/Roadmap.md` — agent orchestration: dispatches tasks to a headless coding CLI (`claude`, Kimi Code) over SSH, parses the NDJSON event stream into chat cards. The remote CLI is the brain; behavior is steered via system prompts, `AGENTS.md`/`CLAUDE.md`, skills, hooks, and tool allow-lists. `Roadmap.md` lays out the GitTaskBench-style direction (natural-language task → remote CLI understands repo, sets up env, executes, delivers a machine-checked artifact) and a top-level `Benchmark/` harness (task definitions, runner, grader — plain Python/JSON, never added to the Xcode target).
  - `Docs/Digest.md` — daily trending-repo briefing: collects hot repos via `GitHubClient`, narrates a one-shot LLM briefing via `ChatClient`, delivers by local notification (no backend, no APNs), and personalizes from explicit per-item feedback (interest weights with decay, resettable from Settings).
- `Resources/web/` — vendored JS/CSS/fonts (markdown-it, KaTeX, highlight.js, github-markdown CSS, xterm.js) bundled with the app.

## Architecture conventions

- **State:** plain `@Observable` classes injected through the SwiftUI environment (`@Environment`), not singletons or an external store.
- **Persistence tiers, strictly enforced:**
  - Secrets (GitHub OAuth token, LLM API keys, SSH host passwords) → **system Keychain only**, always user-entered, never bundled or hardcoded.
  - App settings (font sizes, provider, base URL, model) and SSH host metadata (no passwords) → UserDefaults.
  - Chat sessions, repository locations, RepoLaunch deployment history/logs, and installed web assets → JSON/files under Application Support.
- **Navigation:** iPhone uses a single `NavigationStack` deliberately — do not switch to a collapsed split view on iPhone (it pops two levels per back swipe). iPad/macOS use `NavigationSplitView` (`Views/MainView.swift`).
- **Web assets:** `Resources/web/` is installed to Application Support on first launch. When you change anything under `Resources/web/` (including the terminal assets), bump `WebAssets.version` in `Rendering/WebMarkdownView.swift` (currently `"10"`) to force re-installation. Note the file-system-synchronized group flattens resources into the bundle root — two files with the same basename anywhere under `GitAgent/` collide at build time.
- **UI strings:** add user-facing text to `L10n` in `Settings/Localization.swift`, not inline literals.
- **Provider support:** new LLM providers extend the `ChatProvider` enum in `Chat/ChatClient.swift` (display name, default base URL, default model); all non-Anthropic providers must speak the OpenAI Chat Completions protocol.
- Keep platform differences in `#if os(macOS)` / `#if os(iOS)` blocks, following `Utilities/PlatformHelpers.swift`.

## Security considerations

- Never commit `Local.xcconfig`, `LocalSecrets.swift`, or any token/API key — the whole config design exists to keep personal values out of git.
- Do not store credentials anywhere but the Keychain (`Auth/KeychainHelper.swift`); UserDefaults and Application Support are for non-sensitive data only. SSH host passwords follow the same rule (keyed by host UUID).
- GitHub auth uses OAuth Device Flow precisely so no client secret is needed — do not introduce one.
- SSH connections pin the exact first-use host key and reject changes. Fingerprint confirmation UI remains a known gap tracked in `SSH/SSH.md`; do not describe automatic TOFU as strict identity verification.
- The macOS app is **not sandboxed** (see "Project overview"): the local terminal runs with the signed-in user's full file-system access, exactly like Terminal.app — treat it accordingly before adding agent/execution features on top of it. Folders are picked via `NSOpenPanel` and persisted as security-scoped bookmarks (kept so sandboxing can be re-enabled later).
- WKWebView content is rendered from bundled assets and API data; keep link routing inside the app (`WebMarkdownView`, `WebPageView`) rather than opening arbitrary URLs in an uncontrolled context.

## Where things are headed (README roadmap)

Chosen route: **the remote coding CLI is the brain, SSH is the only transport** — iOS SSH-es to a Mac/Linux running headless `claude`/Kimi Code; macOS uses the same SSH path for other hosts (its native local terminal is an interactive shell, not the planned headless Agent relay). Done so far: `SSH/` transport (basic), `Locations/` repository-location layer (basic), and `Agent/RepoLaunch/` deployment foundation (basic). Next, in build order: Agent task orchestration → remote CLI relay → confirmation/safety loop → GitHub write actions (Git Data API) → libgit2 local engine (deferred). Keep new code compatible with that direction, but do not build these features unless asked.
