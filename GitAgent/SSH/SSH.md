# SSH — transport layer

SSH is GitAgent's **only remote-execution transport**. There is no daemon and no
listening port anywhere: the target Mac/Linux just runs its stock `sshd`
(macOS: System Settings → Sharing → Remote Login), and the app opens an exec
channel per task.

## Decisions (pinned)

- **One transport for everything.** iOS always goes through SSH to reach a
  Mac/Linux. macOS uses the *same* SSH path — `localhost` to drive itself,
  a LAN address for other machines. No separate "local executor" code path.
  (SSH to localhost works inside the App Sandbox: the existing
  network-client entitlement covers outbound connections.)
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
| `TerminalView.swift` | xterm.js terminal (WKWebView) + byte bridge | done |
| `SSHView.swift` | Host list, host editor, terminal screen | done |
| `HostKeyStore.swift` | Known-hosts fingerprints + TOFU verification | not started |
| `SSHKeyManager.swift` | Public-key auth (generate/import keys) | not started |
| SFTP support | Remote file browsing/transfer (Citadel `openSFTP`) | not started |

## Terminal rendering

The interactive shell is rendered by vendored **xterm.js** (`Resources/web/
terminal/`) inside a WKWebView — bytes cross the JS bridge base64-encoded in
both directions, and geometry changes are reported back as PTY window-change
requests. The assets install alongside the Markdown assets via `WebAssets`
(version 8) in `Rendering/WebMarkdownView.swift`.

## iOS integration notes

- The **Local Network** permission prompt is declared via
  `INFOPLIST_KEY_NSLocalNetworkUsageDescription` in the target build settings
  (`GENERATE_INFOPLIST_FILE = YES`, so there is no Info.plist to edit).
- Optional Bonjour discovery of `_ssh._tcp` later; manual host entry first.
