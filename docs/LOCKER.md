# The locker and PEGGY — how balls are won (2026-10-01)

The locker (the ball icon on the home page, `game/ui/locker_panel.gd`) has
two tabs. **PEGGY** is a ticket-fed drop machine: aim a puck along a rail,
hold the big red button while a ticket feeds in, and the puck rattles down a
peg board into one of seven prize slots. Whatever ball sits in that slot is
yours. **BALLS** is the collection: owned balls equip on tap, the rest show
their rarity. Hoops are still bought for tickets under the collection
(`App.try_buy("hoop", id)`); **balls are never bought**, `try_buy("ball", …)`
refuses. Never call the machine "Plinko" anywhere in the game — it is PEGGY.

## The rules

- A drop costs **300 tickets** (`PeggyPrizes.DROP_COST`), about 25 minutes
  of trials: an *entry* purchase in the economy's tiers (docs/ECONOMY.md).
- Every ball has a **rarity**: `common` (one colour, classic seams), `rare`
  (coloured panels, classic seams), `epic` (patterns under the seams —
  camos, stripes, spots, checks, gradients), `legend` (seamless wrapped
  designs — the pumpkin, the smiley, the beach ball …). `BallSet.rarity`,
  authored in `tools/aseprite/gen_ball_wrap.lua`'s `STYLES` table.
- **Level gates match the areas.** Common and rare from level 1 (the cage),
  epic plates from level 3 (the beach), legend plates from level 5 (the
  city). `PeggyPrizes.layout(level)`, outer plates rarest:
  lvl 1–2 `R C C C C C R`, lvl 3–4 `E R C C C R E`, lvl 5+ `L E R C R E L`.
- **Plates only ever show balls you do not own.** Each plate draws from the
  unowned balls of its rarity. When a rarity is exhausted the plate
  **promotes** to the next rarity up that still has one at your level, then
  falls back down. Plates prefer seven different balls, but as the roster
  thins the same ball sits on several plates — the last ball of all is on
  every plate — so nothing ever stalls on a 4 % slot. Only when nothing
  unowned is left at your level does a plate show the ticket glyph and pay
  **150 back**.
- A win pops the card: NEW BALL · name · rarity · n/47 · **SET AS YOUR
  BALL?** EQUIP / KEEP · AGAIN. An epic or legend pull takes the screen with
  rotating rays (`game/ui/prize_rays.gd`) and the jackpot fanfare.
- A ball you have won but not looked at on the BALLS tab is **unseen**: the
  home page's locker icon carries a gold dot (`IconButton.badge`) until the
  tab is opened (`App.unseen_balls()` / `mark_balls_seen()`).

## The board (`core/locker/peggy_board.gd`)

Headless float64 physics, `DetRng` only, same seed → same path. Board
units, 1 u = 0.1 m on the cabinet; origin at the slot floor's centre:
walls at ±3.5, seven 1.0-wide slots, dividers to 1.2, ten rows of pegs
(r 0.12, pitch 1.0, row pitch 0.8, six and five a row), every row flanked by
r 0.30 wall bumpers (a scalloped wall: no V-pocket, every gap ≥ 0.58 against
the 0.50 puck), puck r 0.25, g 98, restitution 0.30 on pegs and 0.50 on
walls, ±4° jitter on each hit, dt 1/240. The puck is released at rest from
the rail; the rail travels **±1.0 u** (`AIM_MAX`, the end-stops sit over the
inner edges of the second slots). `simulate(aim, seed)` returns the 60 Hz
path, the hits (for the ticks and flashes), the slot and the duration;
`odds(aim, n)` the seven probabilities.

Measured (`tools/peggy_ledger.gd`, 1500 drops per aim):

| aim | s0 | s1 | s2 | s3 | s4 | s5 | s6 |
|---|---|---|---|---|---|---|---|
| end-stop −1.0 | 16.7 | 20.8 | 27.1 | 21.4 | 9.3 | 3.1 | 1.5 |
| centre 0.0 | 4.7 | 9.7 | 22.4 | 27.7 | 21.7 | 9.1 | 4.7 |

