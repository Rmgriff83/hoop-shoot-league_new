# Home screen — the retro card chrome over the live area (2026-09-23)

Ross's concept, implemented: ink-outlined, hard-shadowed cards in the pixel
faces (cream palette or its dark twin) over a **full-screen live view of the
current area**. `game/screens/title_screen.gd` (a `Node3D`), widgets in `game/ui/`.

```
Court       full-screen CourtGeometry + Camera3D (TitlePan), under a mild scrim (0.25)
TopBar      [LVL01 + meter] [locker]                          [▪ 1,240] [menu]
AreaZone    EASY LEVEL / ARCADE CAGE [ranks]  (cream, ink outline, left-aligned);
            big < > chevrons at the screen edges, centred between zone and cards
LeagueCard  orange · "LEAGUE" · ">" · status line
ModeRow     TrialCard (gold, "BEST 29" / "NO RUNS YET")   PracticeCard (teal, "NO CLOCK")
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
  grid, no system fallback. Anything the faces lack (☰ ▪ ■ ●) is **drawn in
  code**: `HamburgerButton`, `CoinsPill.Square`, `IconButton`.
  `·` and `★` exist in Press Start 2P; the ticker test asserts every glyph.
- **The live court** is the page background: the scene is a `Node3D` holding
  one `CourtGeometry` (built from the area's practice `App.MODES` row, with
  its own `Sun` / `Env`) and a camera on `TitlePan.pose()` (five `title_*`
  numbers on the ArenaSet; cage fov 66 for portrait). The chrome sits on a
  `CanvasLayer` over a mild ink scrim (`SCRIM_ALPHA` 0.25) that also takes the
  horizontal swipe. A page turn (arrows or swipe) fades a full-screen ink
  cover, rebuilds the court, refreshes the zone, cards and ticker, and
  fades back. `App.home_card` keeps the page. No SubViewport.
- **The league in context** (`game/ui/league_context.gd`, `LeagueContext`;
  design "Home League Context v2"): tapping LEAGUE grows the card area up to
  just under the area name, slides the home cards out left and the league
  in from the right — a tab row `<` HEAT · TABLE · SCHED · CARDS · STATS over
  panes that slide sideways. It IS the league dashboard now (the full-screen
  hub is gone): the next heat with the opponent card, PLAY HEAT, SIM DAY /
  SIM ALL, playoffs, advance, next season; the table or bracket; the
  schedule; this league's cards (loadout + shop, this league's coins); the
  career, best heats and time-trial records. `App.enter_league(id)` makes a
  league current without a scene change; `App.to_league_hub()` (CONTINUE
  SEASON after a heat) lands on the home with it open. While open the zone's
  caps read `LEAGUE NAME · status`, the chevrons hide, the swipe is off.
- **Cards** (`game/ui/mode_cards.gd`, `ModeCards`): Buttons with a label
  stack. `league_line(state)` is the LEAGUE sub-line from an
  `App.league_states()` row: `NEW LEAGUE`, `LOCKED · TOP 4 IN THE ARCADE
  LEAGUE`, `SEASON 1 · DAY 1 · TIP OFF`, `SEASON 2 · DAY 4 · 3RD PLACE`,
  `SEASON 2 · SEMIS 1-0`, `SEASON 2 · CHAMPIONS`, `SEASON 2 · DONE · 5TH
  PLACE`. LEAGUE → opens the league in context; TIME TRIAL / PRACTICE →
  `App.start_area(mode, area)`. **Quick heat is not on the home screen** (it
  lives in the league hub; `AREA_MODES["heat"]` stays).
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

An ArenaSet with `title_*` set (pose, and `title_tier` for the subtitle), its
`App.MODES` rows, and a row in `title_screen.gd` `CARDS`.

## QA and tests

- `godot --path hoop_shoot --resolution 360x640 -- --qa-title` →
  `user://qa/title_*.png`: the cage over its pan, the beach page, back, the
  settings sheet, then the dark page.
- `--qa`, `--qa-aim`, `--qa-beach` click TIME TRIAL on the right page.
- `tests/test_home_ui.gd` (palettes, faces, dark mode persistence, league
  lines, ticker copy + glyph coverage, widgets), `tests/test_title_cards.gd`
  (the pan, poses, routing).
