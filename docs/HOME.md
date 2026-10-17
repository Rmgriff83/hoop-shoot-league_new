# Home screen — the retro card chrome over the live area (2026-09-26, design "Home League Context v2")

Ross's concept, implemented: see-through, dither-shadowed cards in the pixel
faces (cream palette or its dark twin) over a **full-screen live view of the
current area**. `game/screens/title_screen.gd` (a `Node3D`), widgets in `game/ui/`.

```
Court       full-screen CourtGeometry + Camera3D (TitlePan), under a mild scrim (0.25)
TopBar      [LVL01 + meter] [ball = locker]                   [coin 1,240] [menu]
AreaZone    ★ (one star per difficulty step, ArenaSet.title_stars)
            ARCADE CAGE (52 px, wraps at 430, dithered drop shadow) [⚔ ONLINE]
            big < > chevrons at the screen edges (y 520), dithered shadows too
Float       over the court above the area, only while the league is open (per tab)
Wash        a vertical gradient from clear at y 781 to dark gray (0.72) at the ticker
CardArea    a fixed box (y 781 → 1206) holding the home block or the league in context
  League    orange, 270 high: NAME — n TITLES / SEASON n · three numbers (RECORD ·
            PLACE · STREAK, or SERIES · ROUND · SEED) · ENTER LEAGUE > · dashed rule ·
            NEXT · @ NAME / DAY d OF 14; trophies overhang top-left, loadout chips top-right
  Pair      TIME TRIAL (gold, stopwatch, "BEST 29") · PRACTICE (teal, jersey, "NO CLOCK")
Ticker      flat strip at the very bottom, scrolling copy from the save
```
No bottom nav: the phone's safe area would push one up, and the space goes to
the cards. **Locker** (`game/ui/locker_panel.gd`, docs/LOCKER.md): a **page**
over the area (below) — BALLS, the balls you own (equip via `App.select`),
and NETS, the nets you own (COTTON / CHAIN sub-tab; a tap opens the
hang-it-where sheet — any net on any court, or EVERYWHERE); nothing unowned
is listed. Its PEGGY button opens the
**PEGGY page** (`game/ui/peggy_page.gd`), the carnival drop machine that
wins balls and nets — tickets buy nothing else; the hoop counter is closed
for now (`App.HOOPS_IN_LOCKER`). The locker icon carries a gold dot while a
won prize has not been looked at.
**The board** sits mid-court (`BoardPreview`, (140, 440), 440 wide — design 3a, 2026-10-17): the area's top five this week and YOUR row after a gap; a tap opens the global boards (below). It slides off left as the league opens. **ONLINE** is the one cream card beside the area name (the 1v1 icon + the word): the lobby.
**Shop is not on the home page**: it will live inside each league, selling
cards usable only in that league (so the easy league can't farm cards for the
hard one); the pill shows TICKETS, the locker money.

- **Theme** (`game/ui/retro_theme.gd`, `RetroTheme`): two palettes over one
  layout — `LIGHT` (the concept's cream, ink `#221C18`, orange / gold / teal /
  blue) and `DARK` — picked by `App.dark_mode` (settings part, `darkMode`).
  `face()` is the panel look: flat, sharp, no border, a hard offset drop
  shadow in ink (the comic-book style); `pressed()` drops the face onto its
  shadow; `flat()` is a strip with an ink rule (the ticker). The **mode cards**
  and every top-bar element are see-through (`game/ui/shadow_style.gd`,
  `ShadowStyle`; cards are `ShadowCard`s): a transparent face over the court
  with the element's own colour as a hard offset shadow, **dithered** with a
  3 px checkerboard (a tiled texture, drawn only as the L strip past the
  face), a thin edge in that colour and a faint tint; labels in cream + ink
  outline. Cards use their colour; the level, locker, ranks and menu use
  cream; the coins pill gold. `on_scene()` gives
  any text drawn straight on the court that cream face with an ink outline.
  `card_button()` dresses a `Button`; `caps()` / `display()` make labels in
  the body / display face. Flipping the setting rebuilds the chrome in place
  (`rebuild_chrome()`); the court stays.
- **Type**: `UiFont` — Press Start 2P (display) and Silkscreen (body), 8 px
  grid, no system fallback. Anything the faces lack (☰, the bars) is **drawn
  in code** (`HamburgerButton`, `IconButton`); the pixel icons come from the
  design project as `assets/ui/icon_*.png` (ball, coin, star, trophy,
  stopwatch, jersey, multiplayer), drawn nearest-filtered by `PixelIcon`.
  `·` and `★` exist in Press Start 2P; the ticker test asserts every glyph.
  A headline's **dithered drop shadow** (the area name, the chevrons) is the
  Label's own shadow pass run through `game/ui/dither_text.gdshader`
  (`RetroTheme.dithered`): cream at half strength, offset (7, 7), one square
  of a 3 px checker kept.
