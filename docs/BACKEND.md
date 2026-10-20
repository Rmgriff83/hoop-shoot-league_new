# Backend: accounts, leaderboards, and the road to 1v1

The one server Hoop Shoot talks to, and why it costs nothing to run. This
replaces `docs/SYNC.md`'s Laravel plan (its local-first principles survive:
`user://save/` is the truth while playing, the server is a mirror and a
referee, never authoritative mid-session).

## Shape

```
phone ── HTTPS (JSON) ──► Cloudflare Worker (server/, TypeScript, Hono)
                             ├─ D1 (SQLite): players, player_secrets, player_identities, tt_best, tt_week_best, seen_runs, transfer_codes, rl, save_parts, online_*
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
`POST /v1/register`s when the net allows (`Net.ensure_account`) — since
2026-10-17 only once NEW PLAYER has picked the name (`App.player_created()`;
design 35a), so the register call carries the chosen name; the hometown the
form also asks for is a synced setting, not a server field. Every later
call carries `Authorization: Bearer <playerId>.<secret>` over TLS; the server
stores SHA-256(secret) — since 2026-10-17 one row per device in
`player_secrets` (see Platform identity) — and refuses a known id with a
secret it does not hold (403). On a 403 at registration or a 401 on any
authenticated call the game recovers in this order: a linked, signed-in
platform restores the account (`Net._recover_identity` →
`restore_from_platform`); otherwise it mints a fresh identity. Nothing in the
repo or the APK is a shared secret.

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
   `transfer/code` 3/hour, `transfer/claim` 5/hour per IP, `link` 5/hour,
   `link/restore` 5/hour per IP, `link/<provider>` (unlink) 5/hour,
   `DELETE /v1/me` 3/hour per IP + 2/hour per player. Minute buckets use
   the Workers Rate Limiting binding in production and an in-isolate window
   locally; hour/day windows are D1 counters (`rl`). Bodies ≤ 4 KB, JSON only,
   unknown fields → 400. Kill switches `FEATURE_SUBMIT` / `FEATURE_BOARD` /
   `FEATURE_TRANSFER` / `FEATURE_SAVE` / `FEATURE_MATCH` / `FEATURE_CARDS` /
   `FEATURE_PLATFORM` (anything but `on` → 503, which the game reads as
   offline); account deletion has none.
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
  `period_end {period, score, totals}` at the buzzer, `loadout {slots,
  ready}` in the pre-match pick (→ Ranked), `card {id}`, `rematch`, `ping`;
  room → phone `joined {side, area, peer, status, ranked}`, `peer`, `matched
  {peer, levels, tiers, cap, seconds}` once both are seated, `loadout_ok`,
  `start {seed, area, seconds, ot_seconds, ball_return_s, hands, levels,
  ranked, cap, tiers}` once both are ready or the pick timer runs out (no
  clocks to agree on: each phone starts on receipt, latency apart), relayed
  messages tagged `from`, `card_ok`, `settled`, `rematch_go`, `peer_left`,
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
- **Rematch** (2026-10-07): only on the post-match page, while the finished
  room is still open (it lives 60 s after the decision, another minute per
  offer). `REMATCH?` sends `rematch`; the other phone's card turns gold
  (`THEY WANT A REMATCH · TAP TO ACCEPT`); when both have asked the old room
  mints a fresh room id and sends `rematch_go {room, area}`, each phone opens
  it with its current loadout (revalidated by the Worker) and the new
  `start` tips off. Leaving the page (HOME) closes the socket and the other
  phone's card reads `THEY LEFT`. `App.offer_rematch`, `App.rematch_state`,
  `MatchCopy.rematch_*`.
- **Later**: rejoin after a drop (the room already re-sends `start` to a
  reconnect), an online card-drop system (the ranked ladder landed
  2026-10-19 → Ranked).

- **ANY court (2026-10-17, design 37a):** `POST /v1/match/quick {area: "any",
  areas: [owned courts]}` (and `leave`). The Lobby pairs an any-court player
  with the first waiter on one of their courts, else with another any-court
  player on a court both own (`cage` when none); the reply carries `area`
  (the joiner's court) and the room, created by an any-court host with
  `x-area: any`, takes the court the joiner brings. `areas` is validated
  (unknown court → 400); a code is never "any".
- **The face-off (2026-10-18, design 37a):** the phone sends its hometown on
  the room URL (`&town=`); the room route cleans it (`src/towns.ts`
  `cleanTown`: A–Z, 0–9, single spaces, ≤ 16) and always sets
  `x-player-town`, so the player record — `joined.peer` / `peer.peer` —
  carries `town` ("" when none). The `peer` message also carries the room's
  `area`, so an any-court host learns its court. Needs a Worker deploy; the
  old Worker just sends no town (the card shows the level alone).

## Cards online (phase 3b, built 2026-10-07)

The same power-up cards as leagues, from an **online-only inventory that
lives on the server** — the save can be edited, the ledger cannot, and the
other phone must trust what hits its rim.

- **The rule** (2026-10-19, docs/ECONOMY.md → The rule): **no path from
  real money to online cards, ever.** Ticket packs buy tickets; tickets never
  buy online cards; online cards are never tradeable, giftable or sold;
  drops are never sold. So there is no online shop and no online wallet:
  online cards come only from verified server drops and spoils (next task).
  That keeps "winner takes the played cards" clear of Apple 5.3 / Google
  Play's gambling policy.
- **Ledger** (`migrations/0004_online_cards.sql`, `server/src/cards.ts`):
  `online_cards(player_id, card_id, n)`, `online_ledger` (play rows, pruned
  after 90 days; its `coins` column is history, always 0 now), and
  `players.level` — the game's level, reported at register and whenever a
  league match raises it (`Net.report_level` → `PATCH /v1/me {level}`), so
  the card cap holds server-side too. The card list comes from
  `data/cards.json`. `online_wallet` is dropped by
  `migrations/0006_drop_online_wallet.sql` — before applying it in
  production run `SELECT count(*) FROM online_wallet WHERE coins > 0` and
  stop if real players hold a balance (none expected: dev accounts only).
- **Inventory**: `GET /v1/cards` → `{inventory, level}` (`RL_CARDS` 20/min
  + 200/day, `FEATURE_CARDS` kill switch). There is no buy route.
- **The phone's cache**: the `online` bucket in `cards.json` is a read-only
  mirror of the ledger (`Net.refresh_cards` / `_apply_cards`: spares =
  copies owned − the ones in the loadout; a slot the ledger no longer covers
  empties), so every card API and view renders it unchanged. The loadout is
  the phone's; `App.try_buy_card` refuses the online bucket.
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
- **The decision** (no payout yet: no tickets, XP, coins or card drops
  online — the ranked task refills this): at the decision the room writes
  the `matches` row and sends `settled {won, reason}` to each side (reason
  `played` / `forfeit` / `void`). The post-match page shows no rewards card
  for an online match. (Until 2026-10-19 this paid online coins by an upset
  multiplier; removed with the online wallet.)
- **Game**: the lobby's card strip (the three slots, `CARDS >`) opens
  `CardDeckSheet` on the online bucket — slots (tap to unequip) and LOADOUT
  (tap a spare to equip) only; no SHOP and no balance for the online bucket.
  `--qa-multi` seeds the cache, snaps the deck, and the fake peer brings an
  ice it plays on us.

## Ranked (Stage A, built 2026-10-19)

Ross's brief: a global rated 1v1 with (next, Stage B) verified card drops,
spoils and comeback rewards. Principles: online cards only for what the
server witnessed, never purchasable (docs/ECONOMY.md → The rule); never the
words bet / wager / stake — the mechanic is SPOILS; every number in data
(`data/ranked.json`, `data/online_drops.json`), computed by headless code
(server TS authoritative, `core/online/ranked_rules.gd` the display mirror),
enforced by Vitest + GDScript tests (`tests/fixtures/ranked_ladder.json` pins
both sides to the same tier bands).

- **Rating** (`server/src/glicko.ts`, `rank.ts`, migration `0007_ranked.sql`):
  Glicko-2 (Glickman's paper, tau 0.5, 1500 / 350 / 0.06), ONE global rating
  per player across every court, permanent, no seasons or resets. `ratings
  (player_id, mu, rd, vol, cons, games, wins, losses, win_streak,
  loss_streak, tier, division, peak_tier, peak_division, shield_left,
  updated_at)`, index `ratings_board (cons DESC)`. Updated by the room at the
  decision, ranked rooms only, each match its own rating period with the
  opponent's rd widened for idle days (`inflate`, on Glicko-2's internal
  scale). Forfeit = a loss for the leaver and a win for the stayer; a void or
  a desync changes nothing.
- **The visible rank** (`data/ranked.json` → `tiers`): the conservative
  rating `cons = mu − 2·rd` through the bands ROOKIE (700) / STARTER (1000) /
  PRO (1150) / ALL-STAR (1300) / MVP (1450) / LEGEND (1600), each in three
  equal divisions III → I (below the first band is ROOKIE III; LEGEND is one
  division and shows the global position, `LEGEND #12`). A new player sits at
  cons 800 → ROOKIE II. Rules: **inactivity never drops the tier** (Glicko
  widens rd while away; the tier only moves on a result); **promotion
  shield** — after moving up, the next 3 ranked matches cannot drop you
  (`shield_left`, event `shielded`); **tier floors** — once a tier is reached
  (`peak_tier`) the rank can lose divisions inside it but never falls below it
  (event `floored`: the rank becomes that tier's III while the rating
  underneath keeps moving, so matchmaking stays honest); a **peak badge**
  (`peak_tier` / `peak_division`); `promoted` / `demoted` otherwise.
