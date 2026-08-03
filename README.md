<p align="center">
  <img src="assets/icon.png" width="128" alt="GitAgent icon">
</p>

# GitAgent

> [中文版](README.zh.md)

**A Git-oriented agent that harnesses AI on your iPhone, iPad, or Mac to operate git repositories — local repos on devices across your LAN, or hosted repos online (GitHub).**

Instead of tapping through git UIs or SSH-ing into machines, you tell GitAgent what you want in natural language. The agent plans and executes the git work for you: inspect history, review changes, commit, branch, push — on the machine in front of you, on another device in your local network, or against a remote hosting service.

## Vision

Git is everywhere, but driving it is still manual: every device has its own repos, its own state, its own terminal. GitAgent turns an iOS/macOS device into the control point:

- **Agent-first, not UI-first** — the primary interface is intent ("show me what changed on the office Mac since yesterday", "commit and push the fix on the NAS"), not buttons and menus
- **LAN-wide reach** — discover and operate git repositories on other devices in your local network: check status, pull, commit, resolve routine operations remotely
- **Online repos too** — the same agent drives hosted repositories (GitHub) through their APIs, so local and remote work live in one place
- **Runs where you are** — a native Swift app on iOS and macOS, no cloud relay required for LAN operations

## Where it is today

The current codebase is the foundation the agent is built on — a native GitHub client:

- GitHub sign-in via OAuth Device Flow (in-app browser or system browser, token in the system Keychain)
- Browse your own/private repositories and starred repositories; the Starred list follows when you starred each repository (newest star first), not repository update time
- In-app repository browser: README and file preview with full Markdown rendering, in-document anchor jumps, and link routing that keeps everything inside the app (files, folders, and repos open below the pinned README/Files picker)
- Profile view with the GitHub contribution graph (GraphQL)

**AI Chat is wired in:**

