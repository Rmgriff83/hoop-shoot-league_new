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
| `at` `{frame, from}` | hold until exactly `frame` frames after the mark `from` (`in`): v2 places its hits by count |
| `time_scale` `{x}` | true slow motion: the sim and the net run slower, 60 real frames a second |
| `camera` `{at, look, fov}` / `{off}`, `hud` `{on}` | the social cut's rim camera (refused in an App Store shot) |
| `league_heat`, `ready`, `card`, `league_page`, `league_tab`, `match_end`, `season_wrap` | the league (`director_stages.gd`) |
| `results`, `board`, `board_rows` | a time-trial result; the ranks page with staged rows (a second `board_rows` is the climb) |
| `lobby`, `finding`, `found`, `online_heat`, `online_result` | ranked online against QaFakePeer |
| `locker`, `locker_tap`, `peggy`, `peggy_drop` `{want: legend}` | the locker; a real PEGGY drop aimed by the board's own sim |
| `splash` `{fresh, menu}` | the splash's neon logo with its menu hidden (the end card); `fresh` shows NEW GAME as a first install does, `menu` keeps the menu (v2's opening) |
| `new_player` `{seed}` | the NEW PLAYER page NEW GAME opened, its rolls on a seed (`tools/trailer/v2/roll_seeds.gd` lists them); marks `page` and `land` |
| `flyover` `{area, from, to, seconds, hold_frames}` | the area alone in the home background's camera pose, trucked `from` → `to` (metres off that pose; screen-right is +z) at a constant speed, on past `to` for the handles; holds `hold_frames` at `from` first (v2 part 2) |
| `flicks` `{n, want, seed}` | flick after flick while the clock runs: a heat played to its buzzer (v2 part 3); each waits for a ready ball and gives up when the period ends |
| `watch` `{what: buzzer\|done, name}` | marks the frame a heat's clock runs out / the heat is done (both sides' balls down), from the sidelines while later steps run |
| `clinch_day` `{seed}` | the cage campaign on the regular season's last day, one win from the top seed and not yet clinched (`tools/trailer/v2/clinch_doc.gd`) |
| `cards` `{area, have: {id: n}, loadout}` | one league's card bucket set exactly (v2 part 4 stages the bought card out of it, so the shop buy grows a new slot); `drag_card` takes a `mark` and marks the ghost's lift (`mark`) and the drop (`mark_drop`) |
| `locker_scroll` `{to: px\|end, frames}` | the locker's open tab scrolled as a flick does, fast then easing to rest (v2 part 7); `peggy` takes `{drops}` to reseed the plates |
| `wear`, `tap`, `call` | change kit, press a named button (`tap {name, under}` searches inside a named node when the name is not unique — two pages carry a `Back`), call a method |

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

## Store screenshots