- **The queue** (`POST /v1/match/ranked`, `FEATURE_RANKED`, the match
  middleware's `RL_MATCH` now 30/min; `lobby.ts` `/ranked`): one global
  queue in the Lobby DO beside the casual quick/code paths (which stay
  unranked: no rating, drops or spoils). The Worker loads the caller's
  `ratings` row (made on first use), the courts the verified level opens
  (`rules.ts` `areasForLevel`: cage ≥ 1, beach ≥ 3, park ≥ 4, city ≥ 5) and a
  hidden, mild `lean` (3+ straight ranked losses, or 7+ days since the last
  ranked game: the search treats the player as 100 below their rating).
  The phone polls every 4 s (`queue.poll_s`); each poll re-scans the other
  waiters (`rq:<playerId>` entries, stale after 60 s) with a window of
  `100 + 50 × floor(max wait / 4 s)` rating points over a non-empty common
  court; past 30 s (`cap_s`) it takes the closest anyone with a common
  court. **Ranked ignores the lobby's court picker** (Ross's call): the
  server picks a court at random from the ones both own. A pair writes
  `ranked_rooms (room, area, a_id, b_id)` (pruned after a day); the taker is
  told `{room, host:false, paired:true, area, opponent}` and the host learns
  on its next poll; `POST /v1/match/leave {ranked:true}` drops the entry.
  The room upgrade looks the id up in `ranked_rooms`: found → the row's court
  is forced, `x-ranked: 1`, and only its two players may connect.
