# Performance — measuring the match modes and keeping them inside a budget

Ross's brief (2026-10-23): league and online heats lagged slightly on the beach,
park and city while the cage stayed smooth. The shooting must stay smooth and
the areas keep their look and effects. The work runs in three stages
(measure → a lite opponent view → a cheaper main view where still needed),
with the numbers shown after each; this is the document the numbers, the
budget and the rules live in.

## 1. Measuring: `--qa-perf`

`tools/qa_driver.gd` runs every area × mode and writes `user://qa/perf.json`:

    godot --path hoop_shoot --resolution 360x640 -- --qa-perf
    godot --path hoop_shoot --resolution 360x640 -- --qa-perf=beach,city --qa-perf-mode=heat_pip --qa-perf-seconds=24
    tools/android_qa.sh --qa-perf                    # on the phone, pulled to build/qa/<model>/

- **Modes**: `heat_pip` — a league heat with the opponent PiP open; `heat_min` —
  the same with the PiP minimized (`PipMin`); `trial` — the area's time trial.
  A heat has a bot shooting on OUR side (`App.qa_player_bot`, through
  `league_heat_config` → `Heat.player_bot`) so both sides play like a real
  match; a trial gets a flick every 1.6 s. Every heat is day 1 of a fresh
  season seeded 4242 (the same opponent and schedule every run, whatever the
  save holds) and level gating is off for the sweep, so every court measures
  on every device. The save is restored afterwards (a QA heat never advances
  a season).
- **Drift**: the sweep ends by running its FIRST scenario again (the `*` row —
  `cage heat_pip*`). A warm phone throttles; the gap between the first and the
  last row is the thermal drift the rest of the table carries, so rows are
  compared to the baseline, never to each other across the sweep.
- **Timing**: 1 s to load, the 3 s countdown, then a 3 s warm-up that is NOT
  measured, then `--qa-perf-seconds` (24) of play. Then `perf_<area>_<mode>.png`.
