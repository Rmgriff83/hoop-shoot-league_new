# Home screen — the retro card chrome over the live area (2026-09-26, design "Home League Context v2")

Ross's concept, implemented: see-through, dither-shadowed cards in the pixel
faces (cream palette or its dark twin) over a **full-screen live view of the
current area**. `game/screens/title_screen.gd` (a `Node3D`), widgets in `game/ui/`.

```
Court       full-screen CourtGeometry + Camera3D (TitlePan), under a mild scrim (0.25)
TopBar      [LVL01 + meter] [ball = locker]                   [coin 1,240] [menu]
AreaZone    ★ (one star per difficulty step, ArenaSet.title_stars)
            ARCADE CAGE (52 px, wraps at 430, dithered drop shadow) [ranks] [multiplayer]
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
the cards. **Locker** (`game/ui/locker_panel.gd`): the prize counter — every ball and
hoop, owned ones equip (`App.select`), the rest buy for tickets
(`App.try_buy`). **Ranks** is an icon beside the area name (SOON for now).
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
- **Summary copy** (`game/ui/league_summary.gd`, `LeagueSummary`, pure):
  `card(state)` (the LEAGUE card's top / sub / titles / stats / next line),
  `spot`, `upcoming`, `season_stats`, and `line(state)` — the one-liner the
  ticker reads: `NEW LEAGUE`, `LOCKED · TOP 4 IN THE ARCADE LEAGUE`, `SEASON
  1 · DAY 1 · TIP OFF`, `SEASON 2 · DAY 4 · 3RD PLACE`, `SEASON 2 · SEMIS
  1-0`, `SEASON 2 · CHAMPIONS`, `SEASON 2 · DONE · 5TH PLACE`.
- **Cards** (`game/ui/mode_cards.gd`, `ModeCards`): `league_card(state,
  slots)` (trophies up to five then `+n`, chips = `Chip` crops of the card
  art or the dashed `+`), `trial_card` / `practice_card` (`icon_card`),
  `text_card`, and the shared `art` / `empty_slot` / `chip` / `stat`
  pieces. LEAGUE → opens the league in context; TIME TRIAL / PRACTICE →
  `App.start_area(mode, area)`. **Quick heat is not on the home screen**.
- **Ticker** (`game/ui/home_ticker.gd`, `HomeTicker`): `items_from(bests,
  states, coins, next_up)` → `ARCADE CAGE BEST 29 · ARCADE LEAGUE · SEASON 2
  · DAY 4 · 3RD PLACE · NEXT UP: PRUDENCE CHIME · 1,240 TICKETS`, laid twice
  around a `★` seam and scrolled at 80 px/s.
- **Settings** (`game/ui/settings_panel.gd`): SHOT HELP, DARK MODE, TUNING
  (debug builds only), CREDITS, CLOSE.

## Placeholders (present, not wired)

- **Level element** — `LVL01`, empty meter. No progression system exists;
  `LevelBadge.set_level(n, frac)` is the hook.
- **Ranks** — the icon beside the area name flashes SOON. The league hub's
  RECORDS tab and `results_screen` hold the leaderboard logic to lift.
- **Shop** — off the home page by design; to be built into the league view
  with league-scoped cards.
- **Tickets** (the pill) are real (`App.tickets()`): time trials and league heats award them (docs/ECONOMY.md).
- The concept's **social** tab is not built.

## Adding an area

An ArenaSet with `title_*` set (pose, and `title_stars` for the star row), its
`App.MODES` rows, and a row in `title_screen.gd` `CARDS`.

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

## QA and tests

- `godot --path hoop_shoot --resolution 360x640 -- --qa-heat-result` →
  `user://qa/heat_win.png` (OT, a card drop), `heat_loss.png`, `heat_quick.png`.
- `godot --path hoop_shoot --resolution 360x640 -- --qa-results` →
  `user://qa/results_best.png`, `results_iced.png`, `results_home.png`: the
  page as a new best with tickets, as a mid-board iced run, then HOME.

- `godot --path hoop_shoot --resolution 360x640 -- --qa-title` →
  `user://qa/title_*.png`: the cage over its pan, the beach page, back, the
  league open on every tab (with its float), the locker, the settings sheet,
  then the dark page.
- `--qa`, `--qa-aim`, `--qa-beach` click TIME TRIAL on the right page.
- `tests/test_home_ui.gd` (palettes, faces, dark mode persistence, league
  lines, ticker copy + glyph coverage, widgets), `tests/test_title_cards.gd`
  (the pan, poses, routing).
