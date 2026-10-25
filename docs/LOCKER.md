# The locker and PEGGY — the collection, and how balls and nets are won (2026-10-01, pages 2026-10-15, the carnival cabinet 2026-10-15)

The **locker** (the ball icon on the home page, `game/ui/locker_panel.gd`)
is a page over the area (docs/HOME.md → Pages, design "Store and Locker"):
your collection, nothing more. **BALLS** lists the balls you own in a
4-wide grid of dotted tiles (the one in use gold, "IN USE"; the rest
"EQUIP", tap to equip everywhere); **NETS** lists the nets you own, split by
a **COTTON / CHAIN sub-tab** since each kind hangs on different courts
(below). The tabs count what you own ("BALLS 9", "NETS 2"). No locked or
unowned tile is shown: **nothing is bought outright — tickets only ever
buy PEGGY plays, and both the balls and the nets are its prizes** (Ross,
2026-10-15). The **PEGGY button** beside the ticket chip opens the **PEGGY
page** (`game/ui/peggy_page.gd`): the carnival drop machine fills the
frame under `<` · the level chip with its XP meter · the ticket chip. Tap
**PLAY (300)** over the machine and a ticket flies into the console and
**credits** it (saved — leave and come back, the ticket is still in and
DROP still flashing); drive the crane with the joystick; tap **DROP** and
the puck rattles down the peg board into one of seven bays. Whatever hides
in that bay is yours. `<` returns to the locker; the locker's CLOSE returns
home. The hoop counter that used to
sit under the balls (buy for tickets, swap) is **closed for now**
(`App.HOOPS_IN_LOCKER = false`, 2026-10-07): `try_buy("hoop", …)` refuses;
the player's hoop stays the starter and the beach / city mandate their own.
**Balls are never bought**, `try_buy("ball", …)` refuses. Never call the
machine "Plinko" anywhere in the game — it is PEGGY.

## NETS (2026-10-15)

A net is a **look for the hoop's kind of net** (`game/cosmetics/net_set.gd`,
`NetSet`): `kind` is `cotton` (the nylon hoops: cage, beach) or `chain` (the
city's steel rim), `style` names the body `NetBodies` builds
(docs/BLENDER_101.md §28–32), `price_coins` is tickets. The feel — the nine
`net_*` knobs and the make sounds — stays on the court's `HoopSet`; a style
only changes what hangs. Nine nets ship (`assets/nets/<id>/net_set.tres`,
`CosmeticLibrary.NETS`): **Cotton** and **Chain** (the stock pair, free,
owned by every save), **Jack** (a jack chain, valued 600 — a *mid* tier),
**Ladder** (straight drops tied by hoop chains, 1000 — *premium*), **Wool**
(a hand-knitted net in twelve yarn colours, 700 — *mid*, for the nylon
courts), the **Neon Yellow** / **Neon Orange** cottons (the cotton body with
a `NetSet.tint`, 400 each — *entry*), **Red White Blue** (the heavy-duty
polyester net in colour bands, 500 — *mid*) and **Tattered** (the worn park
net, 2026-10-24: three hooks torn off, snapped pieces, loose strands, a
grimy grey-cream — valued 500, *mid*; §32). Every net but the stock pair is
a PEGGY prize (since 2026-10-15 nothing is bought outright; the value is the
economy ledger's tier). **Any
net hangs on any hoop** (Ross, 2026-10-16): a chain on the park's nylon rim,
cotton on the city's steel. What follows the choice is what you see and
hear — the body `NetBodies` builds, swung by `NetSim` on the **knobs of
that kind's reference hoop** (`CourtGeometry._knobs_hoop`: the chain hoop's
for a chain, the hoop's own for its native kind), the chain rattle / cotton
rustle AND the make clip — a hung net of the other kind borrows its reference
hoop's swish (`Sfx.hang_net`; fixed 2026-10-24, the park's chain used to
swish like cotton), the thumbnail. What stays the area's: the hoop
itself and the ball's physics (`SimGeometry` net drag / wall restitution,
the AI calibration, the golden grid). `App.net_kind_for_area` still names a
hoop's native kind, which is the stock fallback when nothing owned is hung.