- **The probe** (`QaDriver.PerfProbe`, one `_process` a frame): frame time
  (`delta`) → p50 / p95 / p99 / max, fps, **hitches** (frames over
  `perf_budget.json → hitch_ms` 20, counted and normalised per 60 s, the first 20
  logged with their time) and **spikes** (frames over 1.5 × the run's own p50 —
  the stutter a player feels whatever the frame rate; at a 30 fps p50 every
  frame is a "hitch" by the absolute rule, so the budget uses both); per
  viewport (the main view and the PiP)
  `RenderingServer.viewport_get_measured_render_time_cpu / _gpu` (ms, the draw
  of that viewport only; **GPU reads 0 on Metal** — the Mac — and real on the
  phone's Vulkan; shown as `n/a`) and `Viewport.get_render_info` for the VISIBLE
  and the SHADOW pass × draw calls / primitives / objects; the **script time** —
  a sentinel node with the lowest `process_priority` stamps the clock first in
  the frame and the probe (the highest) reads it last, so the span is every
  `_process` in between and nothing else (p50 / p95; `loop_p50/p95` in the dump
  is `Performance.TIME_PROCESS + TIME_PHYSICS_PROCESS`, the whole main-loop
  step, kept for reference) and `RenderingServer.get_frame_setup_time_cpu()`; **see-through coverage** — every
  10th frame, the sum of the projected bounding rects of the main view's visible
  alpha-blended surfaces (a `BaseMaterial3D` with `TRANSPARENCY_ALPHA`, or a
  shader that writes `ALPHA` without a scissor) as a fraction of the screen, in
  screens-worth (an upper bound on blended overdraw).
- **On the phone**: `tools/android_qa.sh` writes the args into
  `files/qa_args.txt` (`adb shell run-as com.rossgriffus.hoopshoot`), launches
  the installed build, waits for `files/qa/perf.json` and pulls it with the
  snaps to `build/qa/<model>/`. `QaDriver._args()` reads that file ONCE at launch
  when the command line carries nothing and deletes it, so a QA mode can never
  stick to an install. `export_presets.cfg` is untouched.

The table (`PerfBudget.header_text`): `p50 p95 p99 hit60 spk60 | mainC mainG pipC pipG |
drwV drwS | script cov pipDrw | tris` — frame percentiles in ms, hitches and
spikes per 60 s, the two viewports' render times (C = CPU, G = GPU), the main view's
visible and shadow draw calls, the script time p95, the coverage max, the PiP's
visible+shadow draws, the triangles (visible + shadow, both views).

## 2. The budget: `data/perf_budget.json` and `tools/perf_ledger.gd`

The **baseline** is the cage's league heat with the PiP open, measured on Ross's
phone; `tools/perf_ledger.gd -- --in=<dump> --set-baseline` copies that row (and
the device) into `baseline.measured`. Every other area/mode must sit under
baseline × **headroom**:

| number | headroom | why |
|---|---|---|
| frame p50 | ×1.15 | the typical frame may cost 15 % more than the cage's |
| frame p95 | ×1.25 | the slow 5 % a quarter more |
| frame p99 | ×1.35 | the slowest 1 % a third more |
| hitches / 60 s | cage + 2, floor 3 | a handful of >20 ms frames a minute is invisible; a run of them is "the lag" — not enforced when the baseline p50 is already within 80 % of `hitch_ms` (the phone), where every frame would count |
| spikes / 60 s | cage + 3, floor 6 | frames over 1.5 × the run's own p50: stutter at any frame rate |
| draw calls (visible + shadow, both views) | ×1.5 | the cage's 177 surfaces are many small draws; an area may spend more draws, not many more |
| script p95 | ×1.3 | the fx scripts' share |
| see-through coverage | 1.5 screens (absolute) | the cage has none; one and a half screens of blended pixels is the ceiling |
| triangles | logged | not the problem (cage 4.4k, city 21.7k) |

    godot --headless --path . -s tools/perf_ledger.gd -- --in=build/qa/<model>/perf.json

prints the table, the limits and every gap (`beach heat_pip frame_p95 24.1 ms >
19.6`), exits 1 on a break and 2 with no baseline. `tests/test_perf_budget.gd`
pins the arithmetic (`core/perf/perf_budget.gd`).

## 3. Numbers

### Stage 1 — the first measurement (2026-10-23, build at 6efa52d + the probe)

**Ross's phone** (moto g - 2025, Mali-G57 MC2, Android, mobile renderer, 720×1604,
24 s after a 3 s warm-up; `build/qa/moto_g_-_2025/perf.json`):

    area   mode         p50    p95    p99 hit60 spk60 |  mainC  mainG   pipC   pipG |  drwV  drwS | script   cov pipDrw |    tris
    cage   heat_pip    19.4   27.9   31.5  1001 131.2 |    1.0   13.9    0.7    1.9 |   145     0 |    7.6  0.00  145+0 |   28706
    cage   heat_min    19.7   28.9   32.3  1209 119.5 |    0.9   14.0    0.7    2.0 |   145     0 |    7.6  0.00  145+0 |   28708
    cage   trial       18.3   22.4   32.2   233  91.3 |    1.7   15.2      -      - |   143     0 |    2.2  0.00      - |   13484
    beach  heat_pip    22.7   28.1   29.6  2321   0.0 |    0.7   14.6    0.5    5.2 |    51    50 |    6.6  0.01  49+49 |   47207
    beach  heat_min    24.2   26.5   29.4  2385   0.0 |    0.8   16.2    0.5    5.3 |    51    50 |    7.2  0.01  49+49 |   47282
    beach  trial       18.8   21.5   29.9   326  45.2 |    1.6   15.8      -      - |    48    48 |    2.4  0.01      - |   22395
    park   heat_pip    34.7   41.8   44.4  1718   0.0 |    1.6   26.9    1.1    5.3 |    74    57 |   15.9  0.00  72+57 |  142025
    park   heat_min    29.2   33.1   33.7  2065   0.0 |    1.1   22.5    0.8    4.5 |    74    57 |    9.8  0.00  73+57 |  142019
    park   trial       25.0   31.3   32.6  2206   0.0 |    1.5   22.9      -      - |    70    55 |    2.0  0.00      - |   69918
    city   heat_pip    30.0   33.3   35.6  1998   0.0 |    1.1   23.7    0.8    4.1 |    82    58 |   10.8  0.04  78+57 |  152059
    city   heat_min    30.7   33.3   34.2  1910   0.0 |    1.1   24.3    0.8    4.2 |    82    58 |   10.7  0.04  78+57 |  152079
    city   trial       24.4   25.6   28.7  2422   0.0 |    1.6   22.5      -      - |    75    56 |    2.5  0.01      - |   74514
    cage   heat_pip*   19.7   27.2   30.6  1085  77.7 |    1.0   13.7    0.8    2.0 |   145     0 |    7.7  0.00  145+0 |   28713

**The Mac** (Mac17,3, Apple M5, 360×640 window at 144 Hz; every row p50/p95/p99
6.9 ms, no hitches — frame times quantise to the display, so only the draw
counts, the script time and the triangles carry information;
`build/qa/mac/perf.json`): script p95 heats 2.1–2.3 ms (city 3.9), trials
0.5–0.7 ms; draws and triangles match the phone's rows.