- Multi-provider LLM support — Kimi Code, Moonshot AI, OpenAI, DeepSeek, Anthropic, or any OpenAI-compatible endpoint (Custom). Provider picked from a menu; models fetched automatically from the API
- Multiple chat sessions persisted locally; answers stream in with full Markdown rendering
- **Repository context via @ and /** — type `@` to pick a repository (adds its README to the prompt), then `/` to attach files or folders from it (a folder contributes its README when it has one). The prompt template puts your text first, referenced content after
- API keys are always user-entered and stored in the system Keychain — never bundled

**Local and SSH terminals are in:**

- On macOS, Terminal includes **This Mac** and starts the user's login shell in a native pseudo-terminal; no localhost SSH account or Remote Login setup is required. It matches Terminal.app: dotfiles load, the shell starts in your home directory (or directly in a repository folder), and your full toolchain (Homebrew, conda, …) works — the macOS app is intentionally **not sandboxed**, because a sandboxed child shell gets none of that
- Add a host by pasting its `ssh` command line (e.g. `ssh -o PubkeyAuthentication=no user@host -p 2222`) — user/host/port are parsed out automatically; an optional display name can be set and renamed later
- When `-p` is omitted, GitAgent preserves the command as `ssh user@host` and does not append `:22` or `-p 22` in the editor or host list; the connection still uses SSH's standard default port 22
- Non-default SSH ports must be supplied explicitly with `-p <port>` and are then preserved and displayed
- Passwords go to the system Keychain, one tap on a host row connects
- Local and remote shells share the same in-app xterm.js renderer (vendored, works offline), with terminal resize propagated to the active PTY and momentum touch scrolling on iOS
- iOS/macOS can connect to Mac/Linux SSH hosts across the LAN using a password or an app-generated Ed25519 key; private keys remain in the Keychain, the first presented host key is pinned with TOFU, and every later key change is rejected
- A saved target remains an independent device in the UI while optionally connecting through another saved SSH host (for example iPhone → Linux jump host → Mac); the directly reached jump host may use a password, while the target uses an Ed25519 key

### iPhone → Linux jump host → Mac setup

Use this route when campus or guest Wi-Fi allows both devices to reach a Linux
host but isolates the iPhone from the Mac directly:

1. Save the Linux host in GitAgent and verify that it connects. The first hop
   may use either a password or an SSH key.
2. Save the Mac as a separate host using the Mac's normal LAN address and
   username, then select the saved Linux host under **Jump Host**.
3. The Mac target must use **SSH Key** authentication. Generate its Ed25519 key
   in the host editor and use **Copy Setup Command**, then paste and run that
   command in Terminal on the Mac.
4. Save the Mac host and connect to it normally. GitAgent keeps showing the Mac
   as an independent device while opening the route in the background as
   iPhone → Linux → Mac.

If **Copy Public Key** was used instead, run this manual equivalent on the Mac
after the public key reaches its clipboard (for example through Universal
Clipboard):

```sh
mkdir -p ~/.ssh
chmod 700 ~/.ssh
pbpaste | grep '^ssh-ed25519 ' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

The generated private key never leaves the iOS Keychain. The copied public key
is safe to install on the Mac. Do not copy a login password or private key into
documentation, source control, or messages. More detail is in
[`GitAgent/SSH/SSH.md`](GitAgent/SSH/SSH.md).

**Repository locations are in:**

- Every GitHub repository has a Terminal status button: green means at least one configured working tree passed the current verification rules; red means none has
- A repository can be linked to multiple working trees — folders selected directly on this Mac, or paths on saved Mac/Linux SSH hosts
- macOS folders are chosen through the system folder picker and persisted as security-scoped bookmarks; since the app is not sandboxed this is a convenience for re-opening folders, not a file-access restriction
- Local verification checks the selected directory, Git metadata, and an exact GitHub remote match, then makes an uncached authenticated GitHub API request to prove that the target repository is currently reachable
- SSH verification logs into the selected host, resolves the Git root, checks the remote identity, runs non-interactive `git ls-remote` from that host, and confirms the repository through the GitHub API
- Selecting a connected working tree closes the location sheet, switches to Terminal, and opens the matching local or SSH shell at the repository path (the local shell starts there directly; the SSH shell runs `cd` after its PTY is ready)
- The location sheet keeps three explicit actions: link an existing working tree, deploy another copy with RepoLaunch, or close the sheet
- Direct local locations open the native macOS shell while retaining the folder's security-scoped bookmark for the lifetime of the terminal session; they do not require a saved localhost SSH host
- Local verification reads Git metadata directly and does not run Git, so proving that the Mac's command-line Git credentials can fetch remains separate from the connection check

**RepoLaunch deployment is in:**

- Agent → RepoLaunch accepts any HTTPS/HTTP/SSH/Git clone URL and deploys it either to a folder selected on this Mac or to a path on a saved SSH host
- Deployment is a visible staged workflow: preflight, clone/update + ref checkout, optional setup/build/test commands, and final Git root/remote/commit verification
- Existing working trees are updated only when their `origin` matches and tracked files are clean; RepoLaunch refuses to overwrite local changes
- Output, stage, commit, destination, and failures are persisted under Application Support as deployment history; credential-bearing HTTP URLs are rejected so secrets cannot enter that history
- With no deployment history, RepoLaunch opens directly on the deploy form; optional ref and setup/build/test commands stay under Advanced Options
- A successful deployment registers a GitHub-backed location when applicable, closes the form, switches to Terminal, and starts the local or SSH shell in the deployed repository

## Agent architecture — the chosen route

**The remote coding CLI is the brain; the app is the face and the hands.**
Heavy tasks (compile, test, iterate on a working copy) are dispatched to a
headless coding CLI (`claude`, Kimi Code) running on a Mac/Linux over **SSH**;
the app streams the NDJSON events back into the chat UI. There is no daemon
and no cloud relay — SSH to the target's stock `sshd` is the only remote
transport on iOS and macOS. The native macOS local terminal remains an
interactive shell and is not treated as the future headless Agent relay.
Behavior is steered from outside the CLI: system
prompts, `AGENTS.md`/`CLAUDE.md`, skills, hooks, and tool allow-lists.

What exists vs. what is planned:

| Piece | Status |
|---|---|
| GitHub client foundation (OAuth, repo/file browsing, Markdown) | done |
| Multi-provider streaming chat UI, Keychain credential storage | done |
| `SSH/` — SSH transport (direct/jump connect, password/Ed25519 auth, PTY shell, xterm.js terminal, TOFU host-key pinning, credentials in Keychain) | done (basic); fingerprint confirmation UI and SFTP pending |
| Repository locations — GitHub repo ↔ local/SSH working trees, verification, native local/SSH Terminal deep link | done (basic) |
| `Agent/RepoLaunch/` — local/SSH repository deployment, staged commands, verification, persistent logs | done (basic) |
| `Agent/` — orchestration (NDJSON event model, session/resume, CLI relay) | planned |
| Remote steering (system prompts, AGENTS.md sync, skills, hooks, allow-lists) | planned |
| Long-task survival (remote `tmux` dispatch, reconnect + resume) | planned |
| In-app GitHub tool loop + write actions (Git Data API, with confirmation) | planned, light-task path |
| On-device git engine (libgit2) | deferred — optional offline complement |

Design documents: [Agent layer technical roadmap](GitAgent/Docs/Roadmap.md) (GitTaskBench-style task execution + in-repo benchmark harness) and [Daily digest technical roadmap](GitAgent/Docs/Digest.md) (trending-repo briefing with feedback-driven personalization).

## Roadmap

In build order:

1. ~~**SSH transport layer** (`SSH/`)~~ — done: direct/jump connect, password and app-generated Ed25519 authentication, interactive PTY terminal, credentials in Keychain, and automatic TOFU host-key pinning; fingerprint confirmation UI remains open
2. ~~**Repository location layer** (`Locations/`)~~ — done: associate one or more local/SSH working trees, verify GitHub remotes, and open connected paths in the matching local or SSH Terminal
3. ~~**RepoLaunch deployment foundation** (`Agent/RepoLaunch/`)~~ — done: deploy arbitrary online Git repos locally or over SSH, run explicit staged setup/build/test commands, verify and register the result
4. **Agent orchestration layer** (`Agent/`) — NDJSON event parsing, task sessions, headless CLI invocation with steering flags
5. **Remote CLI relay** — drive `claude` / Kimi Code on Mac/Linux over saved SSH hosts from iOS and macOS
6. **Confirmation + safety loop** — hooks → in-app user confirmation for write actions; host isolation (dedicated user/container)
7. **Agent write actions on GitHub** — branches/commits/PRs via the Git Data API for tasks that don't need a working copy
8. **Local git engine** (libgit2, deferred) — on-device working copies for offline editing

## Requirements

- Xcode 26+
- macOS 15.7+ / iOS 26+

## Setup

The app signs in through GitHub's OAuth Device Flow, which requires your own OAuth App:

1. Go to <https://github.com/settings/developers> → **OAuth Apps** → **New OAuth App**
   (any name; Homepage and Callback URLs can be placeholders)
2. In the app's settings, enable **Device Flow**
3. Create two **gitignored** files with your personal values:

   `Local.xcconfig` at the project root (Apple signing):

   ```
   DEVELOPMENT_TEAM = ABCDEFGHIJ        # your Apple team ID (needed for iOS devices)
   CODE_SIGN_IDENTITY[sdk=macosx*] = Apple Development
   ```

   `GitAgent/Auth/LocalSecrets.swift` (GitHub OAuth):

   ```swift
   enum GitAgentSecrets {
       static let clientID = "Ov23..."  // your OAuth App Client ID
   }
   ```

4. Open `GitAgent.xcodeproj`, select **My Mac** or an iPhone simulator, and run (⌘R)

No client secret is needed — that is the point of the Device Flow. Do not commit a generated secret.

**AI Chat setup (optional):** open Settings → **AI Chat**, pick a provider (Kimi Code, Moonshot AI, OpenAI, DeepSeek, Anthropic, or Custom), and paste your own API key. Base URL and model auto-fill (models are fetched from the API); everything is editable. Keys are stored in the Keychain only.

**Personal data policy:** personal account values (Apple team ID, signing identity,
GitHub OAuth Client ID) live only in the two gitignored files above. The tracked
`Build.xcconfig` includes `Local.xcconfig` via `#include?` and contains no personal data.

## Project structure

```
GitAgent/
├── GitAgentApp.swift         # App entry point
├── ContentView.swift         # Root view (blank while restoring, login, or main)
├── Auth/
│   ├── GitHubConfig.swift    # OAuth Client ID and endpoints
│   ├── GitHubAuthManager.swift  # Device Flow sign-in, token lifecycle
│   └── KeychainHelper.swift  # Keychain storage (GitHub token, LLM API key)
├── API/
│   ├── GitHubClient.swift    # GitHub REST/GraphQL wrapper (+ image/text caches)
│   └── Models.swift          # Codable models
├── Chat/
│   ├── ChatClient.swift      # Multi-provider streaming client (OpenAI-compatible + Anthropic)
│   ├── ChatStore.swift       # Local multi-session chat persistence
│   ├── ChatView.swift        # Chat screen (Markdown-rendered answers, sessions)
│   ├── ChatComposer.swift    # Input bar, @ repo picker, / file picker, chips
│   ├── ChatReference.swift   # Reference model + prompt template
│   └── MarkdownBubbleView.swift # Height-fitting Markdown bubble
├── SSH/
│   ├── SSHTerminalSession.swift # SSH connect (Citadel) + PTY shell session
│   ├── LocalTerminalSession.swift # macOS login shell in a native local PTY
│   ├── SSHHostConfig.swift   # Saved host model (credentials stay in Keychain)
│   ├── SSHHostStore.swift    # Host list, jump routes, credential resolution
│   ├── SSHConnection.swift   # Direct/jump connection chain
│   ├── SSHEd25519Credential.swift # App-owned SSH key generation/export
│   ├── HostKeyStore.swift    # Automatic TOFU exact-key pinning
│   ├── TerminalView.swift    # xterm.js terminal (WKWebView bridge)
│   ├── TerminalLaunchCoordinator.swift # Location/deployment → Terminal routing
│   ├── SSHView.swift         # Host list, host editor, terminal screen
│   └── SSH.md                # SSH layer design notes + pending work
├── Locations/
│   ├── RepositoryLocation.swift # Persisted GitHub repo ↔ working-tree links
│   ├── RepositoryLocationVerifier.swift # Local/SSH Git and remote checks
│   ├── RepositoryLocationsView.swift # List, verify, delete, and open locations
│   └── AddRepositoryLocationView.swift # Link an existing local/SSH working tree
├── Agent/
│   ├── AgentView.swift         # Agent catalog
│   └── RepoLaunch/             # Local/SSH deploy engine, models, history store, form/log UI
├── Docs/                     # Design documents for planned features
│   ├── Agent.md              # (planned Agent layer) Pinned design decisions
│   ├── Roadmap.md            # (planned Agent layer) Phased technical roadmap (GitTaskBench-style + Benchmark/)
│   └── Digest.md             # (planned daily digest) Design + roadmap (feedback-driven personalization)
├── Views/
│   ├── LoginView.swift       # Device-code login (in-app or system browser)
│   ├── MainView.swift        # Single nav stack (iPhone) / split view (iPad, macOS)
│   ├── RepoListView.swift    # Repository lists + Terminal location status
│   ├── RepoDetailView.swift  # README tab + inline link navigation
│   ├── FileContentViews.swift # File browser + file viewers
│   ├── UserProfileView.swift # Profile + contribution graph
│   ├── WebPageView.swift     # In-app web viewer (external links, OAuth page)
│   └── SettingsView.swift    # Settings (UI/Markdown font sizes, LLM provider)
├── Rendering/
│   └── WebMarkdownView.swift # WKWebView Markdown renderer + link routing
├── Settings/
│   ├── AppSettings.swift     # App settings (font sizes, provider, Keychain key)
│   └── Localization.swift    # UI string table
├── Utilities/
│   ├── PlatformHelpers.swift # Cross-platform helpers + swipe-back delegate
│   └── AvatarView.swift      # Authenticated avatar loading
└── Resources/web/            # Bundled JS/CSS/fonts (markdown-it, KaTeX, highlight.js)
```

## Notes

- The macOS app is not sandboxed (`ENABLE_APP_SANDBOX = NO` in the project — with `CODE_SIGN_INJECT_BASE_ENTITLEMENTS`, that build setting controls the injected sandbox entitlement, not the entitlements file). A sandboxed child shell cannot read the user's dotfiles or run tools outside the container, so the local terminal could never match Terminal.app; treat the local shell as having the same power as Terminal.app.
- Rendering assets are bundled in the app and installed to Application Support on first launch. If you update files under `Resources/web/`, bump `WebAssets.version` in `Rendering/WebMarkdownView.swift` to force re-installation.
- The OAuth token and LLM API keys are only ever stored in the system Keychain.
- iPhone uses a single `NavigationStack` instead of a collapsed split view on purpose: the split view runs two competing back-gesture systems and pops two levels per swipe.
