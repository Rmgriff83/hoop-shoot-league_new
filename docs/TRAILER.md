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

Sections are added as each part is built. So far: recording flicks.

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
