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

## 4. The area envelope

`CardBudget` (headless) computes, per league and per season:

- **AI budget** = Σ signature-card power (that league's measured power) +
  (allowance − signature count) × the pool's rarity-weighted mean power.
- **Player income** = expected drops (regular games × drop odds at a coin-flip
  win rate, plus ~4 playoff games with the playoff bonus) × the rarity-weighted
  mean power, plus what the coin income (win/loss/title rewards) buys at the
  shop at the mean price.
- **Parity** = AI budget ÷ player income.

Rules the suite enforces (`CardBudget.problems()`):

1. every card has a measured power in every league;
2. every card's rarity is its band and its price is on the curve (§2);
3. every league's parity is within **±20 %** of its `card_parity`;
4. `card_parity` never falls along the unlock chain (a harder league never
   hands its AI *less* card power than the league before it);
5. no signature hand carries more than one epic-band card.

The wallet *is* per league (docs/ECONOMY.md): coins earned in a league are
spent in that league's shop, and its cards play only there. So the envelope
is the real thing, not a simplification.

Shipped envelope (2026-09-22): cage allowance 6 (3 signature) → AI 4.2 power
vs player income 9.9 → parity **0.42** against a target of 0.5 (the open
league runs player-favoured); beach allowance 10 (8 signature) → 8.1 vs 9.8 →
**0.82** against 1.0. Each league's player income is ~8 drops and ~6 shop
buys a season.

## 5. What is deliberately not modelled

- **Unwatched games are card-free.** `QuickSim` (the 26 of 28 league games
  the player doesn't play, and SIM THIS DAY) never sees a card. AI cards only
  ever play *against the player*, in live heats. The envelope is therefore
  about the player's experience, not the standings.
- **Cards played never appear in postgame stats.** `Heat.result()` records
  `cardsPlayed` per side for the season bookkeeping only; the result screen
  shows makes, shooting, swishes, streaks, bonus and *iced over* (a natural
  stat that includes card ice), never a card count.

## Adding a card

1. **Row** in `data/cards.json`: `id, name, target, effect {kind, …}, art,
   blurb`. Leave `rarity` and `price` for step 4.
2. **Effect**: a new `kind` needs `CardEffects.apply` / `can_apply` (and the
   `TimeTrial` hook it drives) plus `CardEffects.KINDS`; a new duration or
   magnitude of an existing kind is just the JSON row.
3. **Art**: `tools/aseprite/gen_card_textures.lua` → `assets/textures/cards/`.
4. **Measure**: `tools/card_lab.gd -- <id>`. Read its power per league in
   the output; set `rarity` to `CardDefs.rarity_for(mean)` and `price` to
   `CardDefs.price_for(mean)` (nudge inside the tolerance if it feels wrong).
5. **Deal it**: add the id to the leagues' `ai_pool` where the AI should
   draw it, and to a shooter's `ai_cards` if it is a signature card. Raise
   `ai_cards_per_season` only if the ledger says parity has room.
6. **Ledger**: `tools/card_ledger.gd`. Every league must still be inside its
   envelope; if adding the card to the pool pushed a league out, lower that
   league's allowance or leave the card out of that pool.
7. **Suite**: `tests/run_tests.gd`. `test_card_budget.gd` is the gate;
   `test_cards.gd` covers the effect and policy.

## Adding a league

1. The row in `data/leagues.json` with the five card fields. Pick
   `card_parity` ≥ the league it unlocks after (rule 4), and an allowance
   that lands inside ±20 % of it — the ledger tells you where it landed.
2. `tools/card_lab.gd` (every card is measured per league, so a new league
   needs its own numbers), then `tools/card_ledger.gd`, then the suite.

## Reading the ledger

```
CARD POWER  (assets/cards/card_power.json: n 500, seed 4242, 2026-09-22)
  card     rarity  price  power cage/beach                 mean  band  price curve
  ice      rare      150  +0.61±0.06 / +0.85±0.13         +0.73  ok    ok (130)  NEAR EDGE 0.70 (±0.07): …
  fire7    common    100  +0.78±0.07 / +0.55±0.13         +0.67  ok    ok (120)  NEAR EDGE 0.70 (±0.07): …
  scale: common 0.0–0.7, rare 0.7–1.4, epic 1.4–99.0; price = round10(200 · power^1.30) ±20%

AREA ENVELOPE  (per season; player income at p_win 0.50, 4 playoff games, title p 0.20)
  league   allow authored    dealt   AI pwr |  drops    coins   bought  PLR pwr |  ratio target
  cage         6  3 (2.0)  3 (2.2)     4.16 |   8.25      690     5.52     9.92 |   0.42   0.50 ok
  beach       10  8 (6.8)  2 (1.3)     8.11 |   8.25      845     6.76     9.83 |   0.82   1.00 ok

OK — every card on the scale, every league inside its envelope.
```

`band` and `price curve` say `ok` or what they should be; the envelope row
ends `ok` or `OUT`; the tool exits non-zero with `DATA` / `RULE` lines when
anything is off. Run it whenever `cards.json`, `leagues.json` or the lab
output changes.
