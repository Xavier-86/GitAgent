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

## Roadmap

- **Agent tool-calling loop** — let the model call GitHub tools (list/read/search files) and iterate on its own
- **Agent write actions** — create branches, commit via the Git Data API, open pull requests — always with user confirmation
- **Local git engine** — operate real working copies on-device, not just the GitHub API
- **LAN device control** — discover trusted devices on the local network and let the agent run git operations on their local repositories

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
