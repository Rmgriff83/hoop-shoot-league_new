# Backend: accounts, leaderboards, and the road to 1v1

The one server Hoop Shoot talks to, and why it costs nothing to run. This
replaces `docs/SYNC.md`'s Laravel plan (its local-first principles survive:
`user://save/` is the truth while playing, the server is a mirror and a
referee, never authoritative mid-session).

## Shape

```
phone ── HTTPS (JSON) ──► Cloudflare Worker (server/, TypeScript, Hono)
                             ├─ D1 (SQLite): players, tt_best, tt_week_best, seen_runs, transfer_codes, rl
                             └─ Durable Objects (phase 3): one MatchRoom per 1v1, WebSocket hibernation
```

The game never reaches a database directly: anything the APK can reach, a
cheater can reach with the same credentials. The Worker is the thin trusted
layer, and on Cloudflare's free plan it is free.

| Piece | Free plan (daily) | Workers Paid ($5/mo flat, monthly) |
|---|---|---|
| Workers requests | 100k | 10M included |
| D1 | 5M row reads, 100k writes, 5 GB | 25B reads, 50M writes |
| Durable Objects | 100k requests, 13k GB-s | 1M requests, 400k GB-s |

A leaderboard run costs two requests (submit, view). A 1v1 match will cost
two WebSocket upgrades plus ~70 incoming messages billed 20:1 — about six
Durable Object requests and at worst ~11 GB-s. No egress billing.

## Identity: anonymous device accounts

No sign-up, no email, no store sign-in. On the first launch the game mints
`playerId` (UUIDv4) and a 32-byte `secret`, stores them in
`user://save/account.json` (`SaveService.ACCOUNT_PART`, never synced) with a
handle drawn from `data/handle_words.json` (`HandleWords`), and
`POST /v1/register`s when the net allows (`Net.ensure_account`). Every later
call carries `Authorization: Bearer <playerId>.<secret>` over TLS; the server
stores SHA-256(secret) and refuses a known id with another secret (403 → the
game mints a fresh identity). Nothing in the repo or the APK is a shared
secret.

- **Handle**: `BRICK BARON 42` — two words and a two-digit tag; editable in
  Settings → PLAYER (`PATCH /v1/me`; 3–24 of A–Z, 0–9, single spaces, no
  blocked word; the server tidies and checks, `HandleWords.valid` mirrors it).
- **Move to a new phone**: Settings → MOVE TO NEW PHONE asks for a one-time
  8-letter code (15 min); ENTER CODE on the new phone claims it with a fresh
  secret and the old secret dies. Phase 2's save mirror makes that restore
  progress too; today it restores identity and the boards.
- **Reinstall**: `export_presets.cfg` `user_data_backup/allow=true`, so
  Android auto-backup brings `user://save/` back on the same Google account.
- **Offline is normal**: registration and every submission wait in the
  outbox and retry on the next foreground; nothing in the game waits on the
  net.

## Scores and boards (phase 1, built)

`App.finish_run` → `Net.queue_run(run)` → `ScorePayload.from_run` (the gate
`why_implausible` runs first; the server's `plausible` is the same rule set in
the same order — `server/src/rules.ts`, `core/net/score_payload.gd`, both
tested) → `SaveService.queue_score` (the outbox's `pendingScores`, capped at
20) → `Net.flush` → `POST /v1/scores`. Accepted, duplicate (`seen_runs`) or
refused-for-good (400) all drop the run from the outbox; anything else backs
off and waits.

- `tt_best` keeps one row per player per area (their best, all time);
  `tt_week_best` one per player per area per week (weeks start Monday UTC,
  `weekOf`). A worse run writes nothing.
- Rank = 1 + rows strictly better (higher score, or the same score played
  earlier) — the same rule as `SaveService.top_scores`.
- `GET /v1/leaderboard?area=beach&period=week|all&limit=50` → `{rows:
  [{rank, name, tag, score, playedAt, me}], me: {rank, score}}`.
- The Ranks page (`RanksPage`, `RanksCopy`, docs/HOME.md → Ranks) is fed by
  `Net.board_loaded` / `board_failed`; a failure shows the device's own board
  (`SaveService.top_scores`) under NO SIGNAL.

## Throttling at every layer

Every request has a budget and a hit degrades to the device board.

1. **Client (`Net`)** — one request in flight per endpoint; registration once
   per launch; `flush` at most every 30 s and only with something pending; a
   board is fetched when the page opens or a tab changes and cached 60 s; a
   transfer code every 10 min; 429 / 5xx / timeouts back off 2, 4, 8 … s
   (±25 % jitter, cap 5 min, `Retry-After` wins — `core/net/backoff.gd`);
   nothing headless or under `-- --no-net`.
2. **Edge** — a per-IP wall in front of every `/v1/*` route: 60 requests a
   minute (`RL_IP`, the Workers Rate Limiting binding; `IP_PER_MINUTE`), answered
   before any handler runs, so bots cannot burn the daily budget. A
   `workers.dev` host has no WAF rules (those attach to a domain on a zone,
   and the account-wide ones are Enterprise); if the API ever moves to a
   domain Ross owns, the zone's one free rate-limiting rule is a bonus layer.