What the phone says:

- **The phone is GPU-bound in every area.** The main view's GPU time is 14 ms
  in the cage, 15–16 ms on the beach, 22–27 ms in the park and the city; the
  render CPU is 1–2 ms. The frame p50 follows it: cage 19 ms, beach 23–24,
  city 30, park 29–35. "Only the cage is smooth" is 14 ms of GPU against 22+.
- **Shadows are the main view's extra cost.** The cage draws 145 surfaces with
  no shadow pass; the beach, park and city draw 50–82 visible surfaces plus
  **50–58 shadow draws** (a second pass over the whole court at 1024–2048 px),
  and their trials — no PiP at all — already run at 24–25 ms p50 in the park
  and the city, over the cage's whole heat. Triangles are not it (beach 47k,
  park 142k, city 152k on the phone — the park's trees — and the beach is as
  slow as its shadow pass, not its triangles).
- **The PiP costs 2 ms of GPU in the cage and 4–5 ms everywhere else** (its
  own shadow pass: 49–57 shadow draws), plus script. Minimizing it today
  (`heat_min`) changes nothing: the PiP's GPU time is still 4–5 ms with the
  viewport "disabled" (the measurement runs on; see Stage 2 for the fix) and
  its fx scripts keep running.
- **A heat costs 5 ms of script a frame before any area fx**: cage trial 2.2 ms
  → cage heat 7.6 ms (two net sims, the AI, two LED boards, the PiP court's
  fx `_process`); the park heat reaches 15.9 ms p95 (snow + trees + the PiP's
  copy), the city 10.8. On a 60 Hz budget that is a third of the frame.
- **Stutter**: the cage's frames are bimodal — 60 fps with 7–8 % of frames
  dropping to a double frame (`spk60` 78–131 = frames over 1.5 × p50); the
  other areas sit steadily at 30–40 fps, so they show no spikes and every
  frame counts as an absolute "hitch" (`hit60` 1000–2400 — which is why the
  budget does not enforce the absolute count on this device).
- **Thermal drift is negligible over the sweep**: the cage heat measured first
  and last (the `*` row) differ by 0.3 ms p50.
- **See-through coverage** is tiny everywhere (max 0.04 screens in the city):
  blended overdraw is not the problem.

The baseline is the phone's `cage heat_pip` row (written into
`data/perf_budget.json` by `--set-baseline`). Against the proposed headroom the
ledger reports: the beach heats over on p50 only (22.7 / 24.2 vs 22.4), the
park and the city heats over on p50 (29–35 vs 22.4) and script p95 (10–16 vs
9.9), the park heat_pip also over on p95/p99, and the park and city **trials**
over on p50 (24–25 vs 22.4). Expected gains: Stage 2 (a shadowless, static,
30 Hz PiP) takes 4–5 ms of GPU and 3–8 ms of script out of every heat — that
brings the beach inside and the city close, but not the park; Stage 3's main-view
shadow work (fewer casters, then baked shadows) is what the park and the city
need, since their trials are already over the line without a PiP.

### Stage 2 — the lite opponent view and the kit (2026-10-23)

What changed: the PiP's court runs `CourtGeometry.Profile.PIP` — no sun
shadows (no atlas call), every area fx frozen after it is built (`freeze()` on
BeachFx / ParkFx / CityFx / ArcadeFx: a static ocean, palms, trees, facades;
no birds, pelican, ship, plane, traffic, pigeons, snow or smoke; the shader
sky stays, it runs on TIME); fog, ambient, fill and sun colour kept. The
window draws at half rate (`HeatScreen.PIP_EVERY` 2: `UPDATE_ONCE` armed
every other frame, its ball / rim / net / magnet stepped with both frames'
dt); minimized, its viewport and its court's processing both stop. The rim
fire and ice write no uniforms while out. The PiP wears the opponent's
**kit** (docs/LOCKER.md → The kit) online and the court's stock pair solo.

