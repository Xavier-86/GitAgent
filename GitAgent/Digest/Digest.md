# Digest — daily trending-repo briefing (planned, not implemented)

**Goal:** every day the user gets one technical briefing about hot/trending
repositories, and can react to each item (interested / not interested / save).
Feedback builds a preference profile that personalizes future briefings.

This is a product feature, separate from the `Agent/` orchestration roadmap:
it runs **on-device, with no backend server**. It reuses the existing plumbing
— `API/GitHubClient` for data, `Chat/ChatClient` for LLM narration,
Application Support JSON for persistence, `L10n` for strings.

## Decisions (pinned)

- **No server, no APNs.** Delivery is a scheduled **local notification**
  (`UNUserNotificationCenter`) plus an in-app Digest view. A push server
  would be the project's first backend dependency and would hold user
  preference data off-device — both rejected.
- **On-device generation first.** Collect → rank → narrate runs in the app.
  Offloading narration to the user's SSH host via the `Agent/` relay is a
  later option, not a dependency — a daily-reading feature must not require
  a configured host.
- **GitHub is the only data source initially.** "Trending" has no official
  API; approximate it with authenticated Search queries (created/pushed
  windows, star velocity) via the existing `GitHubClient`. Third-party
  trending scrapers add fragility and ToS risk — do not add one without a
  user-facing setting.
- **Personalization stays simple and inspectable.** A per-topic weight table
  updated by explicit feedback with exponential decay. No embeddings, no
  vector store, no new dependencies. The profile is plain JSON the user can
  reset from Settings.
- **Persistence tiers unchanged.** Digest history, feedback events, and the
  preference profile are non-sensitive → JSON under Application Support.
  LLM keys stay in the Keychain; nothing new goes to UserDefaults except a
  master on/off toggle in `AppSettings`.

## Pipeline

```
collect                rank                   narrate
GitHubClient        topic affinity        ChatClient (one-shot,
 trending candidates  + star velocity  →   streaming into the Digest view)
 + user star graph    + freshness           preference-steered prompt
      │                    │                      │
      └──────────►  DigestIssue (date + [DigestItem])  ──►  DigestView
                                              │
feedback ◄── FeedbackStore ◄── like / dislike / save / tap-through
   │
   ▼
PreferenceProfile (topic weights, exponential decay) ──► steers next run
```

- **Collect.** Candidate repos from Search API windows (e.g. created in the
  last week, pushed today, sorted by stars) plus repos adjacent to the
  user's starred set (same topics/languages). Readmes fetched lazily, only
  for short-listed items (the client already caches text).
- **Rank.** Deterministic score: star velocity + freshness + topic affinity
  from `PreferenceProfile`. The LLM never ranks; it only narrates what the
  ranker selected — keeps personalization debuggable.
- **Narrate.** One `ChatClient.streamChat` call per briefing: system prompt
  carries the user's top interests and disliked topics; items are rendered
  as structured cards, not free prose, so feedback can attach per item.
- **Feedback.** Explicit (interested / not interested / save) on each card,
  plus implicit tap-through into `RepoDetailView`. Each signal updates the
  profile immediately; saved items surface in the digest history.

## Delivery mechanics

- **iOS:** a `BGAppRefreshTask` attempts generation in the background;
  success schedules tomorrow's local notification. If the refresh never
  runs (the common case for rarely-opened apps), the digest is generated on
  next foreground and the notification is scheduled then. The notification
  deep-links into the Digest view.
- **macOS:** no `BGTaskScheduler` — generate on launch and on a daily timer
  while running; same local-notification delivery.
- Notification permission is requested only after the user enables the
  feature in Settings (off by default).

## Data model (Application Support JSON)

| Type | Contents |
|---|---|
| `DigestIssue` | date, `[DigestItem]`, generatedAt, provider/model used |
| `DigestItem` | repoID, fullName, one-line brief, "why picked" reason, tags, rank score |
| `FeedbackEvent` | itemID, signal (like/dislike/save/tap), timestamp |
| `PreferenceProfile` | topic weights, language weights, dismissed repoIDs, last-updated; EMA decay so old signals fade |

Files: `digest-issues.json`, `digest-feedback.json`,
`digest-preferences.json` alongside the existing stores.

## Phased plan

### Phase 1 — Static daily digest (no personalization)

- [ ] `Digest/DigestModels.swift` — types above, Codable.
- [ ] `Digest/TrendingCollector.swift` — candidate queries + short-listing;
      extends `GitHubClient` only with what it lacks (topic search).
- [ ] `Digest/DigestGenerator.swift` — fixed prompt → `ChatClient` → issue.
- [ ] `Digest/DigestStore.swift` — issue history, load/save.
- [ ] `Digest/DigestView.swift` — briefing list + item cards, deep link to
      `RepoDetailView`; strings via `L10n`.

Done when: opening the Digest tab generates and shows today's briefing from
live GitHub data.

### Phase 2 — Feedback loop and personalization

- [ ] Interested / not-interested / save controls on each card.
- [ ] `Digest/FeedbackStore.swift` — event log.
- [ ] `Digest/PreferenceProfile.swift` — weight table + decay; prompt
      steering in `DigestGenerator`; affinity term in ranking.
- [ ] Settings: view/reset preference profile; master toggle in
      `AppSettings`.

Done when: disliking a topic measurably removes it from subsequent
briefings; liking one brings more of it.

### Phase 3 — Daily push

- [ ] `Digest/DigestNotificationScheduler.swift` — local notifications,
      permission flow, deep link.
- [ ] iOS `BGAppRefreshTask` registration (`INFOPLIST_KEY_` build settings,
      no Info.plist); macOS launch/timer generation.

Done when: an enabled user receives one local notification per day that
opens a fresh personalized briefing.

### Phase 4 — Polish (optional)

- Saved-items list; share sheet; "more like this" on a card.
- Host-side generation through the `Agent/` relay for users who want a
  heavier model than the on-device provider.
- Additional sources (e.g. Hacker News) behind per-source settings.

## File plan

| File | Role | Phase | Status |
|---|---|---|---|
| `Digest/DigestModels.swift` | Issue/item/feedback/profile types | 1 | not started |
| `Digest/TrendingCollector.swift` | Candidate collection + deterministic ranking | 1 | not started |
| `Digest/DigestGenerator.swift` | LLM narration via `ChatClient` | 1 | not started |
| `Digest/DigestStore.swift` | Issue history persistence | 1 | not started |
| `Digest/DigestView.swift` | Briefing UI + item cards | 1 | not started |
| `Digest/FeedbackStore.swift` | Feedback event log | 2 | not started |
| `Digest/PreferenceProfile.swift` | Topic weights, decay, prompt steering | 2 | not started |
| `Digest/DigestNotificationScheduler.swift` | Local notifications + background refresh | 3 | not started |

## Risks and open questions

- **Trending approximation quality.** Search-window heuristics drift from
  github.com/trending; validate Phase 1 output by eye before investing in
  personalization.
- **Rate limits.** Authenticated Search allows ~30 req/min; keep the
  collector to a handful of queries per day and reuse the client's caches.
- **LLM cost and absence.** No configured provider → skip narration and show
  ranked items with raw metadata (digest still works, just less readable).
- **Cold start.** An empty profile ranks by velocity + freshness only;
  first-run onboarding could ask for 3–5 interest topics, but only if Phase
  2 shows cold-start quality is actually a problem.
- **Feedback honesty.** Implicit dwell/tap signals are noisy; weight
  explicit feedback an order of magnitude higher, and never let a single
  accidental tap dominate the profile.
