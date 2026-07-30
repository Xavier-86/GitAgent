# Terminal and SSH transport layer

SSH is GitAgent's **only remote-execution transport**. There is no daemon and no
listening port anywhere: the target Mac/Linux just runs its stock `sshd`
(macOS: System Settings → Sharing → Remote Login), and the app opens an exec
channel per task. macOS also has a native local interactive terminal for
user-selected working trees; it does not use SSH or require Remote Login.

## Decisions (pinned)

- **SSH remains the remote and planned agent transport.** iOS uses SSH to
  reach Mac/Linux, and macOS uses SSH for other hosts. The macOS Terminal UI
  additionally offers a native login shell backed by `forkpty`; this is an
  interactive local terminal, not the planned headless Agent/CLI relay.
- **Local access is unsandboxed.** A local repository is selected with
  `NSOpenPanel` and persisted as a security-scoped bookmark. The app ships
  without the App Sandbox (a sandboxed child shell cannot read the user's
  dotfiles or execute tools outside the container, e.g. Homebrew), so the
  local shell has the same file-system access as Terminal.app.
- **Library: Citadel (swift-nio-ssh)** — async/await, exec channels, PTY
  shells, SFTP. Added as a Swift Package (with `NIO`/`NIOSSH` product
  dependencies for buffer/PTY types). Note: Citadel 0.12.x resolves
  swift-nio-ssh from the `Wellz26/swift-nio-ssh` fork — the package
  reference in the Xcode project intentionally points at the same URL.
- **Secrets in the Keychain.** Host passwords are stored via
  `Auth/KeychainHelper.swift`, keyed by the host's UUID; only host/port/user
  live in UserDefaults (`SSHHostStore`).
- **Host key verification: TODO.** Connections currently use
  `.acceptAnything()` — do not ship this silently; implement TOFU with a
  fingerprint confirmation UI (`HostKeyStore`) before calling this secure.
- **Sessions don't survive app backgrounding** (iOS suspends sockets) —
  leaving the terminal screen disconnects. Long remote tasks belong in
  `tmux`/`nohup` with a dispatch/poll model (future Agent layer concern).

## Files

| File | Role | Status |
|---|---|---|
| `SSHHostConfig.swift` | Saved host model (id/name/host/port/user) | done |
| `SSHHostStore.swift` | Host list persistence (UserDefaults + Keychain passwords) | done |
| `SSHTerminalSession.swift` | Connect (password auth), PTY shell, stdin write, window resize | done |
| `LocalTerminalSession.swift` | macOS login shell via `forkpty`, scoped-folder lifetime, resize | done |
| `TerminalView.swift` | xterm.js terminal (WKWebView) + byte bridge | done |
| `SSHView.swift` | Local/remote terminal picker, host editor, terminal screen | done |
| `TerminalLaunchCoordinator.swift` | One-shot route from a repository location to Terminal | done |
| `HostKeyStore.swift` | Known-hosts fingerprints + TOFU verification | not started |
| `SSHKeyManager.swift` | Public-key auth (generate/import keys) | not started |
| SFTP support | Remote file browsing/transfer (Citadel `openSFTP`) | not started |

## Terminal rendering

Local and SSH shells are rendered by vendored **xterm.js** (`Resources/web/
terminal/`) inside a WKWebView — bytes cross the JS bridge base64-encoded in
both directions, and geometry changes are reported back to the active PTY.
Output arriving before the page is ready is buffered so a fast local shell
does not lose its first prompt. The assets install alongside the Markdown
assets via `WebAssets` (version 10) in `Rendering/WebMarkdownView.swift`.

## Repository location integration

`Locations/RepositoryLocationVerifier.swift` uses SSH exec channels to verify
remote working trees before they are marked connected:

1. Connect to the saved host with its Keychain password.
2. Resolve the canonical Git root with `git rev-parse`.
3. Parse every GitHub remote and require an exact `owner/repository` match.
4. Run non-interactive `git ls-remote` on the matched remote. Password prompts
   are disabled, SSH connection attempts are bounded, and slow HTTP transfers
   time out instead of leaving the UI waiting forever.
5. Separately make an uncached authenticated GitHub API request so stale URL
   metadata or a cached response cannot produce a green state.

Selecting a connected location publishes a one-shot `TerminalLaunchRequest`.
`MainView` switches to Terminal and `SSHView` chooses the requested transport.
Remote locations connect through their configured SSH host, then
`SSHTerminalSession` sends a shell-quoted `cd` after its PTY writer exists.
Direct macOS locations start `LocalTerminalSession`, retain their bookmark,
and send the same shell-quoted `cd` after the local PTY exists. Retry preserves
the requested host, directory, and bookmark.

On macOS, direct local folders use security-scoped bookmarks and read Git
metadata without spawning a process. Their online check proves that the
configured GitHub repository is reachable by the signed-in GitHub account, but
it does not prove that the Mac's command-line Git credentials can fetch.
The native local terminal can run ordinary shell commands with the user's
full file-system rights, while repository verification deliberately remains a
process-free metadata check.

## iOS integration notes

- The **Local Network** permission prompt is declared via
  `INFOPLIST_KEY_NSLocalNetworkUsageDescription` in the target build settings
  (`GENERATE_INFOPLIST_FILE = YES`, so there is no Info.plist to edit).
- Optional Bonjour discovery of `_ssh._tcp` later; manual host entry first.