`python3 -I tools/trailer/store_shots.py` takes one frame from the App
Store clips per screenshot, downscales it once to 1290 × 2796 (the 6.9"
slot, the layout's own shape), and writes `marketing/trailer/store/clean/`
and `captioned/` (each screenshot under its trailer card, moved off the
content), plus a sheet of each. Run it after `capture_all.sh appstore` and
`cards.sh appstore`. The frames and caption positions are the `SHOTS`
table at the top of the script. The listing text is in
`marketing/store/APP_STORE_LISTING.md`, and the website pages are in
`marketing/site/`.

## Checkpoints

- **A**: `marketing/trailer/checkpoint_a/`: `CHECKPOINT_A.md` (shot list on
  the bar map, copy options, the six themes and their frames),
  `storyboard_<layout>.png`, `cards_<layout>.png`, `crisp/`.
- **B**: `marketing/trailer/draft/` (960 high).
- **C**: `marketing/trailer/final/`, checked with `build_cut.py --check`.

## v2 — "Play for keeps" (2026-11-12)

The second trailer, built ONE PART AT A TIME from Ross's storyboard,
`tools/trailer/v2/storyboard.json`: 8 parts (his 8 scenes), 18 bars at
110 BPM, 60 fps, **2356 frames**, master **1080 × 2340**. Every boundary is
`round(t × 60)` on the GLOBAL timeline — a bar is 130.9 frames — so a part's
length is its `end_frame − start_frame` from the JSON and is never computed
per part. The hits are in the JSON too (`frame` / `part_frame`).

Everything v2 lives in `tools/trailer/v2/` and writes under
`marketing/trailer/v2/` (gitignored):

```
python3 -I tools/trailer/v2/v2.py music                music.wav: the JSON's recipe (song bars 3–16, then
                                                       bars 5–8 fading out, qsin), 48 kHz, exactly 2356 frames
python3 -I tools/trailer/v2/v2.py conform raw/partNN/x.mov
                                                       a phone recording → conform/partNN/x.mov (+ .wav)
python3 -I tools/trailer/v2/v2.py insets conform/partNN/x.mov
                                                       the recording's HUD against the headless reference
tools/trailer/v2/capture.sh <shot>                     a v2 shot through Movie Maker → v2/clips/<shot>.mov
tools/trailer/v2/cards.sh N                            part N's text card frames (minutes: 2 s a frame)
python3 -I tools/trailer/v2/v2.py part N               part N's deliverables + the hit report
```

A part is a shot (`tools/trailer/v2/shots/partNN.json`, the director's verbs,
hits placed with `at {frame}` from the `in` mark) plus a part file
(`tools/trailer/v2/parts/partNN.json`: which clip frames fill it, which mark
is each hit, what was approximated). A QA click presses on one frame and
releases five later, and a button fires on the release: press five frames
early when the change is the hit, on the beat when the pressed look is.

**Sources.** Parts 1, 2, 3, 4, 7 and 8 are rendered by the game (the
director on the trailer save, `tools/trailer/v2/shots/`); parts 5 and 6 are
Ross's online match, recorded on his iPhone 16 (his POV) and his friend's
iPhone XR (theirs). Headless frames are the App Store layout at 2×
(1440 × 3120 = 720 × 1560) and are downscaled ONCE to the master with the
area filter. Recordings are conformed first: scaled to 1080 wide (the 16's
1179 × 2556 down ×0.916, the XR's 828 × 1792 up ×1.304 with lanczos), the
last pixels cropped (the 16: 2 px) or padded (the XR: 1 px top and bottom)
to 2340, and iOS's variable frame rate made a constant 60.

**Insets.** The headless HUD must sit where the iPhone 16's does, so v2
renders with `--qa-safe-top=108 --qa-safe-bottom=62`: the 16's 59 pt / 34 pt
insets at 3× scaled by 720 / 1179 (`UiLayout` measures a real phone the same
way, in design px). `tools/trailer/capture.sh` takes them as
`TRAILER_SAFE_TOP` / `TRAILER_SAFE_BOTTOM` (and the output folder as
`TRAILER_OUT`); v1 keeps its 118 / 62. `v2.py insets` lays a recording's
frame over `clips/hud_ref.mov` (the practice HUD at 108 / 62) and prints the
offset it finds in the top and bottom HUD bands, with a side-by-side and
blend PNG in `v2/insets/` to read by eye.

**Per part** (`marketing/trailer/v2/parts/partNN/`): `partNN_clean.mov` (no
text) and `partNN_text.mov` (the game-rendered text card), identical frames
otherwise, all-intra H.264 crf 10, exactly `frames` long, the game's SFX
only (the music runs unbroken in the final assembly); `partNN_sfx.wav`;
`partNN_review.mp4` (the text version with its slice of music.wav, for a
phone); `partNN_sheet.png` (one frame per beat, labelled bar.beat and the
hit). The report says where each hit landed against its target frame
(anything over 2 frames is flagged), which sources were used, and what was
approximated. Text cards are the game's (card_scene.gd `render_v2`): the
tour panel at x 36, 648 wide, **y 1010** (design px; over the floor in the
shooting view, under LET'S PLAY on the NEW PLAYER page, clear of both HUD
bands at 108 / 62), each line **32 px** Press Start (18 glyphs a line; a
longer line wraps inside the panel), in from the part's "text card in" hit
with the tour card's rise, out with its 0.2 s fade on the part's last
frame — locked on part 1 (2026-11-12) for every part. Part 7's line is two
lines; part 8 has none (its badges and legal lines are its own).

Part 2 is built a court at a time (`v2.py part 2a` … `2d`: a slice of a
part from its `frames_list`, with the part's card already up where the slice
starts), Ross's real shots cut in after the flyovers. The cage (2a,
2026-11-12): from exactly the home pose, trucked 1.5 m screen-right over
the bar inside the booth — the booth is centred on the hoop, not the home
camera, so its left fence is ~0.2 m from the start and the room is to the
right. Ross picked the inside pass over one pulled 2 m back outside the
gate ("too far out"; `shots/probe_cage.json` holds both). 2a's bar: the
flyover to beat 2.5, then Ross's own cage make (an XR recording, conformed)
with the swish's sound onset on beat 3 — the sound is found in the
recording's audio (its loudest transient), the frame put on the beat. The
beach (2b, 2026-11-13): an open court, so the home pose trucked 3 m, centred
(`shots/probe_beach.json`), the same split, then the clean SWISH +3 from
Ross's beach recording — the game's swish sound, not a rim-touching make's
net sound; a recording's swish reads in its RMS profile as a sustained burst
(~5 frames) followed by the floor bounce ~25 frames later, and the onset is
the first frame at full level. The park (2c, 2026-11-13): the same 3 m
centred pass (`shots/probe_park.json`), then the SWISH +2 from Ross's park
recording — the game's spot timer had moved the camera while that ball was
in the air, so the cut sits exactly on the recording's camera change (beat
2.75, 7 frames before the swish) and the part never shows the jump. The
city (2d, 2026-11-13): the same 3 m centred pass but trucked screen-LEFT
(Ross: the city sweep runs right to left; `shots/probe_city.json`), then a
+1 from Ross's city time-trial recording with the net sound's onset on beat
3 — that clip's only swish happened before it starts, so a re-recorded city
swish can replace it with the same recipe. Bar 6 is a 130-frame slice.
An onset, for every court: the first 1/60 s chunk whose RMS is over half
the sound's peak. Seen together (Ross, 2026-11-13) every bar cutting pan →
live on the same beat sat too hard on the downbeat, so part 2's slices were
re-cut (the storyboard's `frames_list`; the part's own bounds and the drop
on 7.1 unchanged): 2a keeps its bar; 2b is live only and 65 frames longer
(393–589, beats 4.1 → 5.3: the previous +2 dropping, ball in hand, flick,
arc, the swish on the bar-5 downbeat — the recording was paused too soon
after the swish to hold on it instead), paid for by the park and city pans
(2c 589–687 from 5.3, a 26-frame pan then the swish on 5.4; 2d 687–785 from
6.2, a 15-frame pan then the make on 6.3). A slice that runs past its bar
gets every beat it covers on its sheet. The beach flyover capture stays on
disk.