- **The live court** is the page background: the scene is a `Node3D` holding
  one `CourtGeometry` (built from the area's practice `App.MODES` row, with
  its own `Sun` / `Env`) and a camera on `TitlePan.pose()` (five `title_*`
  numbers on the ArenaSet; cage fov 66 for portrait). The chrome sits on a
  `CanvasLayer` over a mild ink scrim (`SCRIM_ALPHA` 0.25) that also takes the
  horizontal swipe. A page turn (arrows or swipe) fades a full-screen ink
  cover, rebuilds the court, refreshes the zone, cards and ticker, and
  fades back. `App.home_card` keeps the page. No SubViewport.
- **Pages over the area** (`game/ui/home_page.gd`, `HomePage`, 2026-10-15,
  design "Store and Locker"): the locker and PEGGY open with the ENTER
  LEAGUE move — `TitleScreen._slide_home` slides the whole chrome (top bar,
  zone, chevrons, cards, ticker) out to the left while the page's frame
  (654 × 1234 at (30, 20), see-through dotted pieces in the scene colours on
  every palette) slides in from the right over the area, under a light wash
  (`HomePage.WASH`), 0.3 s on the league's quad curve; the full-width dotted
  CLOSE runs it back. Pages **stack**: PEGGY from the locker slides the
  locker out under it to the LEFT and brings it back when it closes
  (`slide_out(true, false)` / `slide_in(true)`); the locker's CLOSE then
  returns home. A dark-mode `rebuild_chrome()` keeps the chrome out while a
  page is open.
