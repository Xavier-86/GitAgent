<p align="center">
  <img src="assets/icon.png" width="128" alt="GitAgent icon">
</p>

# GitAgent

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
- Browse your own/private repositories, global search, view any user's repos
- In-app repository browser: README and file preview with full Markdown rendering, in-document anchor jumps, and link routing that keeps everything inside the app (files, folders, and repos open below the pinned README/Files picker)
- Profile view with the GitHub contribution graph (GraphQL)

**AI Chat is wired in:**

- Multi-provider LLM support — Kimi Code, Moonshot AI, OpenAI, DeepSeek, Anthropic, or any OpenAI-compatible endpoint (Custom). Provider picked from a menu; models fetched automatically from the API
- Multiple chat sessions persisted locally; answers stream in with full Markdown rendering
- **Repository context via @ and /** — type `@` to pick a repository (adds its README to the prompt), then `/` to attach files or folders from it (a folder contributes its README when it has one). The prompt template puts your text first, referenced content after
- API keys are always user-entered and stored in the system Keychain — never bundled

**SSH remote terminal is in:**

- Add a host by pasting its `ssh` command line (e.g. `ssh -o PubkeyAuthentication=no user@host -p 2222`) — user/host/port are parsed out automatically; an optional display name can be set and renamed later
- Passwords go to the system Keychain, one tap on a host row connects
- Interactive remote shell in-app: a real PTY rendered with xterm.js (vendored, works offline), with resize propagation to the remote host
- Same code path drives macOS → localhost and iOS/macOS → any LAN machine; host-key verification (TOFU) is still pending — see `GitAgent/SSH/SSH.md`

## Agent architecture — the chosen route

**The remote coding CLI is the brain; the app is the face and the hands.**
Heavy tasks (compile, test, iterate on a working copy) are dispatched to a
headless coding CLI (`claude`, Kimi Code) running on a Mac/Linux over **SSH**;
the app streams the NDJSON events back into the chat UI. There is no daemon
and no cloud relay — SSH to the target's stock `sshd` is the only transport,
on iOS and macOS alike (macOS drives itself via SSH to `localhost`, so there
is exactly one code path). Behavior is steered from outside the CLI: system
prompts, `AGENTS.md`/`CLAUDE.md`, skills, hooks, and tool allow-lists.

What exists vs. what is planned:

| Piece | Status |
|---|---|
| GitHub client foundation (OAuth, repo/file browsing, Markdown) | done |
| Multi-provider streaming chat UI, Keychain credential storage | done |
| `SSH/` — SSH transport (connect, PTY shell, xterm.js terminal, hosts in UserDefaults, passwords in Keychain) | done (basic); TOFU host keys, public-key auth, SFTP pending |
| `Agent/` — orchestration (NDJSON event model, session/resume, CLI relay) | planned |
| Remote steering (system prompts, AGENTS.md sync, skills, hooks, allow-lists) | planned |
| Long-task survival (remote `tmux` dispatch, reconnect + resume) | planned |
| In-app GitHub tool loop + write actions (Git Data API, with confirmation) | planned, light-task path |
| On-device git engine (libgit2) | deferred — optional offline complement |

## Roadmap

In build order:

1. ~~**SSH transport layer** (`SSH/`)~~ — done: connect, interactive PTY terminal, key-in-Keychain host storage; TOFU host-key verification and public-key auth still open
2. **Agent orchestration layer** (`Agent/`) — NDJSON event parsing, task sessions, headless CLI invocation with steering flags
3. **Remote CLI relay** — drive `claude` / Kimi Code on Mac/Linux from iOS and macOS (macOS includes localhost)
4. **Confirmation + safety loop** — hooks → in-app user confirmation for write actions; host isolation (dedicated user/container)
5. **Agent write actions on GitHub** — branches/commits/PRs via the Git Data API for tasks that don't need a working copy
6. **Local git engine** (libgit2, deferred) — on-device working copies for offline editing

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
│   ├── SSHHostConfig.swift   # Saved host model (passwords stay in Keychain)
│   ├── SSHHostStore.swift    # Host list persistence (UserDefaults)
│   ├── TerminalView.swift    # xterm.js terminal (WKWebView bridge)
│   ├── SSHView.swift         # Host list, host editor, terminal screen
│   └── SSH.md                # SSH layer design notes + pending work
├── Agent/                    # (planned) Agent orchestration — remote CLI as the brain
├── Views/
│   ├── LoginView.swift       # Device-code login (in-app or system browser)
│   ├── MainView.swift        # Single nav stack (iPhone) / split view (iPad, macOS)
│   ├── RepoListView.swift    # Repo lists, search, user lookup
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

- Rendering assets are bundled in the app and installed to Application Support on first launch. If you update files under `Resources/web/`, bump `WebAssets.version` in `Rendering/WebMarkdownView.swift` to force re-installation.
- The OAuth token and LLM API keys are only ever stored in the system Keychain.
- iPhone uses a single `NavigationStack` instead of a collapsed split view on purpose: the split view runs two competing back-gesture systems and pops two levels per swipe.
