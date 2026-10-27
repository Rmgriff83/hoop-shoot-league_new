# Cards — the governance rulebook

How power-up cards are measured, priced, dealt and kept in balance between
the player and the AI across every area league. This is the document to
read before adding a card or a league. The mechanics themselves (effects,
loadout, tray, drops) are in `docs/LEAGUE.md` → *Power-up cards*.

The system is three numbers. Each lives in data, is computed by a headless
`core/` class, is printed by `tools/card_ledger.gd`, and is enforced by
`tests/test_card_budget.gd`. **A green ledger is a green suite.**

| Number | What it is | Where it comes from | Where it lives |
|---|---|---|---|
| **Power** | a card's mean point swing per heat, per league | measured: `tools/card_lab.gd` (`CardLab`) | `assets/cards/card_power.json` |
| **Scale** | rarity bands and the price curve, in power points | authored once | `data/cards.json` → `rarity_bands`, `price_curve` |
| **Parity** | AI card power per season ÷ the player's expected card income | computed: `CardBudget` | target per league in `data/leagues.json` → `card_parity` |

## 1. Power is measured, never guessed

`tools/card_lab.gd` runs seeded bot-vs-bot heats on each league's format,
geometry, error multiplier and roster (`Heat` with `player_bot`, the same
cadence/aim driver on both sides). Every seed runs one control heat with no
cards and one heat per card with that card in the AI's hand; the card's
**power in that league is the mean change in the AI's margin, in points**.
The heat plays the card through `CardPolicy → Heat.play_card → CardEffects →
TimeTrial` exactly as a league heat does, so **a new effect kind is measured
the day it exists — the lab has no model of any effect**.

```
godot --headless --path . -s tools/card_lab.gd            # every card, every league (~0.4 s a heat)
godot --headless --path . -s tools/card_lab.gd -- ice     # one card; the others keep their numbers
godot --headless --path . -s tools/card_lab.gd -- --n=60  # a quick look (do not commit)
```

It writes `assets/cards/card_power.json` (`n`, `seed`, per-card per-league
power, and `detail` with the margins and the share of runs where the policy
actually played the card). The file is deterministic and **committed**; the
suite reads it and never runs the lab. The lab's `n` and `seed` are constants
in the tool so the numbers are reproducible; the same run rewrites the same
file.

Read `played` too: a card the AI rarely finds a moment for measures near
zero *because* it is rarely played, which is a policy question, not a
balance one.

The lab measures on the still court (no board slide, no spot shuffle) — a
card's swing barely depends on either and the control is cleaner without
them.

## 2. Rarity and price derive from power

`data/cards.json` carries the scale:

```json
"rarity_bands": {"common": [lo, hi), "rare": [lo, hi), "epic": [lo, hi)},   // power points
"price_curve":  {"k": …, "exp": …, "tolerance": …}                           // price = round10(k · power^exp)
```

`CardDefs.rarity_for(power)` and `CardDefs.price_for(power)` are the only
way a card's `rarity` and `price` should be chosen. The stored values are
still typed in the JSON (they are read everywhere), but `CardBudget.problems()`
fails the suite when a card's `rarity` is not the band its mean power falls
in, or its `price` is more than `tolerance` off the curve. The tolerance is
there to nudge a price for feel — not to leave the band.

**The scale was calibrated once from the first two cards** (Deep Freeze and
Heat Check define it). Do not move the bands to fit a new card; move the
card.

Calibration record (2026-09-22, lab n 500, seed 4242):

| Card | cage | beach | mean | band | price |
|---|---|---|---|---|---|
| Deep Freeze `ice` | +0.61 ± 0.06 | +0.85 ± 0.13 | 0.73 | rare | 150 (curve 130) |
| Heat Check `fire7` | +0.78 ± 0.07 | +0.55 ± 0.13 | 0.67 | common | 100 (curve 120; was 80) |

Re-measured 2026-09-27 with the city league and the fire window's loan rule
(below), lab n 500, seed 4242:

