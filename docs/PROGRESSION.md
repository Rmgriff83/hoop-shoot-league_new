# Progression — the player's level (2026-09-26)

One number, global to the player: their **level**, earned only by playing
league matches. It ties three things together and will carry into
multiplayer as-is:

- **Areas.** Each league spans a band of levels and caps there; reaching the
  cap opens the next area (the whole area: league, time trial, practice).
- **Cards.** Every card has a level. You can own one early (a drop, the
  shop) but you cannot play it until you reach its level. Each league's cap
  is the next card's level, so grinding a league always ends at the next
  card up the power structure.
- **Fairness later.** Multiplayer matchmaking and card eligibility will read
  the same level, which is why nothing bought with money can move it.

The rule of the house (docs/CARDS.md): every number lives in data, is
computed by a headless `core/` class, printed by a ledger and enforced by a
test. Here: `data/progression.json` + the `levels` / `unlock` / `xp_mult`
rows in `data/leagues.json` + `level` on each card in `data/cards.json`;
`core/progression/progression.gd` (`Progression`) and
`progression_budget.gd` (`ProgressionBudget`); `tools/progression_ledger.gd`;
`tests/test_progression.gd`.

## 1. Levels and bands

`xp_per_level = 100`, `start_level = 1`: level = `1 + floor(xp / 100)`. The
save's `progress` part holds `{xp, seasonXp, seasonKey}`.

| League | Band | Opens at | Cap (XP) |
|---|---|---|---|
| Arcade (cage) | 1 → 3 | — | 200 |
| Beach | 3 → 5 | level 3 | 400 |
| City | 5 → 7 | level 5 | 600 |

A league's matches never push XP past its cap (`Progression.apply_match`
clamps; `capped` says so). The next league starts where this one caps and
`unlock.level` is that cap — `Progression.validate()` refuses data that
breaks the chain, and every card's level must be a band edge.

| Card | Level |
|---|---|
| Deep Freeze (ice) | 1 |
| Heat Check (fire7) | 3 |
| Vortex (vortex6) | 5 |

## 2. A match's XP

```
raw  = win ? 9 : 2
     + 0.4 × swishes
     + (best streak ≥ 8 ? 4 : ≥ 5 ? 2 : 0)
     + (won by 10+ ? 2 : 0)
     + (won in OT ? 1 : 0)
raw *= playoff ? 1.5 : 1
raw *= league.xp_mult
```

**Season soft cap** (`season_soft_cap 100`, `over_cap_rate 0.25`): XP earned
in one league season past 100 counts at a quarter, so a monster season lands
about a level and a third, not two. (`seasonKey` = `league:year`; a new
season resets the count.)

**The title** (`Progression.apply_title`): straight to the league's cap,
from anywhere in the band. Winning the Arcade League at level 1 makes you
level 3 and opens the beach at once.

## 3. Pacing (the ledger, 14-game seasons, no title)

| Season | Record · swishes · best streak | Season XP | Levels | Band |
|---|---|---|---|---|
| Terrible | 1-13 · 1 · 2 | 35 | 0.35 | 0.30–0.50 |
| Awful | 3-11 · 2 · 3 | 63 | 0.63 | 0.45–0.70 |
| Decent | 7-7 · 4 · 5 | 108 | 1.08 | 0.85–1.20 |
| Strong (+ 5 playoff games) | 11-3 · 6 · 6 | 137 | 1.37 | 1.20–1.50 |

So level 1 → 3 is about two decent seasons, three-plus bad ones, or one
title — and the beach opens with Heat Check usable the moment you arrive.
`ProgressionBudget.problems()` holds every archetype inside its band and
the title at the cap; the suite runs it.

## 4. Where it shows

- **Home** — the `LVL0n` element and its meter (progress inside the level);
  the ticker's `LEVEL 2 · 64/100 XP`. A locked area's LEAGUE, TIME TRIAL and
  PRACTICE cards are disabled with `LOCKED · LEVEL 3`; the league card
  reads `LOCKED · REACH LEVEL 3`. `App.start_area` and `enter_league` refuse
  a locked area / league (`App.league_gating`, on in release builds only).
- **Match** — a card above your level sits in the tray dimmed with a
  `LVL 3` chip and will not play; the loadout float greys its name with the
  level; the shop shows a `LVL n` chip per card (gold once you have it).
  Buying and drops are never gated.
- **Post-match** — `+28 TICKETS · +18 XP` on the coins card and a level
  line under the opponent: `LEVEL 1 · 64/100 XP`, `LEVEL UP · LEVEL 2`
  (gold) or `LEVEL 3 · CAP`.

## Difficulty

The AI side of a league's difficulty is the roster's ratings and `err_mult`, measured in
points by `tools/league_lab.gd` — see docs/LEAGUE.md → Difficulty ladder (fewer pushovers
per league, not stronger stars). The player's side is the area's hoop geometry.

## Adding a league

Give it `levels: {min: <previous cap>, cap: <min + 2>}`, `unlock: {level:
<previous cap>}`, `xp_mult` (1.0 unless its matches should pay differently),
and put the cards that should open with it at `level: <its min>` or `<its
cap>`. Run `tools/progression_ledger.gd`; the suite's `test_progression.gd`
is the gate.

## Adding a card

Set `level` to the band edge where it should open (the cap of the league
whose grind earns it). `tools/progression_ledger.gd` lists it; a level that
is not a band edge fails `Progression.validate()`.

## Not modelled (yet)

- Anything above level 7: the next league adds the next band.
- Multiplayer's use of the level (matchmaking, card eligibility) — the
  level is global and saved, that is all the hook it needs.
- Prestige / resets; time-trial XP (by decision: leagues only).
