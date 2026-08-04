<p align="center">
  <img src="assets/icon.png" width="128" alt="GitAgent icon">
</p>

# GitAgent

> [中文版](README.zh.md)

**A GitHub client with AI chat and built-in terminals — native on iPhone, iPad, and Mac.**

GitAgent is growing into a git-oriented AI agent that operates repositories across your devices. Today it already lets you browse GitHub, chat with LLMs about your code, open local and SSH terminals, link repositories to real working trees, and deploy repositories with a single form.

## Features

**Browse your repositories** — sign in with GitHub OAuth Device Flow (token in the system Keychain); your own, private, and starred repositories, plus a profile view with the contribution graph.

**Read and explore code** — READMEs and files with full Markdown rendering (math, syntax highlighting, anchor jumps); links to files, folders, and repositories all open inside the app.

**Chat with AI about your code** — Kimi Code, Moonshot AI, OpenAI, DeepSeek, Anthropic, or any OpenAI-compatible endpoint, with models fetched automatically; type `@` to reference a repository, then `/` to attach files or folders; streaming Markdown answers, sessions persist locally, API keys stay in the Keychain.

**Terminal — local and SSH** — a native local shell on macOS that behaves like Terminal.app (dotfiles, Homebrew, conda, all of it); add SSH hosts by pasting an `ssh` command line, with password or app-generated Ed25519 key and jump-host support; the same xterm.js terminal on every platform, credentials in the Keychain.

**Link repositories to working trees** — connect a GitHub repository to a folder on this Mac or a path on an SSH host, with automatic verification; opening a connected location drops you into a terminal, right at the repository.

**Deploy with RepoLaunch** — clone any git URL to this Mac or an SSH host through a visible staged workflow (preflight → checkout → setup/build/test → verify); never overwrites local changes; a successful deploy opens a terminal at the new working tree. RepoLaunch is the first agent in the catalog — task-oriented agents that drive a remote coding CLI are planned next.

## A quick tour

### macOS

*After sign-in you land on your repositories — own, private, and starred, with a terminal-status dot on each row.*

<p>
  <img src="assets/mac/homepage.png" width="560" alt="macOS — repository list">
</p>

*Open a repository: the README renders as full Markdown, and the Files tab browses the tree with last-commit info.*

<p>
  <img src="assets/mac/read.png" width="410" alt="macOS — README rendering">
  <img src="assets/mac/files.png" width="410" alt="macOS — file browser">
</p>

*The Chat tab talks to your chosen LLM — type `@` to reference a repository, then `/` to attach files or folders.*

<p>
  <img src="assets/mac/chat.png" width="560" alt="macOS — AI chat">
</p>

*The Terminal tab lists This Mac (a native local shell) and your saved SSH hosts.*

<p>
  <img src="assets/mac/terminal.png" width="270" alt="macOS — terminal hosts">
</p>

*Repository locations link a GitHub repo to a verified working tree — on this Mac or an SSH host.*

<p>
  <img src="assets/mac/local.png" width="420" alt="macOS — repository locations">
</p>

*The Agent catalog: RepoLaunch is the first available agent — it clones and prepares a repository locally or over SSH. More agents are under development.*

<p>
  <img src="assets/mac/agent.png" width="400" alt="macOS — Agent catalog">
  <img src="assets/mac/repo.png" width="400" alt="macOS — RepoLaunch deployment history">
</p>

*Settings: font sizes and the AI chat provider, base URL, and model.*

<p>
  <img src="assets/mac/setting.png" width="340" alt="macOS — settings">
</p>

### iOS

*The same app on iPhone: home with your profile, and the repository list.*

<p>
  <img src="assets/ios/homepage.png" width="200" alt="iOS — home screen">
  <img src="assets/ios/repos.png" width="200" alt="iOS — repository list">
</p>

*README rendering and the file browser, identical to the Mac.*

<p>
  <img src="assets/ios/read.png" width="200" alt="iOS — README rendering">
  <img src="assets/ios/files.png" width="200" alt="iOS — file browser">
</p>

*Terminal hosts — including multi-hop routes ("Via 5090" reaches the Mac through a jump host) — and the Agent catalog with RepoLaunch.*

<p>
  <img src="assets/ios/terminal.png" width="200" alt="iOS — terminal hosts">
  <img src="assets/ios/agent.png" width="200" alt="iOS — Agent catalog">
</p>

*Settings on iOS: font sizes and AI chat configuration.*

<p>
  <img src="assets/ios/setting.png" width="200" alt="iOS — settings">
</p>

## Requirements

- iOS 26+ / macOS 15.7+
- Xcode 26+ to build from source
- `tmux` on any machine that runs RepoLaunch deployments (macOS: `brew install tmux`)

## Setup

GitHub sign-in uses the OAuth Device Flow, which requires your own OAuth App:

1. Go to <https://github.com/settings/developers> → **OAuth Apps** → **New OAuth App** (any name; the URLs can be placeholders), then enable **Device Flow** in the app's settings.
2. Create two **gitignored** files with your personal values:

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

3. Open `GitAgent.xcodeproj`, select **My Mac** or an iPhone simulator, and run (⌘R).

**AI Chat (optional):** open Settings → **AI Chat**, pick a provider, and paste your API key. Base URL and model auto-fill; the key is stored in the Keychain only.

## Documentation

Architecture, roadmap, project structure, and developer notes live in [`GitAgent/Docs/`](GitAgent/Docs/) — start with [Development.md](GitAgent/Docs/Development.md).

## License

GPL-3.0 — see [LICENSE](LICENSE).
