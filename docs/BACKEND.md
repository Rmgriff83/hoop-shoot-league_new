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

## Phase 3: live 1v1 matches (built 2026-10-06)

- **Transport**: `MatchClient` (`game/net/match_client.gd`) holds a
  `WebSocketPeer` to `wss://…/v1/match/room/{id}?area=`, bearer in the
  handshake, polled every frame, outgoing messages gated to 5 a second, a
  ping every 30 s. The room is a `MatchRoom` Durable Object
  (`server/src/match_room.ts`, WebSocket Hibernation); the Worker
  authenticates the upgrade and hands the player on in headers.
- **Matchmaking**: one `Lobby` Durable Object (`server/src/lobby.ts`).
  `POST /v1/match/quick {area}` pairs the next two players in an area into one
  room id (a 60 s wait, `leave` to step out); `POST /v1/match/code {area}`
  mints a 5-letter code (10 min) and `POST /v1/match/join {code}` cashes it,
  so a friend across the table or across the world takes the same path.
- **Protocol** (`core/net/match_protocol.gd`, pure, tested): phone → room
  `shot {n, launch}` on release, `outcome {n, score}` when it lands,
  `period_end {period, score, totals}` at the buzzer, `ping`; room → phone
  `joined {side, area, peer}`, `peer`, `start {seed, area, seconds, ot_seconds,
  ball_return_s}` once both are in (no clocks to agree on: each phone starts
  on receipt, latency apart), relayed messages tagged `from`, `peer_left`,
  `expired`, `pong`. A shot is ~250 bytes; a match is ~60 messages a side.
- **Sync model — each side owns its own shots.** `Heat` with `remote: true`
  (`core/match/heat.gd`) has no bot: their launches replay through the AI
  `TimeTrial` for the picture-in-picture (the same float64 sim, so the same
  arc; shots that arrive before our copy of their clock runs queue), while
  the scoreboard, the period decision and the box score come from their own
  `outcome` / `period_end` messages. Both phones hold the same two
  authoritative scores, so both decide the tie → OT and the winner
  identically; the room records the match when both reports for a period
  differ. A disagreement between the replay and their report flags `desync`
  on the result (recorded on the match). `tests/test_heat_remote.gd` proves a
  seeded bot's run replays to the identical score.
- **Leaving**: a dropped socket tells the other phone `peer_left`; a match 30 s
  in is a forfeit win for them, earlier a void (`Heat.remote_forfeit`). Quitting
  the heat screen closes the room. Rooms that nobody joins expire after 60 s;
  idle rooms after 2 min; every room after 10 min; a finished room closes
  60 s after the decision.
- **Throttles**: `/v1/match/*` 20/min per player + 200/day, `FEATURE_MATCH`
  kill switch; per socket ≤ 5 messages/s and ≤ 2 KB (over → close 1008, which
  counts as leaving).
- **Game**: the home's multiplayer icon opens `MatchLobbyPage` (QUICK MATCH /
  CREATE CODE / ENTER CODE + GO, then the waiting, found and failed states);
  `App.start_online` talks to the Lobby, opens the room and tips off into
  `start_heat` with `MatchProtocol.heat_cfg` (the area's heat mode, the room's
  seed, no cards, the other phone's handle in the opponent slot with a palette
  colour). The post-match header reads `ONLINE MATCH · BEACH` (`MatchCopy`).
  No league, no XP, no cards in v1; opponent-affecting cards would need
  relayed `card` events.
- **Testing without a second phone**: two clients on the same server — the
  phone and the Mac with `-- --api=https://hoop-shoot-api.rmgriffus.workers.dev`,
  or two Mac windows — pair through QUICK MATCH or a code. `--qa-multi` stages
  the lobby and a whole match offline against `QaFakePeer`
  (`tools/qa_fake_peer.gd`), a seeded bot behind the wire.
- **Later**: a ranked ladder from `matches`, rejoin after a drop (the room
  already re-sends `start` to a reconnect), an online card-drop system.

## Cards online (phase 3b, built 2026-10-07)

The same power-up cards as leagues, from an **online-only inventory that
lives on the server** — the save can be edited, the ledger cannot, and the
other phone must trust what hits its rim.

- **Ledger** (`migrations/0004_online_cards.sql`, `server/src/cards.ts`):
  `online_wallet(player_id, coins)`, `online_cards(player_id, card_id, n)`,
  `online_ledger` (buy / reward / play rows, pruned after 90 days), and
  `players.level` — the game's level, reported at register and whenever a
  league match raises it (`Net.report_level` → `PATCH /v1/me {level}`), so
  the card cap holds server-side too. The card list and prices come from
  `data/cards.json`, the payout rule from `data/economy.json` → `online`
  (one data file, two readers).
- **Shop**: `GET /v1/cards` → `{coins, inventory, level}`; `POST
  /v1/cards/buy {id}` → the price from `cards.json`, 400 `level` under the
  card's level (`Progression.can_use` on both sides), 402 `coins` when short.
  `RL_CARDS` 20/min + 200/day, `FEATURE_CARDS` kill switch.
- **The phone's cache**: the `online` bucket in `cards.json` is a read-only
  mirror of the ledger (`Net.refresh_cards` / `_apply_cards`: spares =
  copies owned − the ones in the loadout; a slot the ledger no longer covers
  empties), so every card API and view renders it unchanged. The loadout is
  the phone's; `App.try_buy_card` refuses the online bucket and
  `App.buy_online_card` asks the server instead.
- **Into the room**: the WebSocket upgrade carries `?slots=ice,,fire7`; the
  Worker keeps only what the ledger holds under the level (`validHand`) and
  the room deals both validated hands in `start.hands` (+ `levels`), so each
  tray and each opponent chip row show real cards.
- **A play**: `card {id}` phone → room; the room checks the id is still in
  that side's dealt hand, removes it, decrements `online_cards` (ledger
  `play`), relays `card {from, id}` and echoes `card_ok {id}`; a card not in
  hand → `error {code: card}`. The tray marks the slot `...` until the receipt
  (then `Heat.play_card`, the deal animation), or restores it on a refusal.
  The other phone's `card` lands through `Heat.remote_card` — their ice
  freezes *our* rim in our sim (we own our side and report it), their fire
  or vortex lights our replay of theirs.
- **Payout** (coins only; no card drops, tickets or XP online — Ross will
  design an online drop system later): at the decision the room pays the
  winner `round(win_coins × clamp(1 + upset_per_level × (loser_level −
  winner_level), mult_min, mult_max))` and the loser `loss_coins` flat (50 /
  20, 0.15 per level, 0.5–2.5: level 1 beating 9 → 110, 9 beating 1 → 25,
  even → 50), writes wallets + ledger rows and sends `settled {coins, mult,
  won, reason, wallet}`. A forfeit pays the stayer by the same rule and the
  leaver nothing; a void pays nothing. `Economy.online_coins` is the game's
  copy of the rule (the post-match page's `+110 · ONLINE COINS · WIN ·
  UPSET · X2.2`).
- **Game**: the lobby's card strip (`120 COINS`, the three slots, `CARDS >`)
  opens `CardDeckSheet` on the online bucket — slots (tap to unequip),
  LOADOUT (tap a spare to equip), SHOP (rarity, the level chip gold once
  reached, OWNED, BUY). `--qa-multi` seeds the cache, snaps the deck, and the
  fake peer brings an ice it plays on us.
