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
- **Secrets in the Keychain.** Host passwords and app-generated Ed25519 private
  keys are stored via `Auth/KeychainHelper.swift`, keyed by the host's UUID;
  only host/port/user/authentication kind live in UserDefaults (`SSHHostStore`).
- **Host keys use automatic TOFU pinning.** `HostKeyStore` saves the exact
  public key on first contact and rejects every later mismatch. A fingerprint
  confirmation UI is still required before presenting this as strict host
  identity verification.
- **Saved hosts can use another saved host as a jump host.** The target stays
  independently visible and keeps its own Keychain credential and TOFU host key.
  `SSHConnection` opens the first host directly, then uses Citadel
  `direct-tcpip` channels for each later hop. Terminal, repository browsing and
  verification, and RepoLaunch all use the same resolved route. A directly
  reached first hop may use password or key authentication; targets configured
  through a jump host use Ed25519 key authentication.
- **Sessions don't survive app backgrounding** (iOS suspends sockets) —
  leaving the terminal screen disconnects. Long remote tasks belong in
  `tmux`/`nohup` with a dispatch/poll model (future Agent layer concern).

## Files

| File | Role | Status |
|---|---|---|
| `SSHHostConfig.swift` | Saved host model (id/name/host/port/user/auth/jump host) | done |
| `SSHHostStore.swift` | Host list persistence (UserDefaults + Keychain credentials) | done |
| `SSHConnection.swift` | Direct/jump route connection and lifetime ownership | done |
| `SSHEd25519Credential.swift` | App-owned key generation and OpenSSH public-key export | done |
| `SSHTerminalSession.swift` | Connect, PTY shell, stdin write, window resize | done |
| `LocalTerminalSession.swift` | macOS login shell via `forkpty`, scoped-folder lifetime, resize | done |
| `TerminalView.swift` | xterm.js terminal (WKWebView) + byte bridge | done |
| `SSHView.swift` | Local/remote terminal picker, host editor, terminal screen | done |
| `TerminalLaunchCoordinator.swift` | One-shot route from a repository location or deployment to Terminal | done |
| `HostKeyStore.swift` | Exact-key TOFU pinning and changed-key rejection | done (fingerprint confirmation UI pending) |
| Imported/encrypted private keys | Additional public-key auth formats | not started |
| SFTP support | Remote file browsing/transfer (Citadel `openSFTP`) | not started |

## Ed25519 key setup

Each saved host can use either a password or an app-generated Ed25519 key.
The private key is generated on-device and stored only in the system Keychain.
To authorize it on a Mac:

1. Edit the target host, choose **SSH Key**, and select **Generate SSH Key**.
2. Prefer **Copy Setup Command**, then paste and run it in Terminal on the
   target Mac. The command creates `~/.ssh`, avoids adding a duplicate key,
   appends the public key to `authorized_keys`, and fixes both permission modes.
3. Keep the configured jump host selected, save the target host, and connect.

The manual equivalent after **Copy Public Key** is:

```sh
mkdir -p ~/.ssh
chmod 700 ~/.ssh
pbpaste | grep '^ssh-ed25519 ' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

`pbpaste` requires the public key to have reached the Mac clipboard (for
example through Universal Clipboard). A public key may be shared; passwords
and private keys must never be copied into documentation or messages.

## Terminal rendering

Local and SSH shells are rendered by vendored **xterm.js** (`Resources/web/
terminal/`) inside a WKWebView — bytes cross the JS bridge base64-encoded in
both directions, and geometry changes are reported back to the active PTY.
Output arriving before the page is ready is buffered so a fast local shell
does not lose its first prompt. The assets install alongside the Markdown
assets via `WebAssets` in `Rendering/WebMarkdownView.swift`. SSH PTYs request a
`C.UTF-8` locale so remote tools preserve non-ASCII filenames, and the terminal
font stack includes macOS/iOS CJK fallbacks.

## Repository location integration

`Locations/RepositoryLocationVerifier.swift` uses SSH exec channels to verify
remote working trees before they are marked connected:

1. Connect to the saved host with its selected Keychain credential.
2. Resolve the canonical Git root with `git rev-parse`.
3. Parse every GitHub remote and require an exact `owner/repository` match.
4. Run non-interactive `git ls-remote` on the matched remote. Password prompts
   are disabled, SSH connection attempts are bounded, and slow HTTP transfers
   time out instead of leaving the UI waiting forever.
5. Separately make an uncached authenticated GitHub API request so stale URL
   metadata or a cached response cannot produce a green state.

Selecting a connected location or completing a RepoLaunch deployment publishes
a one-shot `TerminalLaunchRequest`.
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