| Card | cage | beach | city | mean | band | price |
|---|---|---|---|---|---|---|
| Deep Freeze `ice` | +0.61 ± 0.06 | +0.85 ± 0.13 | +1.03 ± 0.16 | 0.83 | rare | 150 (curve 160) |
| Heat Check `fire7` | +0.82 ± 0.07 | +0.97 ± 0.10 | +0.90 ± 0.18 | 0.90 | rare (was common) | 170 (curve 170) |
| Vortex `vortex6` | +0.98 ± 0.08 | +2.73 ± 0.20 | +2.12 ± 0.20 | 1.94 | epic | 470 (curve 470) |

The Vortex is worth most where rattle-outs are commonest (the beach's
lively iron); Heat Check's old hard reset had measured −0.84 in the city.

So a card is worth well under a point per heat, and the two are nearly
equal: Ice bites harder on the beach's better shooters (more makes to
catch), Heat Check pays more in the cage where a lit rim outruns the weak
field. The bands were set with the common/rare edge at 0.7 — the geometric
midpoint of the two anchors — and rare/epic at twice Ice. **Both anchors sit
within 2·se of that edge by construction**, so the ledger marks them NEAR
EDGE; that flag matters for *new* cards, not these two. Heat Check's price
rose from 80 to 100 to land inside the curve's tolerance (a price ratio of
150:80 would need power^6.7).

**Measurement error.** The lab pairs each card heat with a control heat on
the same seed, and card decisions draw from their own forked stream
(`Heat._bots[side].card_rng`), so the shooting draws are identical between
the pair and the difference is the card's effect alone — that is what takes
the standard error from ±0.35 (shared stream) to ±0.06–0.13 at n 500. Raise
the lab's `N` when a new card lands within 2·se of a band edge.

## 3. The AI gets a fixed per-season allowance

Per league in `data/leagues.json`:

| Field | Meaning |
|---|---|
| `ai_cards_per_season` | total cards dealt across the roster at season start |
| `ai_hand_max` | cap per shooter |
| `ai_pool` | ids the dealer draws from (rarity-weighted like the drops) |
| `card_parity` | the target ratio for the envelope (§4) |
| `ai_cards` | **signature cards**: `{shooter: [ids]}`, always dealt, counted inside the allowance |

`CardRewards.ai_hands(league, seed)` deals: every shooter starts from its
signature cards, then the remainder of the allowance goes one card at a time,
rarity-weighted from the pool, to a seeded shooter still under the cap.
`Season.create()` stores the result in the season doc as `cardHands`,
`league_heat_config()` hands the opponent its season hand, and
`Campaign.apply_live_result()` removes what it played. **AI cards are
consumed like the player's**: a shooter that burned its Ice on you in round
one meets you clean in round two. Seasons saved before hands existed get
theirs dealt on first use from the season seed (`Season.ensure_card_hands`).

`LeagueData.validate()` rejects unknown ids in `ai_cards` / `ai_pool`, an
authored hand over the cap, and authored totals over the allowance.

## 3b. Drops (league heats, 2026-10-19)

`CardRewards.roll(ctx, seed) → {id, reason}` (`core/cards/card_rewards.gd`, headless,
seeded by the campaign so a replayed season rolls the same; every number in
`data/cards.json` → `drop_odds`):

- **The pool** is every card with `level ≤ the player's level + level_ahead (1)`; the
  rarity weights apply inside it, falling back to any eligible card; none eligible → no
  drop. Equip gating is unchanged: a card from one level up waits dimmed with its LVL chip.
- **A win** rolls at `win` (0.6), `+ playoff_bonus` (0.15) in the playoffs, `+
  comeback_win_bonus` (0.2) when trailing at the regulation midpoint (`Heat.half`, the
  scores when the clock passes half — reason `comeback_win`).
- **A loss** drops nothing, except: lost by `≤ close_margin` (2) or in overtime → a roll at
  `close_loss` (0.35, reason `close_loss`); the `loss_streak_n`-th (4th) straight league-heat
  loss → the `loss_streak_card` (Ice, level 1, always eligible), guaranteed (reason
  `loss_streak`). The counter lives on the league doc (`lossStreak`) and resets on any
  league win; it rolls on (the 8th straight pays again). Quick heats pay nothing.