**Ross's phone**, heats only (trials unchanged within noise; the full table is
`build/qa/moto_g_-_2025/perf.json`, Stage 1's kept in `…_stage1/`):

    area  mode      | frame p50 before→after | p95 | script p50 | script p95 | fps  | PiP shadow draws
    cage  heat_pip  |  19.4 → 19.4 | 27.9 → 29.2 | 5.1 → 4.7 |  7.6 →  8.8 | 50 → 49 | 0 → 0
    cage  heat_min  |  19.7 → 20.8 | 28.9 → 29.0 | 5.2 → 4.8 |  7.6 →  9.1 | 50 → 47 | 0 → 0
    beach heat_pip  |  22.7 → 20.8 | 28.1 → 29.3 | 4.6 → 4.6 |  6.6 →  8.5 | 44 → 47 | 49 → 0
    beach heat_min  |  24.2 → 22.2 | 26.5 → 29.2 | 5.0 → 4.3 |  7.2 →  8.4 | 41 → 46 | 49 → 0
    park  heat_pip  |  34.7 → 33.3 | 41.8 → 41.4 | 12.1 → 10.5 | 15.9 → 18.0 | 29 → 29 | 57 → 0
    park  heat_min  |  29.2 → 28.3 | 33.1 → 33.3 | 6.8 → 5.9 |  9.8 → 11.0 | 35 → 35 | 57 → 0
    city  heat_pip  |  30.0 → 27.8 | 33.3 → 33.3 | 7.0 → 5.8 | 10.8 → 10.8 | 33 → 36 | 57 → 0
    city  heat_min  |  30.7 → 28.3 | 33.3 → 33.3 | 7.0 → 5.9 | 10.7 → 10.5 | 33 → 35 | 57 → 0

- **The beach heats are inside the budget** (p50 20.8 / 22.2 vs the 22.4
  limit); the city gained 2.2 ms and the park 1.4 ms of p50 — as predicted,
  the window was 2–5 ms of the frame and the main view's shadow pass is the
  rest. The PiP's own render time no longer measures (a viewport drawn with
  `UPDATE_ONCE` reports 0; the frame time carries it).
- **Script p50 fell, script p95 rose** everywhere by 1–2 ms: the window's
  ball, rim and net now step every other frame with twice the dt, so the
  per-frame script cost alternates heavy / light and the 95th percentile
  reads the heavy frame. The frame-time p95 did not move (the phone is
  GPU-bound), so it is a measurement artefact of the half rate, not stutter.
- **The park heat still spends 10.5 ms p50 of script against the cage heat's
  4.7** while its trial spends 1.8: something the heat does every frame costs
  the park 6 ms (the flip scoreboard's `set_visitor` is written every frame
  from `HeatScreen._process`; the first Stage 3 item to measure).
- Triangles: the PiP's frozen fx and no shadow pass took the beach from 47k
  to 36k and the park from 142k to 95k (the far trees' shadow casters).
- PiP before/after crops per area: `build/qa/pip/before_<area>.png` /
  `after_<area>.png` (Stage 1 and Stage 2 phone snaps, the window at 1:1).
  The window keeps its look: the ocean, palms, trees, sky and facades stand
  still and shadowless; the opponent's ball, net, rim fx and LED play on.

Still over after Stage 2: the park and the city heats on p50 (28–33 vs 22.4)
and script p95, the park heat_pip on p95 / p99, and the park and city trials
on p50 — the main view's shadow pass (Stage 3).

## 4. Rules for effects (Stage 3; apply to every new effect)

1. **Animate in the shader with `TIME`.** Never set a shader parameter from
   GDScript every frame (the city clouds' per-frame uniform write was the
   precedent that lagged). A value that must be shared (the tide, the wind) is
   a global shader uniform written once when it changes.
2. **Repeated things are one MultiMesh** — birds, pigeons, cars, palms; the
   park's trees already are. Per-instance phase goes in `INSTANCE_CUSTOM`.
3. **One manager per area** drives the ambient life at a reduced tick (15–30 Hz
   through an accumulator), not a `_process` per object; nothing allocates per
   frame (reuse arrays, no `Vector3(...)` churn in loops).
4. **Opaque or alpha-scissor over alpha-blend**, above all on large surfaces
   (the beach shoreline); the probe's coverage number is the check.
5. **Visibility ranges** (`visibility_range_begin/end`) for far detail.
6. **Shadows**: only the ball, hoop, net and near props cast; scenery and far
   props are `cast_shadow = OFF`. Baked shadows in the ground/court textures
   (a Blender pass) with a blob under the ball let an area run `sun_shadows =
   false` like the cage — proposed with before/after shots, never shipped
   without Ross's OK (`arena_set.tres` is his).
7. **`arena_set.render_scale` is a last resort**, proposed per area with
   screenshots only, and never under 0.85 (0.7 was rejected as blurry).
8. **Shader stutter**: a hitch that lines up with an effect's first appearance
   (a card's fx, the rim pop, the PiP's first frame) is a pipeline compile;
   warm the material on the pre-match page.
9. **The opponent view is lite** (`CourtGeometry.profile = PIP`): no sun
   shadows, no area fx motion, a static backdrop, drawn at 30 Hz; it keeps the
   fog, the ambient and the sun colour, and the opponent's net, ball and their
   effects (they react to every shot).