3. **Worker** — per-player buckets: `scores` 6/min (binding) + 120/day (D1),
   `leaderboard` 20/min, `me` 5/min, `register` 5/hour per IP,
   `transfer/code` 3/hour, `transfer/claim` 5/hour per IP. Minute buckets use
   the Workers Rate Limiting binding in production and an in-isolate window
   locally; hour/day windows are D1 counters (`rl`). Bodies ≤ 4 KB, JSON only,
   unknown fields → 400. Kill switches `FEATURE_SUBMIT` / `FEATURE_BOARD` /
   `FEATURE_TRANSFER` (anything but `on` → 503, which the game reads as
   offline).
4. **D1** — indexed queries only, `LIMIT ≤ 50`, rank by one indexed COUNT,
   writes only on improvement; the nightly cron prunes `seen_runs` (30 d),
   dead codes, stale counters and weeks older than eight. Turn on Cloudflare's
   usage notifications at 70 % of each free limit.
5. **Durable Objects (phase 3)** — ≤ 5 incoming messages/s and 2 KB each per
   connection, 30 s heartbeats, one active room per player, rooms close 60 s
   after the result or after 2 min of silence (10 min hard cap), a capped
   matchmaker queue.

Every server limit has a Vitest case (`server/test/api.test.ts`); the client
side is `tests/test_backoff.gd` and `tests/test_account.gd`.

## Running it

```sh
cd server
npm install
npm test                       # Vitest in the Workers runtime, local D1
npm run dev                    # wrangler dev on http://127.0.0.1:8787 (the editor's NetConfig.DEV_URL)
npx wrangler d1 migrations apply hoop_shoot --local
```

First deploy (Ross, once): `npx wrangler login`, `npx wrangler d1 create
hoop_shoot` → paste the id into `wrangler.toml` `[env.production]`,
`npx wrangler d1 migrations apply hoop_shoot --env production --remote`,
`npx wrangler deploy --env production`, then put the printed URL in
`game/net/net_config.gd` `PROD_URL`. Done 2026-10-06: the API lives at
`https://hoop-shoot-api.rmgriffus.workers.dev`. `-- --api=URL` points any
build at any server.

## Phase 2: cloud save mirror (built 2026-10-06)

`docs/SYNC.md`'s part push/pull, on `server/src/save.ts` and `Net.push_save` /
`pull_save`:

- **Wire**: a part is its JSON gzipped whole (`SaveCodec`, pure, tested).
  `GET /v1/save` → the manifest `{parts: {part: {updatedAt, size}}, now}`;
  `GET /v1/save/{part}` → the bytes with `X-Updated-At`; `PUT /v1/save/{part}`
  with `X-Updated-At` stores when newer than what is held, else 409 with the
  held stamp. Cap 256 KB gzipped per part; gzip magic checked; the server never
  reads inside.
- **Parts**: `time_trial_scores, cosmetics, settings, campaign, liveGames,
  cards, progress` (`SaveCodec.SYNC_PARTS`, mirrored in `save.ts`). `account`
  (the secret), `tuning` (a dev scratchpad) and `meta` (the device) never sync.
- **Merge**: part-level last-writer-wins on the part's own `updatedAt`. Two
  phones playing the same account in parallel keep the newer copy of each
  part; the scores part is one list, so a run made on the older copy can lose
  (accepted in SYNC.md).
- **Triggers**: push of dirty parts after a run or a heat (5 min gap), forced
  on focus-out / pause and before a transfer code; pull on launch after
  registration, on focus-in (1 min gap), and forced after a claimed transfer
  code — which is what makes the code restore progress. A 409 on push clears
  the flag and pulls. `App._on_save_pulled` re-reads what it caches
  (settings, cosmetics) and the home page redraws.
- **Throttles**: `RL_SAVE` 30/min per player, `save:day` 400/day in D1,
  `FEATURE_SAVE` kill switch; D1 free storage (5 GB) holds a few thousand
  heavy players (7 parts × ≤ 256 KB, real parts a few KB).
- **Settings → PLAYER** shows `CLOUD SAVE · SAVED 3 MIN AGO` / `2 PARTS
  WAITING` / `OFF` (`Net.cloud_line`).

## Phase 3: live 1v1 league matches

- **Transport**: `WebSocketPeer.connect_to_url("wss://…/v1/match/{room}")`
  polled in `_process`; one `MatchRoom` Durable Object per match (WebSocket
  Hibernation API); a `Matchmaker` object holds the quick-match queue (area +
  level band) and mints 5-letter room codes for playing a friend — the same
  path across the table or across the world.
- **Each side is authoritative over its own shots.** Per shot: `{t: sim_step,
  launch: {angle_deg, speed, vz, backspin, rx, ry, rz, bx, bz}, outcome:
  {type, points, streak, iced}}`. The receiver plays the launch through its
  own `TimeTrial` for the PiP picture (`heat_screen` already renders the
  opponent with the real sim) and takes the scoreboard from the sender's
  outcome; a disagreement flags the match. No rewinds; latency only delays the
  PiP a few hundred ms.
- **Agreement at `start`**: seed (`DetRng.hash_seed(room)`), mode geometry
  (`App.geo_for_mode`), `heat_seconds / ot_seconds / ball_return_s`, the spot
  list, the server start time (3 s countdown). Board motion is a pure function
  of elapsed time; spot shuffles travel as `spot` events. Each side sends
  `period_end {score}`; the room waits for both and decides tie → `ot_start`.
  Disconnect > 10 s after the first 30 s is a forfeit, before it a void.
- **Engine**: `Heat` gets a remote-driven side (no `_bots[AI]`,
  `remote_pickup()` / `remote_release(launch)`); the human opponent fills the
  existing slot as `{id, name, colors.primary}`. Cards: v1 self-only.