- **Difficulty**: `difficulty_mult {easy, normal, hard}` (all 1.0 for now) scales the
  rolls — never the streak Ice — from the AI DIFFICULTY setting.
- **The loadout** is picked before every league heat on the pre-match page built for
  online (the league's bucket, only cards at or under your level, a 12 s clock
  (`prematch.league_seconds`) falling back to the last loadout); the league hub's CARDS
  tab shows YOUR CARDS and the SHOP only.
- **The result screen** says why (`COMEBACK CARD`, `CLOSE ONE`, `TOUGH STRETCH · HERE'S AN
  ICE`) and, in a loss, the bright spots (`core/match/bright_spots.gd`: `NEW BEST STREAK ·
  9`, `8 SWISHES · YOUR MOST`, `SHOOTING 62% · UP FROM 51% · LAST 10`, against the
  running bests on `career.bright`).

## 4. The area envelope

`CardBudget` (headless) computes, per league and per season:

- **AI budget** = Σ signature-card power (that league's measured power) +
  (allowance − signature count) × the pool's rarity-weighted mean power.
- **Player income** = expected drops under § 3b's rules (regular games at a
  coin-flip win rate: a win at `win + comeback_win_share × comeback_win_bonus`,
  a loss at `close_loss_share × close_loss` — the shares from `drop_odds.reference`
  — plus ~4 playoff games with the playoff bonus, at the normal difficulty
  multiplier) × the rarity-weighted mean power of the cards the player can
  PLAY in that league (level below the league's cap — `CardBudget.usable_ids`;
  a card that opens at the cap is the next league's), plus the expected
  streak Ices (`expected_streak_cards`, a Markov chain over the loss counter)
  at the Ice's power, plus what an assumed share of the ticket income
  (win/loss/title rewards × `economy.json` → `cards.ticket_share`, 0.5 —
  informational) buys at the shop at the mean price.
- **Parity** = AI budget ÷ player income.

Rules the suite enforces (`CardBudget.problems()`):

1. every card has a measured power in every league;
2. every card's rarity is its band and its price is on the curve (§2);
3. `card_parity` never falls along the unlock chain (a harder league never
   hands its AI *less* card power than the league before it);
4. no signature hand carries more than one epic-band card.

**Parity is reported, not gated** (2026-10-19, one currency —
docs/ECONOMY.md). Since the wallet is global, how much of it a player puts
into cards rather than PEGGY is theirs to choose, and Ross's call is that
league card buying exists to relieve friction, not to balance the AI. The
ledger prints each league's ratio beside its target with a remark
(`near 0.50`, `above 0.85 (not gated)`); the ±20 % check that used to be
rule 3 is gone from `problems()` and the suite. Card inventories are still
per league, so the AI side of the envelope is the real thing.

Shipped envelope (2026-09-22): cage allowance 6 (3 signature) → AI 4.2 power
vs player income 9.9 → parity **0.42** against a target of 0.5 (the open
league runs player-favoured); beach allowance 10 (8 signature) → 8.1 vs 9.8 →
**0.82** against 1.0. Each league's player income is ~8 drops and ~6 shop
buys a season. Re-run 2026-09-27 with the city (allowance 14, 8 signature,
target 1.0) and playable-only income: cage allowance 5 → parity 0.53, beach
0.83, city 1.18 — see `tools/card_ledger.gd` for the live numbers.

Re-run 2026-10-03 after the difficulty ladder (docs/LEAGUE.md: weaker rosters,
`err_mult` 1.0 everywhere): ice measures 0.78 / 0.50 / 0.48 (mean 0.59 → **common**,
price 100 — a rim nobody gets hot on freezes less), fire7 0.95 (rare, 170 ok), vortex6
1.05 / 1.89 / 2.04 (epic, price → 390). The beach's parity fell to 0.65 with its
eight authored ice cards, so its target is now **0.7** (cage 0.5 → beach 0.7 → city
1.0 along the chain); the city's allowance drops 14 → 12 so it measures ~1.1 against 1.0
(the cheaper shop buys the player more cards, which had pushed it to 1.26).

## 5. What is deliberately not modelled

- **Unwatched games are card-free.** `QuickSim` (the 26 of 28 league games
  the player doesn't play, and SIM THIS DAY) never sees a card. AI cards only
  ever play *against the player*, in live heats. The envelope is therefore
  about the player's experience, not the standings.
- **Cards played never appear in postgame stats.** `Heat.result()` records
  `cardsPlayed` per side for the season bookkeeping only; the result screen
  shows makes, shooting, swishes, streaks, bonus and *iced over* (a natural
  stat that includes card ice), never a card count.

## Heat Check's window (changed 2026-09-27)

`TimeTrial.light_rim` lends the streak up to `FIRE_AT`; when the window
closes on the clock (or the rim ices) the loan is withdrawn and the makes
shot under it stay a real streak, capped under `FIRE_AT` — the fire goes
out, the shooter earns the next one. A miss still puts the fire out and
breaks the streak — a miss *shot under the card*: since 2026-10-25 each
flight remembers whether the fire was on when it left the hand, and a ball
already in the air when the card is played that then misses only breaks
the streak the card found (the loan becomes the whole `FIRE_AT`, so the
makes under the card still stay a streak at the close) and counts toward the
cold streak; the fire burns on (`outcome.fire_kept`, Ross's bug). Before this the
close hard-reset the streak to 0, which the card lab caught as a NEGATIVE
power in the city (−0.84 ± 0.26): a strong shooter lost the streak the card
had helped build, then shot the next five makes at base points.

## The Magnet (`magnet6`, level 5, the city) — was the Vortex until 2026-10-23

A self card with a 6 s window (`TimeTrial.magnetize_rim` / `magnet_left`,
the fire window's shape; design "Magnet Card FX" 38b). Ross swapped the
Vortex for it because its animation was the one that worked; the rule
changed with it:

- **The pull is decided at release.** With `SimGeometry.magnet` on,
  `ShotSim.create_shot` replays the launch once without the magnet
  (`_magnet_predict`, deterministic, ~one extra sim per shot). A **make is
  left alone** (a swish stays a swish, a rattle-in is the same shot). A miss
  is measured by `ShotSim.free_landing`: where the launch's collision-free
  arc would cross rim height on the way down, and how far that point is
  from the rim centre — **a full circle**, the same ring short, long or to
  the side (Ross, 2026-10-26). A **miss landing within `effect.pull_m`**
  (0.5 m from the centre, data — about one ball-width beyond the iron) is
  pulled: at 2/3 of the time the unpulled ball would first reach the rim
  (`first_reach`: iron, board or the rim plane) the bolt strikes
  (`magnet_pull` event, before any iron), the ball is dragged in 4 stepped
  jerks over 0.36 s to a hover 20 cm above the rim (3 cm toward the
  shooter, 2 cm aside), held 0.12 s, then released straight down so the
  normal stepper fires `enter` and the make. `ShotClassify` downgrades a
  pulled entry to MAKE: **never a swish, 1 point** (+ the streak tier). A
  wide miss or an airball (never reaches rim height) is untouched, and so
  is a hard board miss whose arc would land past the ring — before
  2026-10-26 the measure was the distance at first contact, which sat at
  ~0.26 m for every board hit (the board is 0.38 m behind the centre) and
  ~0.35 m for a front-iron clank, so long misses were always pulled and
  short ones almost never. The prediction uses the geometry of the moment;
  the drag reads the live geo, so the moving board keeps the ball.
- **The streak freezes.** A shot released under the magnet (`flight.magnet`)
  that scores pays `StreakRules.points_for` at the streak you already had
  (`outcome.streak_frozen`) and does not grow it; the counter you had is
  yours again when the window closes. A real miss under it still breaks the
  streak (and puts the fire out) — the magnet protects nothing. Fire and
  magnet can be on together: the fire's lent streak just stops climbing.
- The window ends on the clock (after the last pending ball lands) or when
  the rim ices (`magnet_off {reason: time|ice}`); a miss does not end it.
  Ice has precedence: no prediction, no pull on an iced rim.

The show (`game/view/rim_magnet.gd` `RimMagnet`, under the rim pivot via
`CourtGeometry.set_magnet` / `magnet_follow`): a red low-poly horseshoe pops
up 0.52 m over the rim with a 7-step spring, bobs, and throws stepped gold
zaps from its silver tips to the front of the ring (12 fps, hidden every
third step); on `magnet_pull` a forked bolt locks onto the ball with six
spark rays until the release; SPENT pops it down in 4 steps, ICED tints it
pale blue and drops it. Tray tag `MAGNET · 6S` in the card's red; marquees
MAGNET / MAGNET SPENT / MAGNET ICED; a ZAP rim pop on the strike. Built
from primitives with runtime 16×16 pixel textures: ≤ 6 draws, no lights.

Its power in `card_power.json` is **the Vortex's measurement carried over**
(the `placeholder` note in the file) until `tools/card_lab.gd -- magnet6`
is run for it (~27 min, other cards kept) — Ross's call.

## Online matches (2026-10-07)

Cards play in online 1v1 too, from a separate **online** bucket that lives on
the server (docs/BACKEND.md → Cards online): only cards the server ledger
holds can be brought into a room, the server deals both validated hands, and
a play is a relayed, receipted message. Online cards are **never bought**
(docs/ECONOMY.md → The rule: no path from real money to online cards; the
online shop and wallet were removed 2026-10-19). The level rule is the leagues' (`Progression.can_use`),
checked on the phone and again on the server — and since 2026-10-19 **the
card cap** (docs/BACKEND.md → Ranked): in every online match both loadouts
stop at the lower of the two verified levels, picked on the pre-match page
and validated by the room, so a level-5 Magnet never meets a level-2 player.
`data/online_drops.json` → `card_min_tier` adds a ladder-tier floor per card
(ice and fire7 from ROOKIE, the Magnet from STARTER). There is no parity
envelope online; `card_parity` and `CardBudget` remain per league. AI cards
never meet online hands.

### Online cards: where they come from (Ranked Stage B, 2026-10-23)

Only from what the server witnessed, all in `data/online_drops.json`
(docs/BACKEND.md → Ranked Stage B has every rule; `tools/online_ledger.gd`
the numbers):

1. **Spoils** — a rated win takes every card the loser played (the winner's
   own played are spent). Forfeit: the leaver's played to the stayer. A loser
   on 3+ straight played losses keeps one (insurance). The 3rd game against
   the same opponent in a day pays none.
2. **The drop meter** — every rated result adds points (win 10, close loss
   8, loss 3, + 4 for the day's first win); a full meter (22, derived so the
   reference player earns `weekly_card_target` 5 cards a week from all
   sources) drops one card by the tier's rarity odds (`rarity_by_tier`) over
   what the verified level and `card_min_tier` allow. The odds show on the
   post-match page and the rewards page.
3. **The streak Ice** — the 4th straight played loss, once a day.
4. **Logins** — cumulative distinct days: the first login, days 1 / 3 / 7 /
   10 / 30, a welcome-back card after 7+ days away; CLAIMed on the rewards page.
5. **Milestones** — one-time grants by key (first match / win / spoils, win
   counts, every rank band reached by peak), CLAIMed the same way; the keys
   mirror to the Platform facade for the store achievements later.

Never from tickets or money (docs/ECONOMY.md → The rule).

## Adding a card

1. **Row** in `data/cards.json`: `id, name, target, effect {kind, …}, art,
   blurb, level` (the league band edge it opens at — docs/PROGRESSION.md;
   a card is playable only from its level, ownable before it). Leave
   `rarity` and `price` for step 4.
2. **Effect**: a new `kind` needs `CardEffects.apply` / `can_apply` (and the
   `TimeTrial` hook it drives) plus `CardEffects.KINDS`; a new duration or
   magnitude of an existing kind is just the JSON row.
3. **Art** (design "Card Icons" 9a): a 96×128 face PNG — frame, target
   badge, name plate, empty art area — in `assets/textures/cards/` and a
   horizontal sprite strip beside it, both from the design project's
   export; the card's `fx` row says how to run it: `{sheet, frames, fps,
   rect: [x, y, w, h]` (where the loop sits on the face, in face pixels),
   `chip: [w, h]` (the sprite's size in the 40 px chip), `chip_bg` (the
   chip's colour), `glyph` (a small static icon for the tray tag and the
   deal caption, `assets/ui/cards/`)`}`. `CardDefs.validate_fx` checks the
   row; the suite checks the files and that the sheet is `frames × w` by
   `h`. `game/ui/card_face.gd` (`CardFace`) draws it everywhere — the tray,
   the deal, loadout, spares, shop, the drop and the chips. Only
   `card_back.png` is still generated (`gen_card_textures.lua`).
   Magnet (`magnet6`, 2026-10-23, design "Card Icons" 10a): `card_magnet6.png`
   + `fx_magnet.png` (16 frames at 12 fps, rect `[16, 29, 64, 56]`, chip
   36×32 on `#4A1410`) and `glyph_magnet.png`, all from the design export
   (the Vortex's files and its Lua glyph are gone). The PNGs come from the
   design project's export zip (DesignSync base64 does not transcribe
   reliably past ~1 KB), copied straight in and re-imported. The loop is the
   export's `assets/cards/fx_magnet.png` — the sheet the design page itself
   renders (held still, the bolt flaring bottom-right, sparks); the
   `assets/textures/cards/` copy in the export was an earlier iteration.

## Adding a league

1. The row in `data/leagues.json` with the five card fields. Pick
   `card_parity` ≥ the league it unlocks after (rule 4), and an allowance
   that lands inside ±20 % of it — the ledger tells you where it landed.
2. `tools/card_lab.gd` (every card is measured per league, so a new league
   needs its own numbers), then `tools/card_ledger.gd`, then the suite.

## Reading the ledger

```
CARD POWER  (assets/cards/card_power.json: n 500, seed 4242, 2026-10-03)
  card     rarity  price  power cage/beach/park/city       mean  band  price curve
  ice      common     80  +0.78±0.07 / +0.50±0.06 / +0.59±0.00 / +0.48±0.09  +0.59  ok    ok (70)
  fire7    rare      140  +0.97±0.07 / +0.97±0.08 / +0.95±0.00 / +0.91±0.09  +0.95  ok    ok (140)
  vortex6  epic      290  +1.05±0.09 / +1.89±0.13 / +1.66±0.00 / +2.04±0.15  +1.66  ok    ok (290)
  scale: common 0.0–0.7, rare 0.7–1.4, epic 1.4–99.0; price = round10(150 · power^1.30) ±20%

AREA ENVELOPE  (per season; … tickets × share 0.50 bought at the mean price — reported, not gated)
  league   allow authored    dealt   AI pwr |  drops  tickets   bought  PLR pwr |  ratio target
  cage         5  3 (2.5)  2 (1.7)     4.22 |   8.25      498     1.46     7.58 |   0.56   0.50 near 0.50
  beach       10  8 (4.0)  2 (1.3)     5.33 |   8.25      558     1.64     6.57 |   0.81   0.70 near 0.70
  park        11  6 (4.2)  5 (3.6)     7.82 |   8.25      607     1.79     7.16 |   1.09   0.85 above 0.85 (not gated)
  city        12  8 (7.4)  4 (3.1)    10.45 |   8.25      656     1.93     7.79 |   1.34   1.00 above 1.00 (not gated)

OK — every card on the scale, every league inside its envelope.
```

(2026-10-19: the park's powers are the mean fallback — `card_power.json`
has no park entry yet, the three parked `measured in park` reds.) `band` and
`price curve` say `ok` or what they should be; the envelope row ends with
the parity remark; the tool exits non-zero with `DATA` / `RULE` lines when
anything is off. Run it whenever `cards.json`, `leagues.json` or the lab
output changes.
