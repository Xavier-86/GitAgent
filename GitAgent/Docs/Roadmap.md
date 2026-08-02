# Agent Layer — Technical Roadmap

> [中文版](Roadmap.zh.md)

Direction: bring **GitTaskBench-style capability** into GitAgent — the user
describes a real-world task in natural language; a remote coding CLI
understands the target repository, sets up the environment, executes, and
delivers a verifiable result. The benchmark harness itself also lives in this
repository (task definitions, runner, grader) but is **not compiled into the
app** — it is a host-side evaluation tool.

This document extends the pinned decisions in `Agent.md` (remote CLI is the
brain, SSH is the only transport, NDJSON events over exec channels). It does
not reopen them.

## 1. What GitTaskBench teaches us

[GitTaskBench](https://github.com/QuantaAlpha/GitTaskBench) (NeurIPS 2025
ecosystem, arXiv:2508.18993) evaluates agents on 54 real-world tasks, each
pairing a fixed GitHub repository with an automated, human-curated evaluation
harness. Three lessons drive this design:

1. **The task model is (query + repository + harness).** A task is not a
   prompt; it is a natural-language query, a pinned working tree, and an
   automated pass/fail check. GitAgent already owns the first two-thirds:
   `Chat/` carries the query, `Locations/` pins the verified working tree.
2. **Environment setup is the dominant failure mode.** Over half of agent
   failures in the paper come from dependency resolution and environment
   setup, not from reasoning. The relay must treat environment preparation as
   a first-class, inspectable phase — not an invisible side effect.
3. **Results must be machine-checkable.** Metrics are Execution Completion
   Rate (did it produce a valid output at all) and Task Pass Rate (does the
   output meet task-specific criteria). Delivery in GitAgent therefore ends
   with an artifact + a check, not with a chat message.

Current frontier on the benchmark: OpenHands+Claude 3.7 at 48.15% task pass,
RepoMaster+Claude 3.5 at 62.96% — repository-leveraging tasks are far from
solved, so scope expectations accordingly.

## 2. Target architecture

```
┌───────────────────────── GitAgent app (iOS/macOS) ─────────────────────────┐
│ ChatView ── AgentViewModel ── AgentSession ── CLIRelay                     │
│   cards        events          lifecycle      invocation builder           │
└───────────────────────────────────┬────────────────────────────────────────┘
                                    │ SSH exec channel (Citadel), NDJSON
┌───────────────────────────────────┴────────────────────────── remote host ─┐
│ optional shim (JSON-lines protocol, session persistence, permission cb)    │
│   └── headless coding CLI (claude -p / kimi, stream-json)                │
│         └── verified working tree (RepositoryLocation.path)              │
│               └── task artifacts (output files, logs, patches)           │
└────────────────────────────────────────────────────────────────────────────┘
```

- **Repository anchor:** every agent task binds to a connected
  `RepositoryLocation` (verified working tree, `hostID` selects the SSH host;
  `hostID == nil` is a macOS local tree). No verified location, no task —
  this reuses the existing verification pipeline instead of trusting paths.
- **Transport:** one SSH exec channel per task (per `Agent.md`). Long tasks
  outlive iOS socket suspension via the dispatch/poll model (`tmux`/`nohup`
  on the host, app re-attaches by session id) already noted in `SSH.md`.
- **Steering:** system-prompt flags at invocation (app identity, repo state,
  environment profile), `AGENTS.md` in the target repo, tool allow-lists,
  max-turns caps. Hooks implement the write-confirmation loop.
- **Delivery:** task artifacts are pulled back over SFTP (Citadel `openSFTP`,
  listed as pending in `SSH.md`) and surfaced as result cards with a
  machine-checkable status, mirroring the benchmark's artifact + harness
  model.

## 3. Phased plan

### Phase 0 — Security gate (blocking)

Agent execution multiplies the blast radius of the unsandboxed shell. Per
`AGENTS.md`, do not build agent execution on `.acceptAnything()`.

- [ ] `HostKeyStore.swift` — TOFU host-key verification with fingerprint
      confirmation UI (already planned in `SSH.md`).
- [ ] `SSHKeyManager.swift` — public-key auth; agent tasks should not depend
      on password auth held in memory.
- [ ] Host-side isolation policy documented and enforced in setup flow:
      dedicated user or container (Docker/Lima) with only intended repos
      mounted (pinned in `Agent.md`).

### Phase 1 — Minimal relay (one-shot tasks)

Goal: from a connected repository location, dispatch a natural-language task,
stream progress as chat cards, cancel cleanly.

- [ ] `Agent/AgentEvent.swift` — NDJSON event model: text / tool call /
      tool result / error (+ artifact reference, see Phase 2).
- [ ] `Agent/CLIRelay.swift` — builds the headless invocation: prompt
      assembly, `--output-format stream-json`, allow-lists, max turns,
      working directory from `RepositoryLocation.path`.
- [ ] `Agent/AgentSession.swift` — lifecycle: dispatch, stream, resume via
      CLI session id, cancel; dispatch/poll re-attach after iOS
      backgrounding.
- [ ] `Agent/AgentHost.swift` — execution-target model resolving a
      `RepositoryLocation` to (SSH host, working directory, environment
      profile).
- [ ] `Agent/AgentViewModel.swift` — event stream → four card kinds for
      `Chat/` UI.
- [ ] All write actions gated by in-app user confirmation (same rule as the
      GitHub-side roadmap).

Done when: a task dispatched from iPhone to a Mac host runs to completion in
a verified repo, and the full event stream renders as chat cards.

