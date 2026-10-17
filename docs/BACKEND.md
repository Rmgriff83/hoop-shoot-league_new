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
- **Rematch** (2026-10-07): only on the post-match page, while the finished
  room is still open (it lives 60 s after the decision, another minute per
  offer). `REMATCH?` sends `rematch`; the other phone's card turns gold
  (`THEY WANT A REMATCH · TAP TO ACCEPT`); when both have asked the old room
  mints a fresh room id and sends `rematch_go {room, area}`, each phone opens
  it with its current loadout (revalidated by the Worker) and the new
  `start` tips off. Leaving the page (HOME) closes the socket and the other
  phone's card reads `THEY LEFT`. `App.offer_rematch`, `App.rematch_state`,
  `MatchCopy.rematch_*`.
- **Later**: a ranked ladder from `matches`, rejoin after a drop (the room
  already re-sends `start` to a reconnect), an online card-drop system.

- **ANY court (2026-10-17, design 37a):** `POST /v1/match/quick {area: "any",
  areas: [owned courts]}` (and `leave`). The Lobby pairs an any-court player
  with the first waiter on one of their courts, else with another any-court
  player on a court both own (`cage` when none); the reply carries `area`
  (the joiner's court) and the room, created by an any-court host with
  `x-area: any`, takes the court the joiner brings. `areas` is validated
  (unknown court → 400); a code is never "any".

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
  tt_week_best, seen_runs, online_wallet, online_cards, online_ledger →
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