Part 3 (2026-11-13) is one real run: `clinch_day` writes a cage campaign
doc on the regular season's last day — `clinch_doc.gd` fills every other
game of the season (the last day's other games too) and searches results
until the player is outside the playoff line and not clinched before their
game, and the top seed after a win; on seed 45 that is five teams at 8-6,
YOU 7-6 in fifth, Ollie Knots on the day. The heat is then played to its
buzzer with `flicks` (stand-in flicks: no bank on this Mac; `gap_s 4` —
back to back they scored 139, which read fake; paced, 57-29) and the game's
own flow follows: 0.6 s after the heat is done, the CLINCHED page (39a) —
standings rise 0.3 s, the record flips 1.0 s, the row climbs 1.4–1.95 s,
PLAYOFFS slams 2.5 s, CLINCHED · NO. 1 SEED 2.9 s, CONTINUE 3.6 s. `watch`
marks the buzzer (`in`) and `done`. The buzzer's sound sits on 7.1 and the
slam on 8.3 exactly by cutting the clip once, ON the page's first frame:
the scrim darkens the whole frame in one step and hides the jump in the
frames skipped before it (the time between the last ball settling and the
page is what has to go — `done` lands wherever the last ball does, so the
skip is measured per take, from the scrim's frame). A final-day clinching
win has no YOU WIN page in the game: the PLAYOFFS page is that win's page.
A whole heat renders ~6500 frames at this Mac's ~5 fps: `TRAILER_ALARM=2700`.

Part 4 (2026-11-13) is one director run cut in two: bar 9 on the cage
league page (`cards` stages the bucket without Deep Freeze; the CARDS tab,
Deep Freeze's price and CONFIRM are pressed 5 frames before 9.1 / 9.2 / 9.3
— a button fires on its release — so the shop slides in on the downbeat,
the ask (X / CONFIRM) shows on 9.2 and the buy's flight into YOUR CARDS
starts on 9.3; the game's 0.7 s flight lands 10 frames after 9.4, inside
the hold), then `league_heat` with `ready false` and the pre-match page
(`pm`, the page settled: the cut on 10.1), `drag_card` with its `mark` so
the ghost lifts on 10.2 and drops into slot 0 on 10.3, a hold on READY.
Deep Freeze because it is the shop's first row: Magnet's row is below the
pane's fold, out of a tap's reach. The text card leaves the locked slot at
the cut — the storyboard part's `card_y` (`[{part_frame, y}]`, honoured by
`card_scene.gd`) puts it at design y 538, the gap between the OPPONENT panel
and YOU, because at y 1010 it would sit on the loadout slots the drag lands
in; on the league page the locked slot covers the SHOP title (the price row
is clear). The game's own landing: the flown card is freed on arrival and
the new slot grows from 0 width over the next ~0.3 s (slotGrow), so the card
blinks for a few frames at frame 108 — left as the game does it.

Part 7 (2026-11-13) is one continuous take: the locker, PEGGY, a real drop
(`peggy_drop {want: epic}` aims the crane at an epic plate with the board's
own sim, PLAY, DROP — on the trailer save's first drop the plate holds
POLKA), the prize card's pop as `in` (EPIC PULL!, the 0.82 shade, the
magenta rays), EQUIP pressed 5 frames before 15.3, `< BACK` (under
`PeggyPage`: the locker has one too) 5 frames before 15.4 — the game's own
slide from PEGGY to the locker is the whip, the bare court shows for the
silent beat — then `locker_scroll` from 16.1 (55 frames, cubic out: the
rarity rows run past, POLKA gold in the epic row, the legend row last), the
NETS tab on 16.3 and Wool's HANG IT ON on 16.4. Wool because it is on the
cotton group's first row: the panel (name, X, a 3 × 2 grid of courts) opens
under the tapped row, and under row one it sits above the text card's slot
with only its CITY button running under the card; under row two (Rasta) it
was hidden behind it. The text card stays at the locked slot.

