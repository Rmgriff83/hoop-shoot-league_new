# Leagues — how the head-to-head layer is built

Reference: the original TS game (`~/Documents/projects/hoop_shoot_league`, its tests are the
spec). Ross's twist: a league per location, shorter seasons, 90 s heats with a ball-return wait,
a picture-in-picture opponent, and one-time-use power-up cards (M3).

## Core (headless, deterministic)

- `core/util/det_rng.gd` — `DetRng`, the only randomness in core (xorshift64*, `next()`,
  `normal()`, `range_i`, `pick`, `shuffled`, `fork(label)`). Every heat, quick-sim, schedule and
  reward roll replays from its seed.
- `core/ai/` — the AI shooter, ported from `src/core/ai/*`:
  - `AiRatings` (accuracy, swish_rate, pace, composure, streakiness, consistency),
  - `AiMood` (hot/cold Markov chain + per-game form offset → effective accuracy, with score
    pressure),
  - `AiCadence` (pickup delay + aim time from `pace`; `AIM_CAP` 3 s),
  - `AimError.ai_shot(...)` — ideal solve for the heat's geometry, then rating-scaled physical
    error (angle window from swish_rate, speed sigma from accuracy, lateral wobble). The physics
    sim resolves it; no dice on outcomes.
- **Calibration per rim.** The speed-sigma and compensation tables are fitted by
  `tools/calibrate_ai.gd` (Monte Carlo, seeded) into `assets/ai/calibration_<key>.json` for
  `regulation`, `arcade` (2.6 m), `beach` (3.41 m) and `city` (3.63 m, chain net). Re-run after any physics change:
  `godot --headless --path . -s tools/calibrate_ai.gd` (all) or `-- arcade` (one). About a minute
  per key. `tests/test_ai.gd` checks the observed make rate tracks the rating within ±0.08 on the
  arcade rim.
- `core/match/time_trial.gd` gained: a configurable period length, the **ball-return wait**
  (`ball_return_s`; `pickup()` is refused until `ball_wait()` hits 0; event `ball_ready`),
  `freeze_rim(reason)` (the Ice card), and `start_period(seconds)` for overtime.
- `core/match/heat.gd` — `Heat`: one `TimeTrial` per side (player / ai) on the same clock, the AI
  driven by cadence timers and `AimError` shots, ties → `ot_seconds` overtime periods until
  decided. Same renderer contract (`tick → drain_events → balls(side)`), events tagged with
  `side`, plus `ot_start` and `heat_done {result}`. `result()` = won, scores, OT count, per-side
  totals (score, makes, swishes, attempts, bestStreak, bonus, iced).

Defaults: 90 s heats, 20 s overtime, 1.5 s ball-return wait (quick heats); league rows set `ball_return_s` to 1.0. The last 30 s trigger the location's mechanic for both sides: the cage's sliding board (`board_motion` on both TimeTrials; the AI leads a moving hoop by `Heat.AI_LEAD_S`), the beach's random spot shuffle (the screen's existing shuffle for you; the AI gets its own seeded walk between the arena's spots in `Heat` — `set_spots`, `ai_spot` event — and shoots from that spot's origin, with the PiP camera following).

## Heat screen (M2b)

- `game/screens/heat_screen.gd` extends the time-trial screen (`_make_rules()` builds a `Heat`
  and points `trial` at the player's side; `_step_rules()` ticks the heat and routes AI-side
  events to `_handle_ai_event`). The player's court, flick input, HUD and reader board work
  exactly as in a trial.
- **Picture-in-picture**: a `SubViewportContainer` (216 × 384, own 3D world) holding a second
  `CourtGeometry`, camera and `BallPool` for the opponent, with a minimize button that collapses
  it to an "OPP n" chip (the viewport stops rendering while minimized). Opponent sounds are ducked
  through `Sfx.gain_db` while their events dispatch.
- **HUD**: `set_heat(true)` shows `YOU n · OPP n`; `set_ot(n)` prefixes the clock; the
  ball-return wait shows as `next ball 1.2` under the centre while the player waits.
- **Overtime**: `ot_start` puts OVERTIME on both boards and the HUD; `heat_done` hands
  `Heat.result()` to `App.finish_heat` → `heat_result_screen` (WIN/LOSS, score with OT, you/them
  table; Rematch re-rolls the seed; Continue appears for league heats).