- The **NETS tab** lists the styles you own under the COTTON / CHAIN
  sub-tab (a filter by kind; tile `Net_<id>`, the thumbnail from
  `assets/textures/nets/thumbs/<id>.png`, rendered by `--qa-net-thumbs` —
  the net alone, no rim), under a head "COTTON · TAP A NET TO HANG IT", with
  the kind line ("CHAIN") and a tag: **IN USE ON PARK + CITY** (the gold
  tile) or **EQUIP**.
  Tapping a net opens the **hang-it-where sheet** (`game/ui/net_area_sheet.gd`,
  `NetAreaSheet`, layer 35 over the locker; QA `locker_net_sheet.png`): the
  net's name and thumbnail, one row per area in `App.AREA_MODES` order
  (`Area_<id>`: the area, then what hangs there — gold **HANGING** when it is
  this net; an area the level has not reached reads **LOCKED · LVL n** and
  does nothing), **EVERYWHERE** (`App.select_net_everywhere`, now every
  area — PEGGY's prize-card EQUIP uses it too) and **CLOSE**. A row hangs
  the net on that area (`App.select_net(area, id)`, owned only) and the
  rows restyle in place; closing refills the tab. **Buying has no UI yet** (2026-10-15): the
  locker is the collection; `App.try_buy("net", id)` stays wired for the
  store page to come, and the economy still prices every style.
- The **pause menu**'s NET row (docs/HOME.md) cycles every owned net and
  hangs the pick on **that court only**
  (`App.select_net(area, id)`); its BALL row cycles the owned balls and the
  equip is global (`App.select("ball", id)`). Both swap live:
  `CourtGeometry.set_net`, `BallPool.set_ball_set`.
- Saved in `cosmetics.net = {"owned": [...], "selected": {area: id}}`
  (`SaveService.default_nets`, `migrate_cosmetics` backfills older saves and
  mirrored docs). `App.net_set_for(area)` falls back to the hoop's kind's
  stock net when a selection is unowned. `App.net_override` hangs a net
  everywhere without the save (QA, `--qa-jack` / `--qa-ladder`).
- **The kit** (2026-10-23, the opponent view): cosmetics DO go on the wire,
  as ids only. With every `loadout` a phone sends `kit {v: 1, ball, net,
  hoop?}` (`App.my_kit(area)`: our ball, the net we hang on that court, the
  hoop only in the cage where a player picks one); the room shape-checks it
  and relays it (`peer_loadout.kit`, `start.kits {a, b}` — docs/BACKEND.md).
  The receiving phone resolves the ids against ITS catalog
  (`CosmeticLibrary.resolve_kit`): an id it does not know — a newer build's
  net — falls back to the court's stock pair (the starter ball, the stock
  net of the court's hoop's kind), an unknown hoop to the court's own. The
  heat's PiP wears the result (`HeatScreen.pip_kit`); the pre-match page
  shows no opponent ball (Ross). Solo heats show the court's stock pair (a
  shooter in `data/shooters.json` may one day name a `kit`; none does).
  Our pause-menu swaps change our court only, never the window. No fit
  rule: any net hangs on any hoop, so `resolve_kit` is the one place a rule
  would live.

Adding a net: a body class (`extends ChainNet` for a chain, `CottonNet` for
cotton) registered in `NetBodies` — or, for a recolour, the cotton body with
a `tint` — a `.tres` with its kind, style and price,
one line in `CosmeticLibrary.NETS`, `--qa-net-thumbs` then `--import`, the
ledger (the price must land in a tier and keep the catalog in band).

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
- **PLAY then DROP.** PLAY spends the 300 and credits the machine
  (`App.peggy_insert_ticket`, `cosmetics.peggy.credit`); DROP spends the
  credit (`App.peggy_drop`, which refuses without one). The plates are
  fixed from the moment you arrive until the drop, so what you paid for is
  what you drop on.
- **Prizes stay hidden.** Each bay shows a generic ball or net outline with
  a gold "?" and a **rarity dot** (blue common, teal rare, pink epic, gold
  legend; `PeggyMachine.TIER_COLOR`). **Plates only ever hide prizes you do
  not own.** A ball plate draws from the unowned balls of its rarity; when
  a rarity is exhausted the plate **promotes** to the next rarity up that
  still has one at your level, then falls back down. Plates prefer seven
  different balls, but as the roster thins the same ball sits on several
  plates — the last ball of all is on every plate. **The nets:** while any
  net is unowned, one plate per drop (drawn by the seed) hides a net
  instead of a ball — the plate keeps its dot; nets have no rarity scale of
  their own — and every plate that would otherwise be empty hides a net
  too. Only when nothing unowned is left at your level does a plate pay
  **150 back**.