Part 5 (2026-11-13) is Ross's own online match, recorded on his XR
(`raw/part05/ross_pov.mov`, conformed: ×1.304 lanczos, 2 px pad, VFR → cfr
60). His direction, after three passes: the part is this clip alone, it
zooms into the opponent's picture-in-picture at its END, just after the ice
card is played, quick and exact — part 6 then opens in the friend's POV.
So part 5 is clip frames 118–380 (clock 29.5 → 25.2, YOU 18 → 20, ALLEY
19 → 20; no director marks — the beats fall where his play fell): Deep
Freeze is tapped at clip 275 and fires at 280 (part frame 162), and a
second later the zip runs from 340 to the part's last frame, 40 frames (a
24-frame zip right after the card was "too soon and too fast" — Ross): a
segment's `zoom` `{from, to, rect, power}` in `v2_part.py`, zoompan with an
ease-in (power 1.8) from the whole frame into the PiP's inner rect (master
px 695,353 331×588, its orange border measured on every side), filling the
frame by height so the window ends inside the PiP; match time then meets
part 6 within 0.2 s. `crop` cannot do this: it reads its size
once. (His timestamps were approximate — "5.9 s" was a second after the
card — so the card's frames were read off the picture: the tray's tile
changes at 275 and 280.)

Part 6 (2026-11-13) is the friend's recording (`raw/part06/friend_pov.mov`,
1180×2556, 4.6 s, trimmed by Ross; conformed ×0.915), its first 262
frames: their rim already iced, DEEP FREEZE PLAYED ON YOU, the card still
arriving over their hoop, clock 25.4 → 21.0, and they score through the ice
twice. Ross: "zoom accordingly from the last take at the beginning" — the
mirror of part 5's zip, a `zoom` with `out: true`: the part opens at ×4 on
their hoop (a 270×585 window on the backboard, master px 400,1080) and
pulls back to the whole frame in 40 frames at part 5's zip speed (power 1.8), fast off the cut and settling.
The clip has 17 spare frames, so it is taken as trimmed (match time meets
part 5's end within 0.2 s). Their phone draws a debug flick
readout (49° / 46 %) at the lower left — a debug build; flagged.

Part 1 (2026-11-12): the lit splash, NEW GAME pressed on 1.3, the real 0.3 s
slide (the storyboard's 1.4 / 2.1 come 28 / 43 frames early — flagged, the
honest pace kept), the card in on 2.1, the dice re-rolling on 2.2 / 2.3 on
seed 45 (TUNNEL SHARK #77 of PINE HOLLOW → NEON COMET → GOLDEN SHORE).

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