- **Routing**: `App.MODES` rows `heat` / `heat_beach` (`heat: true`, `calib_key`), title button
  QUICK HEAT → area page → `App.start_area("heat", area)`; leagues call
  `App.start_heat(mode_id, cfg)` with their own seed, ratings and opponent card.

## League core and dashboard (M2c)

**Data** — `data/shooters.json` (the 15 authored AI shooters: id, name, hometown, number,
nickname, bio, colors, signature, ratings) and `data/leagues.json` (one league per location:
`roster` of 7 shooter ids, `err_mult`, heat/OT seconds, ball-return wait, `rounds`,
`playoff_teams`, `semis_best_of`, `final_best_of`, `levels` band, `unlock` level or null, `xp_mult`, `rewards`;
docs/PROGRESSION.md). The arcade
league takes the seven lowest-rated shooters, the beach league the next seven, and the city
league `starfall` plus six city shooters (Kingsbridge, Ferry Row, Union Yards, Eastgate,
North Tunnel, Rooftop Hill). `LeagueData` loads and validates all three. The ratings
themselves follow the **difficulty ladder** below.

**Core (`core/league/`)** — all pure, all seeded:
- `ScheduleGen.generate(team_ids, rounds, seed)`: circle-method round robin, 8 teams × 2
  rounds = 14 days × 4 games, every pair twice, each team hosts 7.
- `Standings`: table with tiebreaks (win% → head-to-head → point diff → seeded coin flip),
  games behind, streaks, and the clinch engine (`guaranteed_ahead`, `compute_clinches`: playoffs
  / top seed / eliminated; a split head-to-head is never treated as settled).
- `QuickSim.sim_heat(home, away, seed, seconds, ot)`: shots = floor(90 / pace) Bernoulli makes
  with the mood chain, swish share `0.05 + 0.3·acc·swish`, points through `StreakRules` (tiers,
  swish +1, ice after COLD_AT misses with the swish-through / break rules), 20 s OT rounds.
- `Playoffs`: semis 1v4 / 2v3 (Bo3) → final (Bo5); `Season`: create / resolve_day /
  start_playoffs / resolve_playoff_step (player playoff games are live-only); `PlayerRatings`:
  EWMA self-ratings for simmed days; `Campaign`: the per-league doc (season, self ratings, career
  totals/highs/seasons, shooter careers), `apply_live_result`, `sim_step`, `sim_to_playoffs`,
  `maybe_finish_season`, `start_next_season` (unlocks are `Progression.league_unlocked`).