- A win pops the card: NEW BALL · name · rarity · n/47 BALLS · **SET AS
  YOUR BALL?** or NEW NET · name · n/8 NETS · **HANG IT ON YOUR COURTS?** —
  EQUIP / KEEP · AGAIN · 300 (AGAIN is the PLAY path). An epic or legend
  plate takes the screen with rotating rays (`game/ui/prize_rays.gd`) and
  the jackpot fanfare.
- A prize you have won but not looked at in the locker is **unseen**: the
  home page's locker icon carries a gold dot (`IconButton.badge`) until the
  locker opens (`App.unseen_prizes()` / `mark_prizes_seen()`).

## The board (`core/locker/peggy_board.gd`)

Headless float64 physics, `DetRng` only, same seed → same path. Board
units, 1 u = 0.1 m on the cabinet; origin at the slot floor's centre:
walls at ±3.5, seven 1.0-wide slots, dividers to 1.2, **twelve** rows of
pegs (the v2 carnival board: r 0.12, pitch 1.0, row pitch 0.8; even rows
five pegs between two r 0.45 wall bumpers, odd rows six pegs that stop
short of the walls — no V-pocket, every gap ≥ 0.76 against the 0.50 puck,
and no straight lane down the wall: the bumpers reach past the odd rows'
outer pegs), puck r 0.25, g 98, restitution 0.30 on pegs and 0.50 on
walls, ±4° jitter on each hit, dt 1/240, a seeded kick for a puck that
rests on a peg for a quarter second. The puck is released at rest from the
crane; the crane runs the rail **up to the bumpers, ±2.78 u** (`AIM_MAX`;
Ross chose full travel — a release against a bumper would only slam the
puck inward). `simulate(aim, seed)` returns the 60 Hz path, the hits (for
the ticks and flashes), the slot and the duration; `odds(aim, n)` the seven
probabilities. The peg radius is the knob that keeps twelve rows peaked:
9 mm pegs (the design's) read flat (16 % centre, 13 % edges).

Measured (`tools/peggy_ledger.gd`, 1500 drops per aim):

| aim | s0 | s1 | s2 | s3 | s4 | s5 | s6 |
|---|---|---|---|---|---|---|---|
| crane's stop −2.78 | 25.7 | 26.0 | 25.8 | 15.3 | 4.3 | 1.9 | 1.1 |
| half −1.39 | 17.2 | 24.3 | 30.3 | 16.1 | 7.5 | 3.0 | 1.6 |
| centre 0.0 | 7.1 | 10.4 | 21.7 | 24.7 | 21.0 | 8.8 | 6.3 |

So from the centre an edge plate is "every once in a while" (~6-7 % each);
parking the crane at the bumper makes that edge ~26 % — a skill lever, not
a free epic. Ledger bands: centre 18-40 %, an edge from the centre ≤ 10 %,
the near edge from the stop 15-40 %.

By level, a drop from the centre / the crane's stop pays:
lvl 1 rare 13 / 27 %; lvl 3 epic 13 / 27 %, rare 19 / 28 %; lvl 5 legend
13 / 27 %, epic 19 / 28 %, rare 43 / 30 %.

## The economy

Balls and nets are priced 0 (`NetSet.stock` marks the free pair);
`EconomyBudget.peggy_roster()` is the 47 balls plus the 9 nets,
`peggy_tickets()` the expected cost of winning everything from a fresh save
(`PeggyPrizes.expected_tickets_to_complete`, 60 seeded collection runs at
the centre aim) and `catalog_hours()` is the priced hoops plus that.
Shipped (2026-10-24, the tattered net in): 53 prizes to win (46 balls, 7
nets), 15,900 tickets expected (300 a prize — no drop is wasted), 24.8 h;
with the hoops 25.9 h, inside the 15–35 h band. At level 1 the 27 reachable
prizes take 8,100 tickets; at level 3, 43 prizes 12,900. Rules in `EconomyBudget.problems()`: a drop is
an entry purchase, the roster is payable, a prize costs at most 1.35 drops,
every ball is rated and unpriced, every net is unpriced with one stock net
per kind.

## The save and the seed

`cosmetics.peggy.drops` counts completed drops, `cosmetics.peggy.credit`
holds a fed ticket waiting for DROP; `settings.newBalls` the unseen ids
(balls and nets). `App.peggy_seed(i)` = `DetRng.hash_seed(client id + i)`: the
plates you see (`App.peggy_slots()`, from the current drop index) are the
plates the drop pays, and the index moves only when a drop completes —
releasing the button early spends nothing. `App.peggy_drop(aim)` spends,
simulates, grants (or refunds), advances, and returns the prize record
(`last_prize`).

## The cabinet (`tools/blender/build_peggy.py` → `assets/locker/peggy.glb`)

The v2 carnival cabinet (Ross's `peggy-cabinet-v2.js`, 2026-10-15): a face
of wavy sunburst wings under a marquee arch (`peggy_face.png`, alpha-cut),
twenty-five coloured bulbs with star glows along the arch and the wing
edges, the dark speckled board (`peggy_board.png`) with gold pegs and teal
wedge bumpers, orange acrylic bay walls over a black tray with a sloped
front, and a deep console (scaled 1.3, pulled forward) with the tilted
deck (`peggy_deck.png`: ◀ MOVE ▶ · DROP), the joystick and the big orange
DROP button with its halo and red X. No hall, floor or glass: the page
shows through. Built from the same peg table (`PEGS` mirrors
`PeggyBoard.pegs()`; `tests/test_peggy.gd` checks every mesh against the
core within 1 mm — a bumper's node sits at its sim circle's centre).

Node names are the runtime contract (`game/ui/peggy_machine.gd`):
`Peg%03d` ×66, `Bumper%03d` ×12, `Divider%d` ×6, `BayWall%d` ×8,
`Prize%d` (each with its `PrizeSprite%d` quad) / `SlotLight%d` ×7,
`Bulb%03d` / `Glow%03d` ×25, `Rail`, `Crane`, `Puck`, `Deck`, `Joy` /
`Stick` / `Knob`, `Btn` / `Cap` / `XMark` / `Halo`, `TicketSlot` /
`Ticket` / `SlotMark`, `BigTicket`, `Face`, `Board`, `TopBar`. Textures:
`tools/aseprite/gen_peggy_textures.lua` (the face, the board, the deck, the
big roll ticket, the bulb glow, the eight `peggy_mystery_<ball|net>_<rarity>`
sprites — the outline, the "?", the rarity dot — and the UI's
`icon_ticket.png`).

The machine lives in a `SubViewportContainer` sized by the page (it fills
the frame, 50 px past each side; transparent background; camera fov 36
fitted to the cabinet's 2.7 m at any aspect, at (0, 1.38, d) looking at
(0, 1.15, 0)) UNDER the page's head so `<` and the chip take their taps.
**The joystick** (a drag on the knob: the tilt is the finger's travel over
8 % of the width) drives the crane at 5.5 u/s while held, a servo whining;
**PLAY** (the page's overlay, `PeggyMachine.insert_ticket`) flies the big
ticket in — up from below the camera, a held beat, a shrinking swoop into
the console slot (2.1 s) — then `credited`: the cap glows orange with a
pulsing gold halo; **DROP** (a tap on the cap, `press`) spends the credit.
Locked (no credit, short of tickets): the cap grey, the X blinking; the
joystick still works. The bulb chase runs at 4 idle / 14 busy with a
four-bulb tail and flares on events; the landed bay flashes for 2.4 s,
then the puck returns to the crane. `game/ui/peggy_stick.gd` is unused.
Sounds (`tools/gen_sfx.gd`): `peggy_press`, `peggy_servo` (a flat loop
while the crane moves), `peggy_ticket` (the flight), `peggy_peg_0..2`
(pitched up with each hit), `peggy_win`, `peggy_jackpot`.

## Adding a ball

1. One row in `STYLES` (`gen_ball_wrap.lua`) with its `rarity`; run the
   Aseprite script.
2. `python3 tools/gen_ball_sets.py` (writes the `.tres`, refuses a priced or
   unrated ball); paste the line into `CosmeticLibrary.BALLS`.
3. `build_ball_lineup.py -- --render --thumbs` for the lineup and the
   96 px thumbnails the BALLS tab shows.
4. `godot --headless --path . --import`, the suite, `tools/peggy_ledger.gd`.

QA: `godot --path . --resolution 360x640 -- --qa-peggy` (the locker, PEGGY
sliding in, PLAY and the ticket flight, the credited cap, the crane at the
bumper, the drop, the card, AGAIN, the staged epic and net cards, the short
state, `<` back to the locker, the badge, the NETS tab, dark mode);
`--qa-hud` snaps the locker's slide, BALLS, NETS and the CHAIN sub-tab.
