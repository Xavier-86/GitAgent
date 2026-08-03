# Agent — deployment foundation and planned orchestration

The first Agent component is implemented under `Agent/RepoLaunch/`. It deploys
an arbitrary online Git repository to this Mac or a saved SSH host, executes
explicit setup/build/test command stages, verifies the resulting root/remote/
commit, persists the run log, and turns GitHub-backed deployments into verified
repository locations. Successful runs immediately open the matching local or
SSH Terminal at the verified repository root. This provides the
environment-preparation boundary that the later coding-CLI relay will consume.

**Chosen route: the remote coding CLI is the brain; the app is the face and
the hands.** The app does not re-implement an agent loop for heavy tasks.
It dispatches a natural-language task to a headless coding CLI
(`claude -p --output-format stream-json`, or the Kimi Code equivalent)
running on a Mac/Linux over SSH, parses the NDJSON event stream, and renders
it as chat. Light GitHub-only tasks keep using the in-app tool loop
(see the main README roadmap).

## Decisions (pinned)

- **Protocol: NDJSON events over the SSH exec channel.** One channel per
  task; events map to four card kinds: text, tool call, tool result, error.
  The CLI's session id is kept so conversations can be resumed
  (`claude --resume <id>`).
- **Steering, not forking.** Behavior is shaped from outside the CLI:
  - system-prompt flags at invocation (app identity, user prefs, repo state)
  - `AGENTS.md` / `CLAUDE.md` maintained in the target repo
  - custom skills / slash commands synced from the app
  - hooks for the write-confirmation loop (remote asks → user confirms in-app)
  - tool allow-lists + max turns for mobile safety
- **Optional shim.** A small Python/Node wrapper on the host (around the
  vendor Agent SDK) owns session persistence and permission callbacks, so the
  app speaks one stable JSON-lines protocol even when CLIs change flags.
- **Isolation on the host.** The CLI runs as a dedicated user or in a
  container (Docker/Lima) with only the intended repos mounted.
- **All write actions require in-app user confirmation** — same rule as the
  GitHub-side roadmap.

## Planned contents

| File | Role | Status |
|---|---|---|
| `AgentEvent.swift` | NDJSON event model (text/tool/result/error) | not started |
| `AgentSession.swift` | Task lifecycle: dispatch, stream, resume, cancel | not started |
| `CLIRelay.swift` | Builds headless CLI invocations (flags, prompt, allow-lists) | not started |
| `AgentHost.swift` | Execution target model: saved SSH host + verified working tree | not started |
| `AgentViewModel.swift` | Event stream → chat cards for `Chat/` UI | not started |

## Implemented RepoLaunch contents

| File | Role |
|---|---|
| `RepoLaunchModels.swift` | Deployment request/result/stage/history models |
| `RepoLaunchExecutor.swift` | Shared staged plan with macOS `Process` and Citadel SSH executors |
| `RepoLaunchStore.swift` | Application Support history, active lifecycle, bounded logs |
| `RepoLaunchView.swift` | Deployment entry routing, compact local/SSH form, progress, location registration, Terminal handoff |
| `RepoLaunchHistoryView.swift` | Deployment history navigation, rows, deletion, and persisted log presentation |
