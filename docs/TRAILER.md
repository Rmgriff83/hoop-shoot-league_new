# The trailer

Two cuts made from real gameplay (plan: 2026-11-06):

- **App Store preview**: 886 × 1920, 30 fps, 13 bars (28.4 s). Screen
  captures of the app only: the shooting view with its HUD, no rim camera.
- **Social cut**: 1080 × 1920, 60 fps, about 18 bars (39 s). May open on a
  filmed hand; gets the rim close-ups.

The music is `assets/music/title_moog.ogg` ("Moog_SEM 110bpm" by fonoskop,
CC BY 4.0, https://freesound.org/s/856449/): 34.907 s, exactly 16 bars at
110 BPM, one bar = 2.1818 s. The credit goes on the end card and in the
video description.

Everything the trailer needs lives in `tools/trailer/`. Everything it makes
(pulled recordings, frames, clips, drafts, finals) goes in
`marketing/trailer/`, which is gitignored. `marketing/` carries a
`.gdignore`, so Godot never imports or exports anything in it.

## Ross's picks at Checkpoint A (2026-11-06)

- **Copy:** option A on every card: EVERY FLICK COUNTS · FOUR COURTS · RUN
  THE LEAGUE · PLAY YOUR CARDS · SOLO OR ONLINE · MAKE IT YOURS.
- **The player:** BILLY BONGO, hometown EUGENE (GO BLAZERS of PORTLAND was
  the first pick; it read as the NBA team, which Apple would count as a brand).
- **Rendering:** 2x the layout, downscaled once (not native).

## Re-rendering, start to finish

```
tools/trailer/profile.sh build                       # the trailer's own save (once, or after a profile change)
tools/trailer/pull_flicks.sh                         # recordings off the phone
godot --headless --path . -s tools/trailer/flick_bank.gd   # check and index them
tools/trailer/storyboard.sh appstore                 # one still per shot (Checkpoint A)
tools/trailer/cards.sh appstore                      # the text cards, rendered by the game
python3 -I tools/trailer/checkpoint_a.py             # the Checkpoint A pack
tools/trailer/capture.sh tools/trailer/shots/<shot>.json appstore   # one shot through Movie Maker
python3 -I tools/trailer/build_cut.py appstore --draft    # a 960-high draft (Checkpoint B)
python3 -I tools/trailer/build_cut.py appstore            # the final
python3 -I tools/trailer/build_cut.py appstore --check    # ffprobe against Apple's spec
```

Use `social` in place of `appstore` for the other cut. Never run two Godot
instances at once; every script here starts one.

## The profile

Every capture runs on its own save: `-- --save-dir=trailer_save --no-net`
(`SaveService.dir_from_args`; debug builds only, and a release build
ignores it). No real save is touched and nothing reaches the server.
`tools/trailer/make_profile.gd` writes it and refuses the real folder:
BILLY BONGO of EUGENE (Ross's pick), level 6, every court open, 2,480 tickets, 14 balls and 5 nets, the park and
the city on chain, a cage season at seven and two, cards in hand, PRO II.
`profile.sh build` keeps a pristine copy and every shot starts from it
(`profile.sh restore`), so a render is the same every time.

The player's name and hometown are constants at the top of
`make_profile.gd`. League opponents are the game's own shooters
(`data/shooters.json`); board rows, the ranked ladder and the online
opponent (QaFakePeer) are invented handles in `tools/trailer/fixtures/`.
No real player's handle can appear: the network is off.

## The flick bank

`tools/trailer/flick_bank.gd` (headless) reads every pulled
`flicks_*.jsonl`, replays each trace through the real estimator, maps it
with the phone's tuning values, and runs the launch through the sim. A row
is marked `replays` when that gives the launch the phone made; `outcome` is
what the sim says happened. It writes `marketing/trailer/flicks/bank.json`
and prints what there is per court and outcome.

A `flick` step picks a recording for the shot's court whose outcome is in
its `want` list (`nth` chooses among them, `id` names one). Where there is
none, `tools/trailer/flick_synth.gd` finds a stand-in: jittered,
finger-shaped gestures tried through the same estimator, mapping and sim
until one gives the wanted outcome. The shot's log and its marks file say
which was used (`synth:<TYPE>`), and Checkpoint A marks those shots.

## The director and shot files

`tools/trailer/director.gd`, started by the QA driver from
`-- --qa-trailer=<shot.json>`. A shot (`tools/trailer/shots/*.json`) is
`{name, note, themes, setup, steps}`; `setup` is `{ball, net, trail, help}`
(the kit is worn without touching the save). Steps:

| Step | What it does |
|---|---|
| `play` `{mode: trial\|practice, area}` | a court, held until the ball is live |
| `flick` `{want: [types], seed, nth, id, plain, poster_mid, then}` | one flick: a recording, or a stand-in |
| `until` `{what}` | `running`, `ready`, `resolved`, `settled`, `entered` (a ball in the net), `peggy_card` |
| `wait` `{s}`, `mark` `{name}`, `poster`, `end` | time, a named frame, the storyboard frame |
| `time_scale` `{x}` | true slow motion: the sim and the net run slower, 60 real frames a second |
| `camera` `{at, look, fov}` / `{off}`, `hud` `{on}` | the social cut's rim camera (refused in an App Store shot) |
| `league_heat`, `ready`, `card`, `league_page`, `league_tab`, `match_end`, `season_wrap` | the league (`director_stages.gd`) |
| `results`, `board`, `board_rows` | a time-trial result; the ranks page with staged rows (a second `board_rows` is the climb) |
| `lobby`, `finding`, `found`, `online_heat`, `online_result` | ranked online against QaFakePeer |
| `locker`, `locker_tap`, `peggy`, `peggy_drop` `{want: legend}` | the locker; a real PEGGY drop aimed by the board's own sim |
| `splash` | the splash's neon logo with its menu hidden (the end card) |
| `wear`, `tap`, `call` | change kit, press a named button, call a method |

Flick replay: each movie frame advances the replay's own clock by 1/60 s
and feeds the touch points that fall inside it to
`FlickInput._begin_at / _move_at / _end_at` with their recorded
timestamps, so the estimator reads what it read on the phone.

Clean frames: the music bus is muted (`Sfx.set_music_sound(false)`,
`App.music_on = false`) so the edit can lay the music unbroken; the tuning
panel and the recorder are off; tours and the tutorial are off for every
`--qa` pass. Under Movie Maker a frame takes as long as it takes to render,
so anything that read the wall clock (sound rate limits, card frames, the
home's twinkle) reads `GameClock` instead, which counts game time there.

## Touch trail

`game/debug/touch_trail.gd`: a short white streak with the dithered shadow
that follows a FlickInput. Nothing in the game creates one; the director
does when a shot's `setup.trail` is true. Apple allows touch marks as
overlays in an App Preview, but no hands or devices.

## Capture

`tools/trailer/capture.sh <shot.json> <appstore|social>` runs the shot
under Movie Maker (`--write-movie … --fixed-fps 60`, not headless) and
writes `marketing/trailer/clips/<layout>/<shot>.mov` (all-intra H.264,
crf 10), `.wav` (the game's SFX and ambience, no music) and
`.marks.json` (frame numbers of the shot's marks, the flicks used, any
problems). Only the frames from half a second before `in` to half a second
after `out` are kept.

Frames are 2x the layout: 1440 x 3120 for the App Store cut (the 720 x 1560
layout, an iPhone's notch and home bar played by `--qa-safe-top=118
--qa-safe-bottom=62`), 1440 x 2560 for the social cut (720 x 1280, a 16:9
phone: `--qa-safe-top=0 --qa-safe-bottom=0`). The insets are always given:
the capture window is taller than the Mac's screen, and a measured safe
area would read the part hanging off the bottom as a giant home bar and
squash the HUD band (the opponent's window landed on the clock). At exactly
2x every UI pixel is a clean square; the cut downscales once.

Movie Maker records at the project's window-size override and only gives a
crisp frame when the window really is that size, which is taller than this
Mac's screen. So `capture.sh` writes a temporary `override.cfg` (the size
override and a borderless window) and removes it on the way out.
`tools/build.sh` and `tests/test_build_config.gd` both refuse a leftover
one, and it is gitignored.

## Text cards

`tools/trailer/card_scene.gd` (`tools/trailer/cards.sh <layout>`) renders
each card of a cut as a PNG sequence with alpha, using the game's own
parts: the tour cards' panel (`ShadowPanel`), Press Start with the ink
outline and the dithered shadow, white for the first line and butter for
the second, and the tour card's rise and fade. The credit line and the
social cut's FREE ON THE APP STORE are cards too. ffmpeg only lays them
over the footage. The end card's picture is the splash screen itself.

## The edit

`tools/trailer/edit.json` holds both cuts: `timeline` entries
`{at: "bar.beat", clip, from}` (`from` is a mark, or a mark plus or minus
seconds: `"poster-0.5"`), `cards` `{id, text, at, until}`, and the copy
options. Every entry is a hard cut on the music's grid; the only fade is
the last bar of music. `build_cut.py` halves the 60 fps footage for the
30 fps App Store cut, downscales with an area filter, lays the cards,
mixes the music (at full length, looped at the bar-16 seam for the social
cut) over the shots' SFX (lower while a card is up), and normalises to
about -14 LUFS. `--validate` checks the data; `--barmap` prints it.

## Checkpoints

- **A**: `marketing/trailer/checkpoint_a/`: `CHECKPOINT_A.md` (shot list on
  the bar map, copy options, the six themes and their frames),
  `storyboard_<layout>.png`, `cards_<layout>.png`, `crisp/`.
- **B**: `marketing/trailer/draft/` (960 high).
- **C**: `marketing/trailer/final/`, checked with `build_cut.py --check`.

## Recording flicks

The footage is driven by real flicks, recorded on the Android dev phone and
replayed on the Mac through the same estimator and sim.

**On the phone** (a debug build: `tools/android_deploy.sh`):

1. Settings → DEV → **RECORD FLICKS** on. (Debug builds only; a store build
   has no DEV section.)
2. Play. A red `REC n` at the left edge counts the flicks recorded on this
   court. Time trials, practice and matches all record.
3. Turn it off when done.

**What to record** — per court (cage, beach, park, city), mostly in
PRACTICE so there is no clock:

- soft flicks that drop in, and clean swishes;
- hard flicks that clang off the back iron;
- flat flicks that rattle out;
- rim-ins (a bounce or two, then in);
- one run of four or five makes in a row (the streak);
- a few ordinary misses. Don't play carefully: the misses are wanted.

In the cage, a time trial's last 30 seconds move the hoop; those flicks
only replay exactly against the same hoop motion, so record the cage in
PRACTICE unless the moving hoop is the point.

**Pulling them off the phone:**

```
tools/trailer/pull_flicks.sh           # → marketing/trailer/flicks/flicks_<time>.jsonl
tools/trailer/pull_flicks.sh --clear   # …and empty the phone's file
```

**The file** (`user://trailer/flicks.jsonl` on the phone, one JSON object
per line; `game/debug/flick_recorder.gd`):

| Key | What |
|---|---|
| `v`, `t_ms`, `session`, `seq` | format version, wall time, the court visit, the flick's number in it |
| `ctx` | `mode`, `area`, `practice`, `heat`, `spot`, `moving`, `ball`, `net` |
| `origin` | the hand's position at release (sim space) |
| `geo` | the hoop's pose at release (`hoop_x`, `hoop_z`, `hoop_y`, `release_h`) |
| `tuning` | every `FlickTuning` value the phone had (the replay uses these) |
| `sample` | the estimator's release sample, including `trace`: `[[usec, x, y], …]` in design px, press first, and `lift_usec` |
| `launch` | what the flick mapped to (`{}` for a cancelled gesture) |
| `outcome` | `{type, made, points, entry_angle_deg}` once the ball settled; `CANCELLED` for a cancelled gesture; `null` if the court was left first |

Outcomes are matched to flicks in the order the balls left the hand, which
can be off by one when two balls are in the air. The flick bank re-runs each
launch through the sim and has the last word.

**Why a trace and not just the launch:** the director feeds the trace back
through `FlickInput._begin_at / _move_at / _end_at` with the recorded
timestamps, so the held ball, the wind-up and the release all move as they
did under the finger. `tests/test_flick_recorder.gd` pins that a replayed
trace gives the same release and the same launch.