- **The league in context** (`game/ui/league_context.gd`, `LeagueContext`):
  tapping the LEAGUE card (or ENTER LEAGUE) slides the home block out left
  and the league in from the right, in the same box — a tab row `<` MATCH ·
  TABLE · SCHED · CARDS · STATS (the active tab a solid cream face with an
  orange dithered shadow) over panes that slide sideways, with an 88 px fade
  at the bottom while a pane can still scroll. It IS the league dashboard
  (the full-screen hub is gone): MATCH — the pine opponent card (`DAY 4 ·
  AWAY` over the name, nickname / hometown, ACC / ARC segments and PACE beside
  the PLAY button with the equipped cards as chips on its corner, the bio;
  **no SIM DAY / SIM ALL — every game is played live**), plus the START
  SEASON / ADVANCE cards for a finished season or a lost playoff; TABLE — the
  standings (your row orange, the dashed PLAYOFF LINE) or the bracket (the
  semis, a connector, the final); SCHED — every game (today's gold, unplayed
  dim); CARDS — LOADOUT (the **spares**; the equipped slots float above) and
  SHOP (this league's coins, the buy pill with the coin icon); STATS — the
  career grid, seasons, BEST MATCHES, the area's time trials. Every panel is
  a see-through cream `ShadowPanel` at 14 % with cream text. `changed` fires
  when the doc moves, `tab_changed` on a tab; `go_loadout()` lands on CARDS ·
  LOADOUT. `App.enter_league(id)` makes a league current without a scene
  change; `App.to_league_hub()` (CONTINUE SEASON after a heat) lands on the
  home with it open. While open the chevrons hide and the swipe is off.
- **The floating layer** (`title_screen.gd` `_rebuild_float`, over the court
  above the area, per open tab): MATCH → the compact loadout strip (three
  42×56 thumbnails, `LOADOUT · n OF 3 SET`; tap → CARDS · LOADOUT); CARDS →
  the full loadout (96×128 cards, tap one to unequip, `SLOT 3 EMPTY`); TABLE
  → `YOUR SPOT` / the big ordinal / `2-1 · 1.0 GB` / `IN A PLAYOFF SPOT`;
  SCHED → `COMING UP`, the next three games as cards (today's gold); STATS →
  `THIS SEASON` RECORD · HIGH PTS · STREAK. Rebuilt on `tab_changed` /
  `changed`, hidden with the home block.
- **Season chip** — while the league is open a chip slides in under the area
name (`SEASON 2 — 2-1`, `SEASON 2 · PLAYOFFS — SERIES 1-1`, `SEASON 2 · OVER
— 10-4 · CHAMPS`; `LeagueSummary.card().chip`). The LEAGUE card's PLACE and
FINISH are bare numbers; a finished season's ENTER LEAGUE narrows to the
chevron (the footer says START INSIDE).
- **Summary copy** (`game/ui/league_summary.gd`, `LeagueSummary`, pure):
  `card(state)` (the LEAGUE card's top / sub / titles / stats / next line),
  `spot`, `upcoming`, `season_stats`, and `line(state)` — the one-liner the
  ticker reads: `NEW LEAGUE`, `LOCKED · TOP 4 IN THE ARCADE LEAGUE`, `SEASON
  1 · DAY 1 · TIP OFF`, `SEASON 2 · DAY 4 · 3RD PLACE`, `SEASON 2 · SEMIS
  1-0`, `SEASON 2 · CHAMPIONS`, `SEASON 2 · DONE · 5TH PLACE`.
- **Cards** (`game/ui/mode_cards.gd`, `ModeCards`): `league_card(state,
  slots)` (trophies up to five then `+n`, chips = `Chip`: the card's sprite
  loop on its own colour, or the dashed `+`), `trial_card` / `practice_card` (`icon_card`),
  `text_card`, and the shared `art` / `empty_slot` / `chip` / `stat`
  pieces. LEAGUE → opens the league in context; TIME TRIAL / PRACTICE →
  `App.start_area(mode, area)`. **Quick heat is not on the home screen**.
- **Ticker** (`game/ui/home_ticker.gd`, `HomeTicker`): `items_from(bests,
  states, coins, next_up)` → `ARCADE CAGE BEST 29 · ARCADE LEAGUE · SEASON 2
  · DAY 4 · 3RD PLACE · NEXT UP: PRUDENCE CHIME · 1,240 TICKETS`, laid twice
  around a `★` seam and scrolled at 80 px/s.
- **New player** (design "New Game Flow" 35a, 2026-10-17; `game/ui/new_player_page.gd`
  `NewPlayerPage`, a `HomePage`): on a fresh install the splash's NEW GAME slides the
  splash out left (sign and all) and the form in from the right. A gold card on top
  previews name over hometown (`icon_jersey`); PLAYER NAME is pre-filled from
  `HandleWords.generate` with its two-digit tag shown grey after the field; HOMETOWN
  from `data/towns.json` (`Towns`, ≤ 16); each has a die (`DieGlyph`, a drawn die that
  spins a turn) to re-roll, or is typed over — typing is tidied in place (upper-case,
  A–Z 0–9 and single spaces). The name follows the settings rules (3–24, no blocked
  word), the hometown cannot be empty; the status line says why ("NAME NEEDS 3 OR
  MORE LETTERS" / "NAME NOT ALLOWED" / "PICK A HOMETOWN", in `#FF8A6A`) and LET'S PLAY
  dims until both pass. LET'S PLAY → `App.create_player(name, tag, town)`: the name and
  tag onto the account part (registration waits for this step — `Net._register`
  refuses until `App.player_created()` — so the chosen name goes up in the register
  call), the hometown and `playerCreated` into the settings part (synced; the
  hometown is not a server field, and the league still says YOU), then straight onto
  the Arcade Cage home with its cards (`enter_league("cage")`, no archive, the league
  closed so the walkthrough can point at the cards) where the home walkthrough runs
  (see Walkthroughs) and then the title shows two `Toast` chips: "WELCOME, BRICK
  BARON" over "OAKRIDGE · FIRST STOP" for 3.4 s.
  `App.player_created()` is `playerCreated` or `has_save()` (older installs skip the
  form); `App.qa_fresh` forces a fresh install for QA (`--qa-splash` snaps
  `new_player`, `new_player_roll`, `new_player_invalid`, `new_player_home`). Tests:
  `tests/test_new_player.gd`, `tests/test_towns.gd`.
- **Walkthroughs** (design "First Time Walkthrough" 36a, 2026-10-17;
  `game/ui/walkthrough.gd` `Walkthrough`, CanvasLayer 50; data in
  `data/walkthroughs.json` read by `core/ui/walkthroughs.gd` `Walkthroughs`): a
  reusable spotlight tour over a live screen. Everything is dimmed (`#0E0B09`
  at 82 %) except the part being explained, cut out with a 3 px gold outline and
  a pulse ring expanding 18 px over 1.4 s; the spot glides 0.4 s between steps;
  a cream card (x 36, 642 wide, pad 28) rises in under or over the spot — below
  a spot in the upper half, above one in the lower half, so it never covers
  what it points at — with the title (display 22, gold) and "n / N", the body
  (bold 21), SKIP (150 × 68, every step but the last), `<` (from the second),
  NEXT (orange, the step's `cta` or NEXT, a `>`); `welcome` / `end` steps are
  centred bookends at y 380 with no spot ("WELCOME TO / HOOP SHOOT LEAGUE",
  "THAT'S IT!" at display 40 gold, dithered). Taps underneath are blocked. SKIP
  and the last NEXT both `App.mark_walkthrough_seen(id)`
  (`settings.walkthroughsSeen`) and emit `closed(completed)`. **Hosting one:**
  a screen builds `Walkthrough.new()`, `start(id, resolve)` with
  `resolve(target_id) -> Rect2` in design px (Rect2() = no spot; a plain step's
  `id` is its target), and listens for `closed`; new tours are new keys in the
  JSON plus a resolver. **The home tour** (`"home"`): queued by
  `App.create_player` (`pending_walkthrough`), run by the title once the home
  shows its cards (no archive, league closed — which is why NEW PLAYER now lands
  on the card home rather than the open league); targets `three` (LEAGUE card +
  the pair, the chips above it), `league`, `level` (the LVL badge), `online`
  (the ONLINE card), `locker`, `enter`, resolved from `Chrome` by node name
  (`title_screen._walkthrough_rect`). The welcome toast waits until the tour
  closes. The tour's buttons are `TourSkip` / `TourBack` / `TourNext` (the home
  has its own `Prev` / `Next` chevrons). `--qa-splash` snaps
  `walkthrough_00..06`; `tests/test_walkthroughs.gd`.
- **Settings** (`game/ui/settings_panel.gd`, a `HomePage` since 2026-10-15,
  design "Settings"): the menu button slides it in like the locker. Every
  row is a dotted face — cream, gold when a toggle is on, orange for SAVE /
  CLAIM: SHOT HELP, DARK MODE, the PLAYER section (your handle + SAVE, your
  HOMETOWN + SAVE (a setting, saved on the spot), the
  handle and cloud-save lines, MOVE TO NEW PHONE, ENTER CODE, the platform
  link row — hidden until a Game Center / Play Games backend exists — and
  DELETE ACCOUNT, two taps — docs/BACKEND.md → Identity / Phase 2 / Platform
  identity), TUNING (debug builds only) over DEV BUILD ONLY,
  CREDITS, the full-width CLOSE. Flipping DARK MODE rebuilds the home chrome
  behind it (still slid out); the page itself wears the scene colours.
- **Ranks** (`game/ui/ranks_page.gd` `RanksPage`, copy in `ranks_copy.gd`):
  the global time-trial boards (docs/BACKEND.md). `<` RANKS and your handle;
  CAGE / BEACH / CITY tabs (a locked area's tab greyed with `LVL n`); THIS
  WEEK / ALL TIME; a status line (`TOP 12 · THIS WEEK`, `NO RUNS YET · BE
  FIRST`, or `NO SIGNAL · DEVICE BOARD` when the server is out of reach,
  with the device's own runs as rows); the top 50 as rows, ranks 1–3 in gold,
  your row on orange; `YOU · #7 · 29` pinned under the list. Opens on the
  current area's tab; the page only emits `request(area, period)` and the
  title feeds it from `Net`. QA: `--qa-ranks`.
- **1v1** (`game/ui/match_lobby_page.gd` `MatchLobbyPage`, a `HomePage` since
  2026-10-17 — design "Online Lobby" 37a; copy in `match_copy.gd`;
  docs/BACKEND.md → Phase 3): the ONLINE card beside the area name opens the
  lobby with the locker move (the home slides out left, the lobby in from the
  right, every face see-through and dotted). `<` ONLINE · 1V1; **COURT**: ANY
  and the four courts in a row (a locked court dimmed with a lock; the whole
  row dimmed and fixed on the cage with `UNLOCK MORE COURTS TO CHOOSE` while
  only the cage is open, else `n OF 4 OWNED`; the chosen one gold, the home's
  court picked at open); QUICK MATCH (orange; `FIRST OPEN MATCH ON YOUR COURTS`
  / `PLAY WHOEVER IS ON …`), CREATE CODE (teal, `PLAY A FRIEND`), ENTER CODE
  + GO (gold) over `GOT A CODE FROM A FRIEND? TYPE IT IN`; at the foot the
  **LOADOUT** panel (gold: three 84 × 112 slots, tap one to remove it, names
  beside, `n OF 3 · TAP TO REMOVE`) and **YOUR CARDS** (the spares at 66 × 88
  with a ×n badge, tap one to add it; `TAP TO ADD` / `NONE LEFT · WIN MORE IN
  LEAGUES`) — the online deck sheet is no longer opened from here. The waits:
  `FINDING A PLAYER…` over `USUALLY UNDER 30 SECONDS` with CANCEL; a code:
  `TELL A FRIEND THIS CODE`, the code at 72 px gold, `WAITING…` over `THE MATCH
  STARTS AS SOON AS THEY JOIN`; `PLAYER FOUND` (gold) over `NAME 42 · LVL 07 ·
  STARTING…`; a failure big in `#FF8A6A` (`CODE NOT FOUND` / `NOBODY CAME` / …)
  over what to do, under BACK. The page emits `quick(area)`, `create(area)`,
  `join(area, code)` and `cancel`; `App.start_online` arranges the room — for
  ANY it sends the owned courts and the Lobby pairs on a court both own (the
  joiner is told the court; an any-court host's room takes the joiner's) — and
  tips off into a heat with the other phone in the opponent slot; the
  post-match page reads `ONLINE MATCH · BEACH` with the online coins card
  (`+110 · ONLINE COINS · WIN · UPSET · X2.2`) and the REMATCH? card (orange to
  ask, gold when they asked, teal once both have, THEY LEFT when the other
  phone went home). QA: `--qa-multi` (`multi_menu`, `multi_code`,
  `multi_found`, `multi_failed`, `multi_finding`, `multi_cards`).

## Placeholders (present, not wired)

- ~~Level element~~ — real now (docs/PROGRESSION.md): `LVL0n` is
  `App.level()`, the meter the progress inside the level; the beach page is
  locked below level 3 (every card disabled with `LOCKED · LEVEL 3`).
- **Shop** — off the home page by design; to be built into the league view
  with league-scoped cards.
- **Tickets** (the pill) are real (`App.tickets()`): time trials and league heats award them (docs/ECONOMY.md).
- The concept's **social** tab is not built.

## Adding an area

An ArenaSet with `title_*` set (pose, and `title_stars` for the star row), its
`App.MODES` rows, and a row in `AreaArchiveCopy.AREAS` (the title's `CARDS`,
the archive, the snapshots and the unlock order all read it). The park
(2026-10-15, design "Park Area Concept") is the latest worked example and
touches every place an area lives: `SimGeometry.park()` + `geo_for_mode`
(+ `calibrate_ai` / `card_lab` `geo_for*`), the `park` / `trial_park` /
`heat_park` rows, `AREA_MODES`, `CosmeticLibrary.ARENAS` + `HOOPS` (its own
`assets/hoops/park`), the league row (level 4→5, the beach's band shrunk to
3→4) and seven shooters, `data/economy.json` multipliers, `calibrate_ai --
park`, `league_lab -- park`, `SaveService.default_nets` (+ the migration
for older saves), `ScorePayload.AREAS` + `server/src/rules.ts` (Ross
deploys the Worker), `RanksCopy` (four tabs: `RanksPage.TAB_SIZE` shrank),
`ResultsCopy.board_name` / `run_sub`, `AreaUnlockCopy.LOOK`,
`tools/pack_3d_assets.py`, `--qa-park` / `--qa-unlock`, and
`tests/test_park.gd` + `test_park_fx.gd`. An area's cost knobs live on
its ArenaSet (2026-10-16): `shadow_distance` / `shadow_size` (the sun's
reach and the directional atlas `CourtGeometry._build_lights` sets) and
`render_scale` (the 3D scale the court puts on its viewport while it is up;
the park runs 20 m / 1024 with near-only tree shadows and stays at 1.0 —
0.7 under Godot's bilinear upscale blurred the pixel art; the city runs
20 m / 1024 too). A shader sky is `sky = "partly_cloudy"` plus the `sky_top`
/ `sky_mid` / `sky_horizon` / `sky_sun_dir` palette (`game/view/area_sky.gd`,
the park's design values by default; the city's match its background and
fog). The park's dressing is
`game/view/park_fx.gd` (`ArenaSet.snow` / `sky` / `parked_cars` /
`tree_layout`): the PSX trees instanced from `data/park_layout.json`
(docs/BLENDER_101.md → The park), the parked cars, the falling snow and the
sky shader.

## Splash (design "Splash Screen" 29a, 2026-10-03)

`game/screens/splash_screen.gd` (the main scene; `App.to_splash()`,
`tests/test_splash.gd`, QA `--qa-splash`): the first screen on launch and
where the area archive's `<` leads. The design's own 3D neon sign
(`game/view/neon_sign_3d.gd`, `NeonSign3D`, the "Neon Sign.html" model
rebuilt with SurfaceTool at startup: HOOP / SHOOT / LEAGUE as rounded
single-stroke glass tubes — cream core, orange glass, two additive halos —
the jumps between a word's strokes blocked out behind, electrodes at the
word ends, the sixteen-bead pull chain under the last E, three orange spill
lights) hangs in a 720×720 viewport of its own (black, a little glow) over a
black background — Ross's call for now; the frosted-cage version was cut.
It plays the moment the screen appears, on the design's timeline: the chain
tug at 0.35–1.2 s, dark until 1.3 s, four uneven blinks, a 2.6 s swell to
full, then a 7 % breath; a tap replays it. At 4.6 s the two full-width
orange buttons rise in 0.15 s apart: CONTINUE (`App.player_created()`) → the
title, which opens the archive as the front door — on a fresh install the
button reads NEW GAME and opens the NEW PLAYER form instead (design 35a, see
New player above); SETTINGS → the settings sheet. Discord and Reddit icons sit top-left (the
links come later). Title music starts here and carries into the title.

## Area unlock (design "Area Unlock" 18a, 2026-10-05)

`game/ui/area_unlock_page.gd` (`AreaUnlockPage`, layer 45; copy
`game/ui/area_unlock_copy.gd`; `tests/test_area_unlock.gd`; QA `--qa-unlock`):
the page that plays the moment a league match's XP reaches an area's level
(beach 3, park 4, city 5 — `AreaUnlockCopy.crossed(before, after)`, the first area
in archive order whose level the rise passed). `App._apply_league_heat` queues
it (`App.pending_unlock`) unless `settings.unlocksSeen` already lists the
area; the heat screen shows it after the match-end page and before the
post-match page. Over a snapshot of the real 3D area (`area_<id>_tall.png`,
the portrait render `--qa-area-snaps` now writes beside the card's), darkened:
a `LEVEL 03 REACHED` chip, the area's picture (the card's render) in a cream
frame under a near-opaque dotted veil with the gold lock in its centre; the
lock rattles, the shackle springs open on a flash and a ring (1.55 s), the
veil fades off the picture, the lock flies away and rays in the area's colour
turn behind it; confetti in the area's colours; NEW AREA slams in, then the
stars and the name, then chips for what opens there (LEAGUE / TIME TRIAL /
PRACTICE), then GO THERE (that area's home: `home_card`, no archive) or LATER
(the post-match page). Either marks it seen, so it plays once per area. The
lock sprites `assets/ui/lock_closed.png` / `lock_open.png` are the design's
14×17 px art drawn at 12×.

## Area archive (design "Area Archive" 17a, 2026-10-02)

`game/ui/area_archive_page.gd` (`AreaArchivePage`, a layer-30 page; copy
`game/ui/area_archive_copy.gd`, `tests/test_area_archive.gd`, QA
`--qa-archive`): **the page you see before any area's home**, and the only
way into a locked area's home — which it never allows. The home keeps its
edge chevrons for the open areas: `<` to the one before, `>` to the next
only when it is open, and the `>` wears a gold NEW dot (as does the
area's archive card) until that area has been visited
(`settings.visitedAreas`, `App.mark_area_visited` on landing). It opens on every cold launch
(`App.show_archive`), from the area name, and from the `▾ ALL AREAS · 2/3
OPEN` line under it; `<` goes back out to the splash when the archive was the
front door (a cold launch), else to the area you came from (hidden when
that area is locked). A cream sheet, `AREAS` and the open count (`2/4
OPEN` since the park), then a 320 px card per area: a **snapshot of the real rendered court** under a
bottom gradient, the stars, the name, a `>` and the history line (`🏆 2
TITLES · 3 SEASONS · ⏱ BEST 31`, `NO RUNS`) when it is open; a locked area
under an ink overlay with the lock (`assets/ui/icon_lock.png`,
`tools/aseprite/gen_ui_icons.lua`) and `OPENS AT LVL n`, disabled.
Tapping an open card presses it, inks the page over and hands the fade to
the title (`_go_area`: the court rebuilds underneath, the cover lifts).

The snapshots are `assets/ui/areas/area_<id>.png`, rendered by the game
itself: `godot --path . --resolution 360x640 -- --qa-area-snaps` builds
each area's real `CourtGeometry` (glb, hoop, lights, ambient life) in an
offscreen 1328×640 viewport from the area's title pose (fov × 0.78 for the
landscape crop), lets it settle 1.4 s and saves the PNG into the project.
**Re-run it (then `--import`) after an area's model, lighting or hoop
changes**, and commit the PNGs. The areas' page order is
`AreaArchiveCopy.AREAS` (the title's `CARDS` is the same list).

## Results (design "Time Trial Results", 2026-09-26)

`game/screens/results_screen.gd` (a `Node3D`): the finished time trial's
numbers over the LIVE court you just played on (the area's home pan under a
0.5 scrim), in the same style. `★ ARCADE CAGE · TIME TRIAL`; a **NEW BEST**
gold chip or the gap to your best (`BEST 31 · 7 SHORT`); the score at 96 px
with the dithered shadow (gold when best); the stat tiles MAKES · SWISHES ·
STREAK · BONUS (+ ICED when it happened); the top-ten board on a see-through
panel, this run's row in orange with `THIS RUN`; **RUN IT BACK** (`60 S ·
SAME CAGE`, `App.start_mode(App.next_mode)`) beside the gold tickets card
(`+30` / `TICKETS · BEST BONUS IN`, only when tickets were earned); **HOME**
(`App.to_title`). Copy is `game/ui/results_copy.gd` (`ResultsCopy`, pure,
`tests/test_results.gd`); the run is `App.last_run` (+ `last_run_was_best`).

**League match end** (`game/ui/match_end_overlay.gd`, design "League Match
End" 15a, 2026-10-01; copy `game/ui/match_end_copy.gd`,
`tests/test_match_end.gd`, QA `--qa-match-end`): the moment between the
final buzzer and the post-match page. The heat screen settles the heat at
the buzzer (`App.settle_heat`, which also snapshots your record, place,
titles and series before/after into `last_heat.league_end`) and plays one
of seven states on a dark-cage backdrop: a regular **win** (YOU WIN slams
in with a cream flash, orange rays and confetti; your record flips 2-1 →
3-1 and a chip says `2ND PLACE · UP 1`), a **loss** (THEY TOOK IT sinks in
and shakes, no rays, a darker scrim, `4TH PLACE · DOWN 1`), a playoff game
that leaves the **series** open (the bracket shows `SERIES 1 - 0`, `FIRST
TO 2`), **advance** (ADVANCE, gold rays, YOU slides into the FINAL box over
`VS DRE`, `ONE WIN FROM THE TITLE`), **eliminated** (ELIMINATED, your row
dims and is struck through, they move on, `SEASON 2 OVER · 3RD PLACE`),
**runner-up** (SO CLOSE) and **champions** (the trophy pops and bobs,
TITLES with a cup per title and `X2`, `SEASON 2 TITLE`, the most confetti).
A tag pill (`DAY 4 · FINAL` / `PLAYOFFS · SEMIFINAL` / `ARCADE LEAGUE ·
FINAL`), the score with YOU and their first name, the coins pill and the
NEW CARD tile (tilted animated face) are on every state; after 3 s TAP TO
CONTINUE blinks and a tap goes to the post-match page
(`App.to_heat_result`). Sounds: `peggy_win` on a win, `peggy_jackpot` on
advance/champions, `match_loss` otherwise. Confetti is
`game/ui/confetti.gd` (seeded, pure `_draw`); the rays are `PrizeRays`.

**League post-match** (`game/screens/heat_result_screen.gd`, design "League
Post-Match", `HeatCopy` in `game/ui/heat_copy.gd`, `tests/test_heat_result.gd`):
the same recipe after a league heat — `ARCADE LEAGUE · SEASON 2 · DAY 4` (or
`SEMI 2 · GAME 3`), YOU WIN in gold / THEY TOOK IT, the score with an OT chip,
`VS NAME · "NICKNAME"`; the box score (MAKES · SHOOTING · SWISHES · BEST
STREAK · STREAK BONUS · ICED OVER) with a YOU chip and the opponent's chip in
their colour, the better number in gold; the coins card (+ tickets) beside the
card drop; **CONTINUE SEASON** (`NOW 3-1 · 2ND PLACE · DAY 5 NEXT`,
`App.to_league_hub`) and **HOME**. A heat outside a league reads QUICK HEAT
and gets only HOME.

## HUD (design "Solo Modes HUD", 2026-09-26)

`game/view/hud.gd` (`Hud`, a CanvasLayer over the live game; copy in
`game/view/hud_copy.gd`, `tests/test_hud.gd`): the top row — PAUSE
(`IconButton("pause")`; and since 2026-10-16 the MUSIC note, `IconButton("music")`, at the
bottom-left (36, 1192) on every court: a tap toggles the shared level playlist
(`App.LEVEL_MUSIC` → `Sfx.start_level_music`, a random track, looping, beside the ambience),
struck through in gold while off; remembered as the `musicOn` setting, off on a fresh install), the clock card (stopwatch + seconds, gold in the last
ten; `OT1 12.3` in overtime) or the teal PRACTICE card, the orange SCORE card
with the springy count-up and, in a trial, the gold BEST chip (`NEW BEST`
once you pass it) — and the **toast chips** (designs 4a / 5a, 2026-10-14;
`game/ui/toast.gd`, `HudCopy.toast_for`): the countdown is the big chip at
y 300 (`STARTS IN` over the digit, then `GO` in orange for 0.9 s), and every
mid-play call is the small 64 px chip at y 196 for 2.6 s — `TIME!` (orange,
stopwatch), `30S MODE · ON / OFF` (orange, stopwatch), the spot shuffle's
`NEXT / L ELBOW / IN 3` (gold, staying while the seconds swap) and `NOW
SHOOTING / L ELBOW` (cream, 1.6 s). The old centre banner (48 / 72 px at
y 450) and the 160 px digit are gone: nothing sits over the hoop while you
shoot. `Hud.banner(text, color)` keeps its name; the mapping is the copy.

**Rim pops** (design "Solo Modes HUD" 5a, 2026-10-03; `game/view/rim_pop.gd`,
`RimPop`, `tests/test_rim_pop.gd`): every scoring call — `+1`, `+2` under
`SWISH` (gold), `BUZZER BEATER`, `HEATING UP`, `ON FIRE` (orange), `IN AND
OUT` — is a small 3D pop that rises off the hoop instead of a centre banner,
in every mode. `CourtGeometry.rim_pop()` spawns one just above the rim
centre (so it follows the moving board); two billboarded `Label3D`s (the
number in Press Start 2P at 32 px, the word above in Silkscreen bold at
16 px, ink outline, an offset ink shadow copy) on the mock's 1.1 s curve:
pop in to 112 % by 12 %, settle, drift up 110 px with a 10 px sine sway,
fade out over the last 30 %. They are depth-tested so the ball and the rim
draw over them, and they stack (each pop is its own node, freed when done),
so `+2` and `ON FIRE` no longer overwrite each other. The copy lives in
`HudCopy.rim_pop/heat_pop/fire_pop/in_out_pop`. The league opponent's PiP
court spawns the same pops at `pop_scale 2.4` so they read at a third of
the width. Practice adds
the 30S MODE row (`ToggleSwitch`) under PAUSE and, under that, the spot rail
(design 5a, 2026-10-05): a column of 150 × 56 `ShadowCard` chips at x 36 / y 200,
the spot you stand on in orange, with a 44 × 56 chevron beside the column that
slides the whole rail 200 px off the left edge and back (`--qa-spots` snaps
`spots_00..02`). The pause menu is shared (`game/ui/pause_menu.gd`, `PauseMenu`):
PAUSED, RESUME, SHOT HELP (taps cycle the value), BALL (taps cycle the owned
balls; the equip is global), NET (taps cycle every owned net, any kind on
any court; the equip is this court's — docs/LOCKER.md → NETS), QUIT TO TITLE — the old
BACK button lives there now.

**League match** (design "League Match HUD", `game/screens/heat_screen.gd`):
the same row with two 162×50 score cards in place of SCORE — YOU in orange,
the opponent's first name in their shooter colour — a gold `OT1` tag in the
clock card in overtime, and the ball-return wait as a NEXT BALL chip. The
opponent's window sits under the row at the right margin in a frame of their
colour with a dithered shadow (`PipFrame`), OPP top-left, a minimize button
top-right and their loadout hanging off the bottom as chips; minimized it is
a chip in their colour with their score and a restore glyph. The card tray
(`TrayCard`) puts each card on a dithered ink shadow with a press state and a
chip across its middle for WAIT (dimmed) or the fire window's seconds. A
played card grows in the middle over its shadow with a caption chip
(`DEEP FREEZE > OLLIE`; blue for yours, orange for theirs) then flies to its
target. ON FIRE is a rim pop like the rest. **Toasts (design 4a update,
2026-10-04; `game/ui/toast.gd`, `Toast`)**: the league's countdown is a chip
at y 300 — `STARTS IN` over the digit, min 240 wide, dark fill under the
colour's dots, the checker shadow — that slides in from above and swaps its
digit; GO is the same chip in orange for 0.9 s (`Hud.countdown_toast`,
`go_toast`). The overtime break is the small chip at y 196 — stopwatch,
OVERTIME (or OVERTIME 2), `20S` in gold — up for the break (`Hud.toast`,
`HudCopy.ot_toast`); the dim and the TIED line are gone. The tray shows a
dashed empty box in every slot without a card (a played card leaves one
behind; the full stack stays centred, `tray_layout`), and the opponent's
loadout row under the PiP shows dashed 40 px chips for their empty slots.

## QA and tests

- `godot --path hoop_shoot --resolution 360x640 -- --qa-heat` →
  `user://qa/heat_countdown.png`, `heat_live.png` (the tray's animated
  faces), `heat_deal.png` (the deal and its glyph caption), `heat_pipmin.png`,
  `heat_pause.png` on a real cage league heat (it equips ice + fire7 in
  empty slots of the dev save).
- `godot --path hoop_shoot --resolution 360x640 -- --qa-hud` →
  `user://qa/hud_countdown.png`, `hud_live.png`, `hud_pause.png`,
  `locker_slide.png` (mid-move), `locker_balls.png`, `locker_nets.png`,
  `locker_nets_chain.png`, `hud_practice.png`, `hud_practice30.png`.

- `godot --path hoop_shoot --resolution 360x640 -- --qa-city` →
  `user://qa/city_home.png` (the third page: CITY COURT, three stars, the
  lock or the league) then `city_00..09.png`, `city_last.png` on a city time
  trial over ~45 s (cars cross the street, windows switch, the spot shuffle).
- `godot --path hoop_shoot --resolution 360x640 -- --qa-cards` →
  `user://qa/cards_f0.png`, `cards_f5.png`, `cards_live.png`: the animated
  card faces (ice, fire, the pending vortex) at tray / loadout / shop / deal
  size, the chips, the WAIT and `5S` tray tags, the deal caption.
- `godot --path hoop_shoot --resolution 360x640 -- --qa-heat-result` →
  `user://qa/heat_win.png` (OT, a card drop), `heat_loss.png`, `heat_quick.png`.
- `godot --path hoop_shoot --resolution 360x640 -- --qa-results` →
  `user://qa/results_best.png`, `results_iced.png`, `results_home.png`: the
  page as a new best with tickets, as a mid-board iced run, then HOME.

- `godot --path hoop_shoot --resolution 360x640 -- --qa-title` →
  `user://qa/title_*.png`: the cage over its pan, the beach page, back, the
  league open on every tab (with its float), the locker page, the settings
  sheet, then the dark page.
- `--qa`, `--qa-aim`, `--qa-beach` click TIME TRIAL on the right page.
- `tests/test_home_ui.gd` (palettes, faces, dark mode persistence, league
  lines, ticker copy + glyph coverage, widgets), `tests/test_title_cards.gd`
  (the pan, poses, routing).
