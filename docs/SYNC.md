# Local → Cloud Sync Architecture

This document is the authoritative design for Hoop Shoot's persistence and its
migration to cloud sync. It carries forward the design specified (but never
built) in the original Hoop Shoot League project — README "Phase 9" and
handoff §8 — and **resolves the seven gaps** found when auditing that spec
against its reference implementation (`growthdyn/bball_sim_NEW2026`:
`frontend/src/stores/sync.js` + `backend/app/Http/Controllers/SyncController.php`).

## 1. Model

**Local-first.** The device save under `user://save/` is the source of truth
while playing; the cloud is a mirror for backup and cross-device continuity.
The server is never authoritative mid-session. Anything *competitive*
(a global leaderboard) is the one exception — see §7.

> **Resolved gap 6 (diffs vs snapshots):** the old handoff said "store diffs";
> the old README and the shipped reference both do **whole-part gzipped
> snapshots**. Decision: **whole-part snapshots.** Parts are small (KBs),
> snapshot push/pull is idempotent and trivially recoverable, and the
> reference server (`campaigns/{clientId}/{part}.json.gz` on S3) already
> implements it. Diffing buys nothing at this size.

## 2. Parts

One local JSON file = one wire part, always:

| Part | Local file | Milestone |
|---|---|---|
| `meta` | `user://save/meta.json` | M1 (implemented) |
| `time_trial_scores` | `user://save/time_trial_scores.json` | M1 (implemented) |
| `tuning` | `user://save/tuning.json` | M1 (implemented) — **device-local dev scratchpad, never synced** (tuning-mode flag + flick tunable overrides) |
| `cosmetics` | `user://save/cosmetics.json` | M1 (implemented) — coins + per-kind (hoop/ball) selected & owned cosmetic set ids |
| `campaign` | `user://save/campaign.json` | M2 |
| `liveGames` | `user://save/live_games.json` | M2 |
| `shots_recent` | `user://save/shots_recent.json` | M2 |

`meta` is unsplittable and always pushed **first** — it creates the server row
(reference behavior). The outbox (`user://save/outbox.json`) is bookkeeping,
never synced itself.

## 3. Identity

> **Resolved gap 2 (ids):** the old game used `c${Date.now().toString(36)}`
> campaign ids while the server route enforces `whereUuid`. Decision: **every
> id is UUIDv4 from the first byte written.** `SaveService.uuid4()` generates
> the device `clientId` (in `meta.json`) and every score/campaign doc id.
> Nothing needs migrating when the network layer arrives.

> **Resolved gap 3 (accounts):** M1–M2 run with **anonymous device identity**
> (`clientId` only). The cloud tier (M3+) uses Laravel Sanctum token auth, as
> in the reference; every server row is scoped `user_id + client_id`. Linking
> a device to an account merges by doc-level LWW (see §4) — local docs upload
> under the account, remote docs download, newest `updatedAt` wins per doc.
> Until an account exists, no network calls are made at all.

## 4. Timestamps & merge

> **Resolved gap 1 (no updatedAt anywhere):** every doc and every part carries
> `updatedAt` (ms epoch), stamped by `SaveService` on write. Implemented in M1.

Pull merge is **doc-level last-writer-wins** on `updatedAt`; a part-level
`updatedAt` short-circuits no-op pulls. Per the reference's hard-won details:

- Each part merges **independently** — never cascade a "remote is newer"
  decision from one part to another (partial pushes can pair a fresh `meta`
  with stale sub-parts).
- A failed "list cloud saves" call returns *unknown*, never *empty* — offline
  must never be mistaken for "no cloud data" (reference: `fetchServerCampaigns`
  returns `null`, not `[]`).
- Clock skew: the server echoes its receipt time on push; a client ignores any
  remote `updatedAt` further ahead of server receipt than a small tolerance.
- Explicit escape hatch: a user-invoked "restore from cloud" force-pull that
  clobbers local (reference: `forcePullFromCloud`).

## 5. Dirty tracking & push protocol

> **Resolved gap 4 (no outbox):** `user://save/outbox.json` persists
> `{ dirtyParts: [...], lastSyncAt, lastError }` and is written in the same
> operation as every data write. Implemented in M1 — `SaveService.mark_dirty()`
> / `dirty_parts()` are the seam the M3 network layer drains.

Push (M3+): for each dirty part, `json → gzip → POST
/api/sync/{clientId}/push` (`PackedByteArray.compress(FileAccess.COMPRESSION_GZIP)`
+ `HTTPRequest`), `meta` first; a part leaves the dirty set only on server ack;
failures keep it dirty with exponential backoff. Wire budget ~900 KB per
request (reference constant, stays under 1 MB proxy limits); oversized parts
chunk exactly as the reference does (`_chunks/{part}/{i}` staged server-side).

Triggers (all reference-proven): end of run/match, app focus-out / pause
(`NOTIFICATION_APPLICATION_FOCUS_OUT`, `NOTIFICATION_APPLICATION_PAUSED`),
manual "save to cloud", and a **5-minute cooldown** between event-driven syncs.
Foregrounding the app triggers a pull (cross-device catch-up). No polling.

## 6. Retention & pruning

> **Resolved gap 5 (`shots_recent` unspecified):** local shot logs are pruned
> before snapshotting to **min(last 500 shots, 30 days)**. Full per-shot
> history is a local nicety, never a sync guarantee. (M2 defines the shot-log
> schema; the pruning rule is fixed now so the part name stays honest.)

Server retention: soft-delete with 30-day recovery window (reference:
`add_soft_deletes_to_campaigns_table`).

## 7. Leaderboards

> **Resolved gap 7 (time-trial cloud story):** two separate mechanisms.
> 1. The `time_trial_scores` part syncs like any other part — that is
>    *backup/restore* of the device's local leaderboard, nothing more.
> 2. A **global leaderboard** is a distinct server feature: individual score
>    rows POSTed to a dedicated endpoint, validated and ranked
>    server-side (server-authoritative, per the original handoff §8). The
>    outbox gains a `pendingGlobalSubmissions` list when this ships. Part-sync
>    and leaderboard submission never share a code path.

## 8. What exists today (M1)

- Scoring (`core/match/streak_rules.gd`, applied in `TimeTrial`): a make is 1,
  a swish 2; the rim lights at 5 in a row, and makes 6–7 pay 2, 8–10 pay 3,
  11+ pay 4, a swish always +1 on top. The run record carries `bonus` (points
  above the plain rule) next to `score`/`makes`/`swishes`/`bestStreak`; older
  records without it read as 0. Cold streak: 7 misses in a row ice the rim
  (`SimGeometry.ice`). A clean entry shatters the ice as the ball drops through
  and a swish scores its 2 (a ball that rattles in after a clean entry pays 0); a ball that touched iron first and would drop in is caught
  by the ice instead (`ShotSim` holds it, then pops it out toward the shooter —
  outcome `ICE_CAUGHT`, no points), which also breaks it; three rim hits in
  total break it too (a ball still in flight after the third hit scores
  normally). The run record carries `iced` (times iced over).

- `game/autoload/save_service.gd`: UUIDv4 `clientId` + doc ids, `updatedAt` on
  every doc and part, atomic writes (tmp + rename), file-per-part layout,
  persisted outbox with `mark_dirty`/`dirty_parts`.
- `tests/test_save_service.gd`: id format, ordering, tiebreak, outbox, and
  reload-persistence coverage.
- No network code, by design. M3+ adds only: an HTTP push/pull worker that
  drains the outbox, Sanctum auth, and the server (which already exists in
  reference form and needs only the schema rename).