So from the centre an edge plate is "every once in a while" (~5 % each,
~9 % for the pair); aiming at the end-stop makes that edge ~17 % — a skill
lever, not a free epic. Honest physics cannot keep a full-width edge release
rare (~33 %), which is why the rail's travel is the knob (`AIM_MAX` 1.5 →
~22 %).

By level, a drop from the centre / the end-stop pays:
lvl 1 rare 9 / 18 %; lvl 3 epic 9 / 18 %, rare 19 / 24 %; lvl 5 legend
9 / 18 %, epic 19 / 24 %, rare 44 / 37 %.

## The economy

Balls are priced 0; `EconomyBudget.peggy_tickets()` is the expected cost of
winning the whole roster (`PeggyPrizes.expected_tickets_to_complete`, 60
seeded collection runs at the centre aim) and `catalog_hours()` is the hoops
plus that. Shipped: 46 balls to win, 13,800 tickets expected (300 a ball —
no drop is wasted), 18.8 h; with the hoops 19.8 h, inside the 15–35 h band.
At level 1 the 20 reachable balls take 6,000 tickets; at level 3, 36 balls
10,800. Rules in `EconomyBudget.problems()`: a drop is an entry purchase,
the roster is payable, a ball costs at most 1.35 drops, every ball is rated
and unpriced.

## The save and the seed

`cosmetics.peggy.drops` counts completed drops; `settings.newBalls` the
unseen ids. `App.peggy_seed(i)` = `DetRng.hash_seed(client id + i)`: the
plates you see (`App.peggy_slots()`, from the current drop index) are the
plates the drop pays, and the index moves only when a drop completes —
releasing the button early spends nothing. `App.peggy_drop(aim)` spends,
simulates, grants (or refunds), advances, and returns the prize record
(`last_prize`).

## The cabinet (`tools/blender/build_peggy.py` → `assets/locker/peggy.glb`)

Built from the same peg table (`PEGS` mirrors `PeggyBoard.pegs()`;
`tests/test_peggy.gd` checks every mesh against the core within 1 mm).
Node names are the runtime contract (`game/ui/peggy_machine.gd`):
`Peg%03d` ×55, `Bumper%03d` ×20, `Divider%d` ×6, `SlotPlate%d` /
`SlotLight%d` / `Prize%d` / `Frost%d` ×7, `Bulb%03d` ×18 (the marquee
chase, `bulb.gdshader`), `Rail`, `Carriage`, `EndStopL/R`, `Puck`,
`Button`, `BtnCap`, `TicketHome` / `Ticket`, `Glass`. Textures:
`tools/aseprite/gen_peggy_textures.lua` (cabinet, marquee, board, button
up/down, ticket, the rarity plates, the light strip, and the UI's
`icon_ticket.png`). The prize balls are the shared classic mesh with each
ball's skin, scaled 0.29, behind a frosted pane.

The machine lives in a `SubViewportContainer` with its own world
(600×840, camera fov 40 at (0, 1.42, 2.62)); drag in the top 150 px to aim,
press in the button rect to feed. Sounds (`tools/gen_sfx.gd`): `peggy_press`,
`peggy_servo` (a flat loop while the carriage moves), `peggy_ticket`,
`peggy_peg_0..2` (pitched up with each hit), `peggy_win`, `peggy_jackpot`.

## Adding a ball

1. One row in `STYLES` (`gen_ball_wrap.lua`) with its `rarity`; run the
   Aseprite script.
2. `python3 tools/gen_ball_sets.py` (writes the `.tres`, refuses a priced or
   unrated ball); paste the line into `CosmeticLibrary.BALLS`.
3. `build_ball_lineup.py -- --render --thumbs` for the lineup and the
   96 px thumbnails the BALLS tab shows.
4. `godot --headless --path . --import`, the suite, `tools/peggy_ledger.gd`.

QA: `godot --path . --resolution 360x640 -- --qa-peggy` (open, aim, hold,
drop, card, the staged epic page, the badge, the BALLS tab).