- **Level trust** (`server/src/level_trust.ts`, `ranked.json` →
  `level_trust`): the server accepts a reported level only if it goes **up**,
  and no faster than `1 + grace (1) + 2 × hours since the account was made`
  (docs/PROGRESSION.md's fastest title run is ~2 levels an hour), clamped to
  99; `PATCH /v1/me` and register return the accepted level (a capped report
  is not an error). Online card eligibility also needs a minimum ladder tier
  per card (`data/online_drops.json` → `card_min_tier`, all rookie until the
  drop task).
- **The pre-match pick and the card cap** (every online match, casual too —
  Ross's call; `match_room.ts`, `cards.ts` `validHand(slots, inv, cap,
  tier)`): the `?slots=` query is gone. Once both phones are seated the room
  sets `cap = min(levels)`, reads both inventories, sends `matched {peer:
  {id, name, tag, level, town, tier, division}, levels, tiers, cap, seconds:
  20}` and arms a 23 s alarm. Each phone sends `loadout {slots, ready}` as its
  pick changes (provisional) and on READY; the room keeps the latest,
  validated against the ledger, the player's level, the cap and the tier
  floor (a blanked slot comes back in `loadout_ok {hand, ready}`), and starts
  when both are ready or the alarm fires (a side that never picked starts
  empty). So a level-7 card never meets a level-2 player. A disconnect during
  the pick ends the room like a pre-start leave: no row, no rating.
- **The decision** (`record()`): the `matches` row gains `ranked, winner
  (a | b | NULL), a_level, b_level, cap, a_mu_before/after, b_mu_before/after`;
  for a ranked room both `ratings` rows are updated in the same batch and
  `settled` carries `ranked: true, rating: {before: {mu, rd, cons}, after:
  {…}, delta}, rank: {tier, division, position?}, events: [...], peak`
  (a void: `ranked: true` and nothing else; a desync: `desync: true`, no
  change). Casual: `settled {won, reason, ranked: false}`. No payout yet —
  Stage B adds spoils, the drop meter, tickets.
- **The board** (`GET /v1/ranked/board`, `FEATURE_RANKED`, `RL_BOARD`): the
  top 50 by `cons` (position, handle, tier, division, record) memoised 30 s
  in the isolate, plus your own live `me` (position = 1 + the count above
  you, tier, division, mu, rd, cons, record, peak). `GET /v1/me` gains
  `rank {tier, division, games, wins, losses, cons, position?}` so the lobby
  cards show the badge without a board call.
- **Game**: the lobby's RANKED button (`App.start_online(…, "ranked")` polls
  the queue until paired, then the room as any other); `PreMatchPage`
  (`game/ui/pre_match_page.gd`) between PLAYER FOUND and the tip-off — the
  face-off cards with the badges, `CARD CAP · LVL n`, the loadout strip with
  over-cap spares dimmed, the timer bar, READY; the RANKED tab on the Ranks
  page (`Net.load_ranked_board`, cached 60 s); `Net.me_rank` from `/v1/me`
  and every rated decision; the post-match `RATING +18 · PRO II · PROMOTED`
  line (`MatchCopy.rank_delta_line`). docs/HOME.md has the pages; QA
  `--qa-multi` (`multi_prematch`, `online_result`).
- **Deploy** (Ross): `wrangler d1 migrations apply hoop_shoot --env production
  --remote` (0007), `wrangler.toml` already carries `FEATURE_RANKED = "on"`
  and `RL_MATCH` 30/60 s, `wrangler deploy --env production`. Until it ships
  the phone's RANKED button fails with `offline` (404 on the route), and the
  pre-match step needs the new room too — deploy the Worker together with
  this build.
- **Stage B (next, after Ross's check)**: spoils (the loser's played cards to
  the winner; forfeit, void, insurance, a same-opponent cap), the server-side
  drop meter sized from `WEEKLY_CARD_TARGET`, the loss-streak Ice, cumulative
  login days, idempotent milestones mirrored to the Platform facade, ranked
  tickets inside the rate band, the full post-match copy.

## Platform identity (prep, 2026-10-17)

Groundwork for Game Center (iOS) and Play Games (Android) sign-in: no store
plugin, achievements or leaderboards yet. A platform link is an optional
upgrade on top of the anonymous account, never a requirement; when the
plugins land, all that is left is "get a proof from the platform, hand it to
the server". Ross's calls: per-device secrets, deletion wipes the phone too,
`FEATURE_PLATFORM` on, deletion independent of it.

**Tables (`server/migrations/0005_platform_identities.sql`).**
- `player_identities (provider, subject, player_id, linked_at, meta)`,
  PK `(provider, subject)`, `UNIQUE (player_id, provider)`: one identity maps
  to exactly one player, one player has at most one identity per provider.
  `provider` is `gamecenter` | `playgames` (`test` only under Vitest).
  `meta` is JSON (a display name, Apple's gamePlayerID) — never a proof.
- `player_secrets (player_id, secret_hash, created_at, last_seen, label)`,
  PK `(player_id, secret_hash)`: **a secret per device**, at most
  `MAX_SECRETS` 5 (the oldest is evicted). Registration makes the first, a
  platform restore ADDS one (the other phone stays signed in: one account on
  two phones), the transfer code REPLACES them all (a move: the old phone
  dies, as before), unlink changes none, deletion removes all. Seeded from
  `players.secret_hash`, which stays as the first secret's copy; `authenticate`
  reads this table (any matching hash, constant-time per row).

**Which platform id is the subject, and why.**
- Apple: `GKLocalPlayer.fetchItems(forIdentityVerificationSignature:)` signs
  the **teamPlayerID** — the same id for every game we ship under our Apple
  team, stable per Apple account; it changes only if the app is transferred
  to another team. `gamePlayerID` is per-game and is *not* covered by the
  signature (kept in `meta`); the legacy `playerID` is deprecated.
- Google: the next-generation Play Games player id is **per-game and stable
  within our PGS project** across devices (read server-side from
  `games/v1/players/me`). The cross-game `developer_player_key` changes on a
  developer-account transfer and must never be a key.

**Routes (`server/src/platform_routes.ts`, behind `FEATURE_PLATFORM`, bodies
≤ 4 KB, unknown fields → 400).**
- `POST /v1/link {provider, proof}` (auth, 5/hour): the verifier turns the
  proof into a subject (501 `not_implemented` for gamecenter/playgames today,
  401 `proof_rejected`, 400 `provider`). Already bound to the caller → 200
  `{linked, already: true}`; unbound → bound, 200; bound to **another**
  player → 409 `{error: "conflict", provider, name, tag, level}` — accounts
  are never merged, the game asks. A re-link with a new subject replaces the
  caller's old identity for that provider.
- `POST /v1/link/restore {provider, proof, newSecret}` (no auth, 5/hour per
  IP): the identity's player gets `newSecret` added → 200 `{playerId, name,
  tag}`; unknown identity → 404.
- `DELETE /v1/link/:provider` (auth, 5/hour): unlink, idempotent.
- `GET /v1/me` → `{playerId, name, tag, level, providers}`.
- `DELETE /v1/me` (auth, 3/hour per IP + 2/hour per player, **no kill
  switch**): one batch deletes the player's rows from players,
  player_secrets, player_identities, transfer_codes, save_parts, tt_best,
  tt_week_best, seen_runs, online_cards, online_ledger →
  `{deleted: true}`; the bearer is dead after. Match history (`matches`) keeps
  the room rows: they are the other player's record of the game and carry no
  handle. Apple's guideline 5.1.1(v) applies to us: the app creates an
  account on first launch (guest / auto-generated accounts count), so
  in-app deletion of the account *and its data* is required, not a
  deactivation; this is Settings → PLAYER → DELETE ACCOUNT (two taps).

**Verifiers (`server/src/platform.ts`).** `ProofVerifier.verify(proof) →
{subject, displayName?, meta?}`; `gamecenter` and `playgames` throw
`NotImplemented` (→ 501) with the real check written out in their comment
blocks; `test` exists only when `PLATFORM_TEST_VERIFIER = "on"`, a Miniflare
binding in `vitest.config.ts` that is never a wrangler var, so every flow is
under test now (`server/test/platform.test.ts`: link, 409, restore,
per-device vs transfer, cap, unlink, deletion, throttles, kill switch, 501).

**Game.**
- `Platform` (autoload, `game/net/platform.gd`) owns one `PlatformBackend`
  (`game/net/platform_backend.gd`; the base class is the null backend — never
  available — on desktop, headless, QA and the phone until a plugin exists).
  A real backend implements `provider_id()`, `display_name()`,
  `is_available()`, `is_signed_in()`, `sign_in()`, `get_identity_proof()`
  and emits `signed_in`.
- Flow: launch → `Net.ensure_account` as today (then `fetch_me` refreshes
  the linked providers onto the account part — names only, never a proof)
  → `Platform.sync_link()`: signed in and not linked → `Net.link_platform`.
  409 → `conflict` + the `AccountFoundSheet` ("FOUND YOUR ACCOUNT · BRICK
  BARON 42 · LVL 7 · USE IT?"). USE IT → `Platform.accept_conflict()` →
  `Net.restore_from_platform` (a new device secret on that account, the
  account part rewritten, `pull_save(true)` — the claimed-code path) →
  "WELCOME BACK". NOT NOW keeps this account unlinked. The handle stays
  ours; the platform display name is never adopted.
- Offline: an unregistered or offline link waits in the outbox
  (`pendingLink`, provider only) and `Net.flush` hands it back to
  `Platform.sync_link` once registered.
- Recovery: a 403 on register or a 401 on push / pull / me / link → restore
  from the platform when linked and signed in, else a fresh identity
  (`Net._recover_identity`, `_mint_fresh`).
- Settings → PLAYER: `PlatformLink` (LINK GAME CENTER / LINKED · GAME CENTER,
  tap unlinks; hidden while the backend is null) and `DeleteAccount` (first
  tap arms "TAP AGAIN TO DELETE EVERYTHING" for 8 s, second tap →
  `Net.delete_account` → `SaveService.wipe_all()` → the title; the next
  `ensure_account` mints a new identity).
- Tests: `tests/test_platform.gd` drives it with `FakePlatformBackend`
  (`tests/fake_platform_backend.gd`) and `Net.transport`, a scripted stand-in
  for HTTPRequest; `tests/test_account.gd` covers `linked`, `pendingLink`,
  `wipe_all`.

**What is left, per platform.**
- iOS: a GameKit plugin (GDExtension or the iOS export plugin) exposing
  `authenticate` and `fetchItems(forIdentityVerificationSignature:)` →
  `GameCenterBackend` (`provider_id "gamecenter"`, proof `{publicKeyURL,
  signature, salt, timestamp, teamPlayerID, gamePlayerID, bundleID}`); Game
  Center enabled on the app record in App Store Connect; the verifier:
  fetch + validate the Apple certificate (apple.com host, chain, expiry,
  cached), RSA-SHA256 over `teamPlayerID ‖ bundleID ‖ timestamp (big-endian
  UInt64) ‖ salt`, timestamp freshness, our bundle id; the deletion flow
  needs nothing extra (no Sign in with Apple tokens to revoke).
- Android: the Play Games Services v2 plugin → `PlayGamesBackend`
  (`provider_id "playgames"`, proof `{serverAuthCode, playerId}` from
  `GamesSignInClient.requestServerSideAccess(WEB_CLIENT_ID, false)`); in the
  Play Console a Game server credential (OAuth web client) whose id and secret
  become Worker secrets (`wrangler secret put`); the verifier: exchange the
  code at `https://oauth2.googleapis.com/token`, `GET
  https://www.googleapis.com/games/v1/players/me`, subject = its `playerId`,
  equal to the client's claim.
- Both: flip the verifier from `NotImplemented` to real, keep the `test`
  one Vitest-only, run the Worker migration `0005` and deploy (Ross).