**Persistence** — save parts `campaign` (`{leagues: {league_id: doc}, records}`) and
`liveGames` (the player's last 50 heat box scores, best-first per league), both dirty-tracked.

**App** — `enter_league(id)` creates the campaign on first visit and makes it current (the
dashboard is the home page's league context, `docs/HOME.md`); `start_league(id)` also goes there;
`start_league_heat()` builds the heat config (opponent card + ratings, league format, a seed
from season seed + game) and `finish_heat` applies the result (season, career, live games,
the league's coins and tickets from its `rewards`, docs/ECONOMY.md) before the post-match page
(`heat_result_screen.gd`, design "League Post-Match", docs/HOME.md → Results), whose CONTINUE
SEASON returns to the dashboard. `App.league_gating` is on in release builds (off in debug builds, so the editor and the phone dev APK reach every area): a league (and its whole area) opens at its
`unlock` level, reached by playing the league before it (docs/PROGRESSION.md).

**Dashboard** — `game/ui/league_context.gd` on the home page (2026-09-26, design "Home
League Context v2"; the full-screen `league_hub_screen` is gone; docs/HOME.md). Tabs MATCH
(the opponent's shooter card with PLAY — **every game is played live, the SIM DAY / SIM ALL
buttons are gone** — ADVANCE when out of the playoffs, START SEASON N+1 when done), TABLE
(standings with the playoff line, or the bracket), SCHED (your 14 games + playoff games,
today marked), CARDS (spares + shop), STATS (career, best matches, the location's
time-trial board). The home's LEAGUE card and its floating layer (`LeagueSummary`) show
each league's season numbers, its next game and its unlock rule.

## Difficulty ladder (2026-10-03)

Ross's rule: a league gets harder by fielding **fewer pushovers, not stronger stars**, and
the step up from the cage is small. Before this the three rosters were non-overlapping
rating bands (cage 0.38–0.58, beach 0.60–0.78, city 0.66–0.80) with a second, hidden ramp
in `err_mult` (1.2 / 1.0 / 0.9: the cage AI played worse than its rating, the city AI
better) — and because makes compound through `StreakRules` tiers, measured in points the
beach AIs scored 2.0× the cage's and the city AIs 2.85× (starfall 79 a heat against a
25-point reference, 100 % wins). Note the hoop itself is **neutral for the AI**:
`assets/ai/calibration_<key>.json` inverts each geometry so a rating makes the same share
everywhere; the farther hoop, livelier iron and chain net are the *player's* ramp, which
Ross tunes per area (after any geometry change re-run `tools/calibrate_ai.gd -- <key>`,
then the lab below to confirm the AI ladder held).

**The lab** — `godot --headless --path . -s tools/league_lab.gd [-- cage|beach|city]
[-- --n=20]`: every roster shooter plays `n` seeded bot-vs-bot heats (`CardLab.run_heat`,
no cards) against one reference bot (accuracy 0.55, swish 0.5, pace 4, composure 0.6 —
a decent human) on the league's real geometry, `err_mult`, format and calibration, and
prints mean AI points, the reference's points and the AI's win share per shooter; per
league the mean / min / max, the pushover count (the reference wins more than 75 % of
heats) and the beach/cage and city/cage ratios. It writes `assets/ai/league_ladder.json`,
which `tests/test_league_ladder.gd` pins (overlapping bands, no star above 0.70, floors
rising, `err_mult` 1.1 / 1.0 / 1.0, pushovers 3 / 1 / 0, the mean ratios, the city star
under 1.35× the cage's, every beach and city shooter beatable). Points are very
sensitive to pace and streakiness — a 0.50 shooter who shoots every 2.6 s outscores a
0.61 who shoots every 3.6 s — so tune by the lab's points, not the accuracy number.
Rosters and `err_mult` also feed `tools/card_lab.gd` (`assets/cards/card_power.json`,
`tests/test_card_budget.gd`): re-run it after any ladder change.

**Measured 2026-10-03** (`n` 40 heats a shooter, seed 7171; † = pushover):

| league | AI mean | reference | top | pushovers | shooters (accuracy → points, AI win share) |
|---|---|---|---|---|---|
| cage | 19.4 | 21.0 | 28.7 (pinewick) | 3 | brickport 0.38 → 13 pts, 8 % wins†, maple-falls 0.50 → 16 pts, 18 % wins†, sunnyvale-flex 0.46 → 17 pts, 25 % wins†, dustplain 0.42 → 17 pts, 28 % wins, goldgulch 0.56 → 20 pts, 45 % wins, cactus-flats 0.50 → 23 pts, 70 % wins, pinewick 0.56 → 29 pts, 78 % wins |
| beach | 24.9 | 24.1 | 30.1 (ironvale) | 1 | thunder-mesa 0.51 → 20 pts, 23 % wins†, harborlight 0.58 → 24 pts, 48 % wins, frostpeak 0.56 → 24 pts, 55 % wins, bellmeadow 0.55 → 24 pts, 50 % wins, coalditch 0.46 → 24 pts, 53 % wins, red-rock 0.58 → 28 pts, 60 % wins, ironvale 0.59 → 30 pts, 73 % wins |
| city | 28.5 | 24.5 | 34.4 (starfall) | 0 | eastgate 0.61 → 25 pts, 50 % wins, kingsbridge 0.54 → 26 pts, 60 % wins, ferry-row 0.54 → 27 pts, 68 % wins, north-tunnel 0.53 → 28 pts, 78 % wins, rooftop-hill 0.60 → 29 pts, 68 % wins, union-yards 0.59 → 30 pts, 73 % wins, starfall 0.59 → 34 pts, 90 % wins |

Ratios: beach/cage mean ×1.28, top ×1.05; city/cage mean ×1.47, top ×1.20 (before: ×2.00 /
×2.06 and ×2.85 / ×3.07). The city's mean ratio is mostly the cage's three pushovers
dragging its mean down; the city's regulars score ×1.28 the cage's regulars. Old → new
accuracies: cage brickport .38, dustplain .45→.42, sunnyvale .50→.46, maple-falls
.52→.50, cactus-flats .53→.50, goldgulch .57→.56, pinewick .58→.56; beach coalditch
.60→.46, thunder-mesa .61→.51, bellmeadow .62→.55, frostpeak .63→.56, harborlight
.66→.58, red-rock .72→.58, ironvale .78→.59; city ferry-row .66→.54, kingsbridge
.68→.54, north-tunnel .69→.53, eastgate .70→.61, union-yards .74→.59, rooftop-hill
.76→.60, starfall .80→.59. `err_mult` 1.2 / 1.0 / 0.9 → 1.0 everywhere.

## AI pacing (2026-09-18)

`pace` is think time on top of the ball-return wait: the AI's release-to-release cycle is
`ball_return_s + pace × AiCadence.TEMPO` (0.35) — 1.84 s for pace 2.4 in a league heat (1 s
return), 2.33 s at the roster median 3.8, 2.96 s at 5.6; quick heats (1.5 s return) run 0.5 s
slower a shot. `Heat._drive_ai` starts the next cycle at release, so like the human the AI can
hold its next ball while the last is still in the air. `QuickSim.shots_for` uses the same cycle
so simulated box scores match live volume.

## League boards (2026-09-18)

Both areas show the standings (regular season) / bracket (playoffs) on an in-world board in
league heats (`game/view/league_banner.gd`, Caveat handwriting with per-line jitter). The
beach fence carries a chalkboard (`chalkboard.png`, chalk palette); the arcade cage hangs a slim
**hand-painted sash** at the back panel's bottom-right (`league_banner_kind = "sash"`,
`sash.png` from `tools/aseprite/gen_sash.lua`: cream cloth, brushed red bands, gold fringe)
with one painted line — league name plus "4th · 3-3" / "semis · 1-0" / "champs!"
(`heat_screen.sash_line`). `league_banner_style` picks the handwriting palette for
board-style banners (only "chalk" exists).

## Overtime (2026-09-18)

A tied buzzer starts a `Heat.OT_BREAK_S` (2.5 s) break: `ot_start` shows the OVERTIME card on
the heat screen while both trials stay DONE. Then `ot_period`: both shooters reset to the key
(`ai_spot` index 0; the screen calls `_set_spot(0)`), `TimeTrial.start_period(ot, true)` clears
the balls, parks the hoop at home, locks the board slide (`motion_locked`) and the spot
shuffle (`overtime`), keeps score/streak/fire/ice, and opens on the 3 s countdown → `go`. The
LED keeps the carried score at the OT tip-off.

## Power-up cards (M3)

Card targets (2026-09-17): `target` is `"opponent"` (Deep Freeze) or `"self"` (**fire cards**,
first `fire7` / Heat Check: `effect {kind: "fire", seconds: 7}`). `Heat.play_card` routes by it;
`CardPolicy` plays self cards once the AI holds a ball. `TimeTrial.light_rim(seconds)`: the
streak jumps to `FIRE_AT` so makes pay and stack the normal tiers for the window; the window's
end (`fire_off {time}`, waits for a ball in the air to land), a miss (`fire_off {miss}`) or ice
(`fire_off {ice}`) puts it out and resets the streak. Longer fire cards = one more JSON row.
Card art carries a target badge (red arrow = against the opponent, green plus = for you). On
the heat screen a play is "dealt": the card slides out of its slot, grows to the centre with a
caption, then flies to your hoop (self) or the PiP / its chip (opponent); the AI's plays run
the reverse path, and the other side's LED announces every play ("ICED BY CARD" when hit,
"OPP HEAT CHECK" when the opponent boosted themselves). A played card leaves the tray and the remaining cards slide to re-centre on
the column; a burning fire card stays lit with its tag counting the window down, then leaves.

Loadout semantics (doc `v` 2, 2026-09-17): the three slots hold *real copies*. Equipping moves
a copy out of the inventory (spares), unequipping returns it, and playing a card in a heat
empties its slot for good (one-time use; nothing goes back to the inventory). One owned copy
can only fill one slot. `CardDefs.migrate` upgrades v1 saves, where slots merely referenced
the inventory, on load. The heat screen's tray stacks the equipped cards up the left edge
(slot 0 at the bottom), centred on the column: READY, or WAIT (effect can't land yet —
opponent's clock not running or rim already iced); played cards leave the tray.

- **Governance (2026-09-22)**: see **`docs/CARDS.md`** — every card's power is *measured*
  (`tools/card_lab.gd` → `assets/cards/card_power.json`), rarity and price derive from it, each
  league deals its AI a fixed per-season allowance (`ai_cards_per_season` / `ai_hand_max` /
  `ai_pool` / `card_parity`, the authored `ai_cards` as guaranteed signature cards) that the
  season stores in `cardHands` and consumes as played, and `CardBudget` checks the AI's
  per-season power against the player's expected income (`tools/card_ledger.gd`,
  `tests/test_card_budget.gd`). Quick-sims stay card-free by design.
- **Data**: `data/cards.json` — one row per card (`id, name, rarity, price, target, effect
  {kind}, art, blurb`) plus rarity weights, drop odds, the rarity bands and the price curve.
  Cards so far: `ice` / Deep Freeze (opponent), `fire7` / Heat Check (self).
  Card fronts are pixel art from `tools/aseprite/gen_card_textures.lua` (96 × 128,
  `assets/textures/cards/`).
- **Core** (`core/cards/`): `CardDefs` (definitions, inventory/loadout doc helpers: add,
  equip, unequip, consume/`consume_slot`, `loadout_ids`/`loadout_slots`, `owned`, `migrate`), `CardEffects` (the effect registry — `ice` calls
  `TimeTrial.freeze_rim("card")` on the target side, so the same cold-streak rules apply),
  `CardRewards.roll(won, playoff, seed)` (seeded drops, win 60 % / loss 25 % / +15 % in the
  playoffs, rarity-weighted). `core/ai/card_policy.gd`: the AI plays Ice when the player is on
  ≥ 3 straight or leads by ≥ 4 with < 45 s left, never in the first 10 s, once per card.
- **Heat**: `hands` per side (`player_cards` / `ai_cards` in the config), `play_card(side, id)`
  (consumed only when the effect applied; emits `card_played {side, card, target, ok}`),
  `can_play`, the AI's hand from the season's `cardHands` (its per-season allowance, less what
  it has already played on you); `cardsPlayed` in the result totals (never shown postgame).
- **Save**: part `cards` = `{inventory: {id: n}, loadout: [id|null ×3]}`; `App.cards_doc /
  add_card / equip_card / unequip_card / consume_card / try_buy_card / loadout_hand`. A deployed
  card leaves the inventory immediately (abandoning a heat is no refund). Every heat (league or
  quick) starts with the equipped hand.
- **UI**: the in-heat **card tray** (left edge, inside the flick input's UI zone; tap = deploy,
  greyed when it can't apply), the **card toast** (art + "Deep Freeze → OPPONENT", or "Ollie
  Knots plays Deep Freeze on YOU!"), the opponent's board scrolls ICED BY CARD, the dashboard's
  **LOADOUT** (this league's three slots + inventory) and **SHOP** (this league's cards for this league's coins) tabs, and
  the result screen's card drop.

## League banners (environment dressing, league heats only)

`game/view/league_banner.gd` hangs a quad textured by a one-shot 2D SubViewport. The beach board is a **chalkboard**: a slate texture from `tools/aseprite/gen_chalkboard.lua`, the Caveat handwriting font (OFL, `assets/fonts/caveat/`, credited), chalk colours, per-line jitter/tilt and hand-drawn underlines. The cage label stays cloth. The
beach's back fence (to the shooter's back-right of the hoop) shows the **standings** in the
regular season and the **playoff bracket** in the playoffs; the cage's left wall carries a small
**LEAGUE MATCH** banner. Anchors live on the arena sets (`league_banner_kind / pos / size /
yaw_deg / lit / label` in `assets/arena/*/arena_set.tres`), so moving a banner is a data edit.
The heat screen builds it in `_after_ready()` only when the heat belongs to a league, from the
same `Standings` / season calls the dashboard uses. From the KEY on the beach only the near half
of the fence banner is in the phone's narrow view; the left spots see all of it.

## After the buzzer (2026-10-01)

A league heat ends with the match-end page (`MatchEndOverlay`, docs/HOME.md
→ Results) before the post-match page: `App.settle_heat` folds the result
into the campaign, pays out, grants XP, rolls the drop and snapshots the
before/after standings (`last_heat.league_end`) that the page animates.