### Phase 2 — Task-oriented capabilities (the GitTaskBench gap)

Goal: attack the benchmark's dominant failure modes explicitly.

- [ ] **Repository briefing.** Before dispatch, build a repo brief (README
      digest, top-level layout, detected toolchain: python/node/rust,
      dependency manifests) and inject it via system-prompt flags. This is
      the app-side counterpart of Aider's repo map.
- [ ] **Environment profile per location.** Persist a per-location
      environment record (interpreter versions, package manager, setup
      commands that worked). Reuse across tasks; surface setup failures as
      first-class events so the UI can show "failed at environment setup"
      instead of a generic error.
- [ ] **Artifact delivery.** CLI declares output artifacts (files/patches);
      the app pulls them over SFTP, stores them under Application Support,
      and renders result cards with previews.
- [ ] **Machine-checkable results.** A task may carry a check command
      (test script, exit-status or output-matching). The relay runs it after
      completion and reports pass/fail — the same Execution Completion /
      Task Pass split as the benchmark.

Done when: a GitTaskBench-style task (e.g. "extract all emails from this PDF
using this repo, save to output.txt") completes end-to-end with a verified
artifact.

### Phase 3 — Benchmark integration (not compiled into the app)

Goal: the benchmark harness lives in this repository as a host-side tool and
drives the same relay, so GitAgent's own stack is measurable.

Top-level `Benchmark/` directory (outside the Xcode target — plain Python and
JSON, nothing compiled):

```
Benchmark/
├── README.md                 # how to run evaluations
├── tasks/                    # task definitions, GitTaskBench-compatible schema
│   └── <TaskName>_01/
│       ├── query.json        # natural-language task + input files
│       ├── task_info.yaml    # repo pin, output path, evaluation config
│       └── test_script.py    # per-task automated pass/fail check
├── runner/                   # drives tasks through the CLI relay on a host
└── grader/                   # executes test_script.py, aggregates reports
```

- [ ] Adopt GitTaskBench's task schema (`query.json` / `task_info.yaml` /
      `test_script.py`) verbatim, so upstream tasks can be dropped in
      unmodified and our results stay comparable with published numbers.
- [ ] Curate an initial task set in **our** domain — repository management
      (issue reproduction, patch + test, branch/commit hygiene, remote
      deployment) — complementing GitTaskBench's multimedia/document domain.
      Start small: ~10 tasks, each with a fixed repo pin and a strict check.
- [ ] `runner/` speaks to the headless CLI directly (no app in the loop) for
      CI-style runs, using the same prompt assembly and allow-lists as
      `CLIRelay.swift`. The app path and the benchmark path must share one
      invocation definition, or the benchmark measures nothing about the
      product.
- [ ] `grader/` reports Execution Completion Rate and Task Pass Rate per
      task and in aggregate; results are plain JSONL under
      `Benchmark/results/` (gitignored).

Done when: `gittaskbench grade --taskid ...`-equivalent runs locally against
a host, and a full-suite run produces an aggregate report comparable to the
published leaderboard format.

### Phase 4 — Hardening (later)

- Cost control: max turns, per-task token budget, early stop.
- Optional shim for protocol stability across CLI flag changes (`Agent.md`).
- GitHub write actions (Git Data API) once the confirmation loop is proven.
- Concurrent tasks per host; per-host capability matrix.

## 4. File plan (app side)

| File | Role | Phase | Status |
|---|---|---|---|
| `Agent/AgentEvent.swift` | NDJSON event model (text/tool/result/error/artifact) | 1 | not started |
| `Agent/AgentSession.swift` | Task lifecycle: dispatch, stream, resume, cancel | 1 | not started |
| `Agent/CLIRelay.swift` | Headless CLI invocation builder | 1 | not started |
| `Agent/AgentHost.swift` | Execution target: location → host + env profile | 1 | not started |
| `Agent/AgentViewModel.swift` | Event stream → chat cards | 1 | not started |
| `Agent/RepoBrief.swift` | Repository briefing injected into prompts | 2 | not started |
| `Agent/EnvironmentProfile.swift` | Per-location env record + setup reuse | 2 | not started |
| `Agent/ArtifactStore.swift` | SFTP pull + Application Support storage | 2 | not started |
| `Agent/TaskCheck.swift` | Post-run machine check → pass/fail card | 2 | not started |
| `SSH/HostKeyStore.swift` | TOFU host keys | 0 | not started |
| `SSH/SSHKeyManager.swift` | Public-key auth | 0 | not started |
| `SSH/` SFTP support | Remote file transfer for artifacts | 2 | not started |

Non-app: `Benchmark/` (tasks, runner, grader) — Phase 3, never added to the
Xcode target.

## 5. Risks and open questions

- **CLI flag drift.** Vendor CLIs change headless flags; the Phase 1 relay
  pins one CLI version, the Phase 4 shim absorbs drift. Do not abstract
  early.
- **iOS backgrounding.** Dispatch/poll via `tmux` is untested; Phase 1 must
  validate re-attach before any UI polish.
- **Benchmark contamination.** Our curated tasks pin public repos; keep task
  definitions out of the app binary and out of any training-adjacent channel.
- **Safety vs. convenience.** The confirmation loop adds friction to exactly
  the autonomous flow the benchmark rewards. Keep confirmation for writes
  inside the app; the benchmark runner (no app) may run unattended only in
  the isolated Phase 0 environment.
- **Scope discipline.** GitTaskBench shows even the best systems pass ~half
  of repo-leveraging tasks. Phase 2 should ship boring reliability (env
  setup, artifact checks) before any autonomous ambition.
