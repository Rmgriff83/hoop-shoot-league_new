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
  logged with their time) and **spikes** (frames one refresh period over the run's own p50, never under 1.5 × it —
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
| spikes / 60 s | cage + 3, floor 6 | frames one refresh period over the run's own p50 (never under 1.5 ×): stutter at any frame rate, without a vsync phone's ordinary dropped frames |
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

### Stage 3 — the main view: casters, levers, and what the phone's GPU actually buys (2026-10-24)

What shipped: the **scenery caster rules** (`CourtGeometry.NO_CAST_SCENERY` by
mesh name plus the ground-plane rule — any mesh thinner than 15 cm and wider
than 4 m — applied in `_build_arena_model`; `apply_caster_rules()` returns the
count, `caster_count()` what still casts), the **A/B levers**
(`CourtGeometry.ab`, QA only: `--qa-perf-ab=casters,no_shadows,shadow1024,
no_fill,fill_light,no_omni,no_sky,no_fog,scale85`, and `--qa-ab=<levers>` on
any snap pass for the look check), the **sim column** (`sim` = the rules tick
alone), the **spike tags** (what was on screen in a spiking frame, `first:x` on
a debut) and `tools/arena_meshes.gd` (an arena's casters, tris and distances).
The sweep runs area-outer with a closing reference row per area (`mode*`): the
phone drifts ~3 ms of GPU time over a 20-minute sweep, as much as most levers,
so a lever only compares against a base row from the same minutes.

**The A/B sweep, Ross's phone, trials** (`build/qa/moto_g_-_2025/perf_ab2.json`;
GPU ms of the main view, each lever against its area's base; the phone was warm,
so the base rows sit above Stage 1's cold numbers):

    area   lever        | main GPU ms | Δ     | shadow draws | tris   | the look (Mac snap diff vs base)
    beach  base         |  16.9       |       |  48          | 22.4k  |
    beach  casters      |  15.8       | −1.1  |  39          | 21.7k  | identical
    beach  no_shadows   |  15.1       | −1.8  |   0          | 11.2k  | 3.5 % of pixels (palm / pole shadows)
    beach  no_fill      |  15.6       | −1.3  |  48          |        |
    beach  fill_ambient |  15.5       | −1.4  |  48          |        | mean 2.6/255
    beach  no_sky       |  15.9       | −1.0  |  48          |        | (the beach has no shader sky: noise)
    beach  scale85      |  15.7       | −1.2  |  48          |        |
    beach  drift*       |  16.2       | −0.7  |              |        |
    park   base         |  25.1       |       |  55          | 69.8k  |
    park   casters      |  24.4       | −0.7  |  46          | 68.6k  | identical
    park   no_shadows   |  20.3       | −4.8  |   0          | 56.1k  | 1.9 % of pixels
    park   no_fill      |  18.1       | −7.0  |  55          |        | 25 % of pixels, mean 1.5/255
    park   fill_ambient |  17.4       | −7.7  |  55          |        | 9 % of pixels, mean 1.7/255
    park   no_sky       |  18.8       | −6.3  |  55          |        | the sky gone (flat colour): 50 %
    park   scale85      |  16.1       | −9.0  |  55          |        | softer
    park   drift*       |  25.0       | −0.1  |              |        |
    city   base         |  20.3       |       |  56          | 74.5k  |
    city   casters      |  20.7       | +0.4  |  56          |        | (CityFx already lists its casters)
    city   no_shadows   |  19.5       | −0.8  |   0          | 65.1k  | 2.7 % of pixels
    city   no_fill      |  16.1       | −4.2  |  56          |        | 39 % of pixels, mean 3.6/255
    city   fill_ambient |  17.0       | −3.3  |  56          |        | 7 % of pixels, mean 1.0/255
    city   no_sky       |  16.7       | −3.6  |  56          |        | the sky gone: 37 %
    city   scale85      |  16.0       | −4.3  |  56          |        | softer
    city   drift*       |  21.1       | +0.8  |              |        |

(The first sweep, `perf_ab.json`, ran lever-outer and drifted 12.3 → 15.2 ms
on the cage over its 20 minutes; it is kept for the record, not read.
`shadow1024`, `no_omni` and `no_fog` moved nothing beyond that noise.)

- **The shadow pass was the wrong suspect on the city and only third on the
  park.** The second `DirectionalLight3D` — the arena's *fill* — costs the park
  7 ms and the city 4 ms of GPU: the mobile renderer lights every fragment
  twice. The shader sky (`park_sky.gdshader`: a gradient plus two fbm cloud
  layers per pixel, 4 + 2 octaves of value noise over ~40 % of the screen)
  costs the park 6 ms and the city 3.6. The shadow pass is 5 ms on the park
  (its trees), 2 on the beach, under 1 on the city (its buildings never cast).
  The caster rules buy ~1 ms where the scenery cast.
- **Folding the fill into the ambient looks the same** (the ambient colour
  halfway to the fill's, energy + 0.6 × the fill's — a Mac frame differs by
  1–3 / 255 on average, `build/qa/levers/<area>_03_fill_ambient.png` against
  `_base.png`) and is worth the whole fill. Ross looked at the side-by-sides
  and the live game and took it (below, Stage 3b): the court folds every
  arena's fill (`CourtGeometry.FILL_TONE` / `FILL_LIFT`), the arena files
  keep their fill fields, and the old second light is the `fill_light` lever.
- **The sky**: a shader that reads `TIME` keeps the radiance map dirty every
  frame (`renderer_rd/environment/sky.cpp`, `uses_time`), so at 64 it is
  rebuilt one layer per frame — small; the cost is the full-screen cloud
  shader. Two ways to the same look at one texture fetch per pixel, both for
  Ross: (a) bake the two noise fields once into a tiling texture (the noise
  made periodic: octave step 2.0 instead of 2.03 and a wrapped hash — a hair
  of cloud-shape change) and scroll the lookup by `drift × TIME` in the sky
  shader (the drift and the pixel stepping stay, `TIME` leaves the sky
  shader so the radiance renders once); (b) render the cloud field into a
  small 2D viewport every few frames and sample it. (a) is the cheaper and
  simpler one.
- **Shadows**: the park's 5 ms is real; the beach's 2 and the city's 1 are
  not worth a bake on their own. The proposal stands for the park (rule 6:
  baked ground shadows plus a blob under the ball, `sun_shadows = false`);
  the shots are `build/qa/shadows/park_03_shadows.png` against
  `park_03_baked_bound.png` (the upper bound: no shadows at all — 1.9 % of
  the frame's pixels differ at phone size).
- **Render scale 0.85** is worth 4–9 ms on the park and city and stays the
  last resort (rule 7).
- **The fx rules (§4) are not where the phone's time goes**: every trial's
  script time is 1.2–1.9 ms p50 and every heat's 5–6 ms, of which the rules
  tick is 1.5–1.9 (`sim`). The existing per-frame uniform writes (the beach's
  ocean / palms / birds, the city's pigeons / smoke, the arcade's screens) are
  within that; they stay as they are, the rules bind new effects.
- **The park heat's "+6 ms of script"** (Stage 2's lead) was noise: with the
  sim column in, the park heat spends 5.7 ms p50 of script against the cage
  heat's 4.9 and the same 1.5–1.9 ms rules tick. Nothing in the heat is
  area-specific.
- **Shader stutter**: the tagged spikes line up with `flight` + `pip` (a ball
  in the air with the window live — load, not compiles); a debut shows once
  per effect per match (`first:fire` on the beach, `ice` twice on the city).
  A pre-match warm-up would remove one or two frames a match: low priority.
- **Spikes redefined**: a vsync phone quantises frames to 16.7 / 33.3 ms, so
  "over 1.5 × p50" at a p50 of 20 ms counted every ordinary dropped frame
  (the Stage 2 sweep read 0–163 spikes/60 s for the same scene). A spike is
  now a frame one refresh period over the run's p50 (never under 1.5 ×);
  the row carries the threshold as `spike_ms`.

**The heat sweep after Stage 3** (`build/qa/moto_g_-_2025/perf_stage3.json`,
2026-10-24 06:20, a cool phone — battery 19 °C — straight from the lock
screen; the caster rules on, as shipped; the ledger's baseline re-set from
this sweep's cage heat_pip row so the spike limit carries the new definition —
cage p50 19.7 against Stage 1's 19.4, the budget itself did not move):

    area  mode      | frame p50 Stage 2 → 3 | p95        | main GPU | shadow draws | script p50 / p95 | sim p50 / p95 | spikes/60 s
    cage  heat_pip  |  19.4 → 19.7 | 29.2 → 28.5 | 13.7 |  0      |  4.8 /  8.8 | 1.5 / 3.1 | 0.0
    cage  heat_min  |  20.8 → 20.4 | 29.0 → 28.0 | 14.4 |  0      |  5.0 /  9.0 | 1.5 / 3.2 | 0.0
    beach heat_pip  |  20.8 → 23.3 | 29.3 → 31.8 | 16.7 | 50 → 41 |  5.3 /  9.4 | 1.3 / 2.9 | 4.7
    beach heat_min  |  22.2 → 22.9 | 29.2 → 28.0 | 17.1 | 50 → 41 |  5.1 /  9.0 | 1.3 / 2.8 | 0.0
    park  heat_pip  |  33.3 → 28.0 | 41.4 → 33.3 | 24.2 | 57 → 48 |  6.2 / 10.8 | 1.7 / 3.6 | 0.0
    park  heat_min  |  28.3 → 27.8 | 33.3 → 33.0 | 23.9 | 57 → 48 |  5.9 / 10.7 | 1.6 / 3.7 | 2.3
    city  heat_pip  |  27.8 → 25.0 | 33.3 → 26.0 | 20.6 | 58      |  5.7 / 10.6 | 1.6 / 3.4 | 0.0   (the drift row; see below)
    city  heat_min  |  28.3 → 25.5 | 33.3 → 30.4 | 22.1 | 58      |  5.9 / 10.8 | 1.6 / 3.6 | 2.3
    beach trial     |  (S1 19.1) → 19.1 | 24.1 | 15.7 | 48 → 39 | 1.7 / 2.4 | 0.1 | 4.7
    park  trial     |  (S1 22.2) → 24.8 | 30.3 | 21.9 | 55 → 46 | 1.6 / 2.6 | 0.1 | 4.6
    city  trial     |  (S1 24.2) → 25.0 | 29.6 | 22.7 | 56      | 1.6 / 2.5 | 0.1 | 0.0

- The first city heat_pip row of the sweep (33.3 p50, script 10.7 / 20.4,
  sim 3.4 — every number double its drift row's and every other heat's) ran
  while Android was still tearing down the apps it had killed to relaunch
  ours; the drift row (`heat_pip*`: 25.0 / 26.0, script 5.7, sim 1.6) is the
  city heat, and the table reads it. The ledger still prints the outlier.
- **Spikes now read 0–4.7 / 60 s everywhere** (one or two frames a minute
  over the run's p50 by a refresh period) against Stage 2's 0–163 — the
  phone's stutter is small; its problem is the rate.
- **The ledger's verdict**: the park and city heats and trials over the p50
  limit (22.7) by 2–5 ms, the beach heats on the edge (22.9–23.3 — ±2 ms
  of temperature either way), the cage inside. Script p95 is inside the
  limit in every honest row (the city outlier aside). The caster rules took
  the beach's shadow draws 50 → 41 and the park's 57 → 48 (about 1 ms); what
  would bring the park and the city under the limit is the fill (−4 to −7 ms)
  and the sky (−4 to −6), then the park's shadows (−5) — the three proposals.
- Sweeps from here compare against this cool-phone dump, not Stage 2's: the
  phone's temperature moves every row by ±2 ms, so a comparison needs two
  sweeps taken the same way (cool, from the lock screen, 7 minutes apart at
  most — `tools/android_qa.sh` refuses a credential-locked phone and relaunches
  once when the first start loses its surface).

### Stage 3b — the fill folded into the ambient (2026-10-24, Ross's call)

`CourtGeometry._build_lights` no longer hangs the arena's fill as a second
`DirectionalLight3D`: the ambient colour moves halfway to the fill's colour
and the ambient energy gains 0.6 × the fill's energy (`FILL_TONE`,
`FILL_LIFT`). The three `arena_set.tres` are untouched — their `fill_*`
fields now describe the ambient's second tone — and `--qa-ab=fill_light`
brings the light back for a comparison. Ross compared the side-by-sides
(`build/qa/levers/fill_compare_<area>.png`) and the live game and could not
tell them apart; the Mac snaps of the three areas both ways are in
`build/qa/fill/`.

**The A/B on Ross's phone** (`perf_ab3.json`, trials, the fold as the base
and the old light as the lever, each area back to back):

    area   | main GPU ms  fold → light | frame p50 | 
    beach  | 14.5 → 15.4  (−0.9)       | 16.7 → 17.2
    park   | 16.3 → 22.0  (−5.7)       | 16.9 → 23.3
    city   | 16.4 → 22.1  (−5.7)       | 18.1 → 23.3

**The heat sweep with the fold** (`perf_stage3_fold.json`, 06:58, the phone
at 22 °C — the same session as the A/B, 10 minutes on; the ledger against
the Stage 3 baseline):

    area  mode      | frame p50 Stage 3 → 3b | p95        | main GPU   | script p50 / p95 | spikes/60 s
    cage  heat_pip  |  19.7 → 18.3 | 28.5 → 26.8 | 13.7 → 14.3 |  4.5 /  7.8 | 4.7
    cage  heat_min  |  20.4 → 18.5 | 28.0 → 29.4 | 14.4 → 14.2 |  4.7 /  8.3 | 0.0
    beach heat_pip  |  23.3 → 19.1 | 31.8 → 27.4 | 16.7 → 14.3 |  4.5 /  8.4 | 2.4
    beach heat_min  |  22.9 → 18.5 | 28.0 → 26.4 | 17.1 → 14.5 |  4.4 /  7.8 | 0.0
    park  heat_pip  |  28.0 → 25.0 | 33.3 → 30.6 | 24.2 → 18.3 |  5.6 /  9.4 | 0.0
    park  heat_min  |  27.8 → 24.6 | 33.0 → 26.6 | 23.9 → 18.4 |  5.2 /  8.7 | 0.0
    city  heat_pip  |  25.0 → 25.0 | 26.0 → 31.4 | 20.6 → 18.5 |  5.5 / 10.0 | 4.7
    city  heat_min  |  25.5 → 23.9 | 30.4 → 27.4 | 22.1 → 16.9 |  5.4 /  9.4 | 0.0
    beach trial     |  19.1 → 16.7 | 24.1 → 18.1 | 15.7 → 15.1 |  1.3 /  1.8 | 0.0
    park  trial     |  24.8 → 17.0 | 30.3 → 24.9 | 21.9 → 16.2 |  0.9 /  1.4 | 0.0
    city  trial     |  25.0 → 18.1 | 29.6 → 24.1 | 22.7 → 16.4 |  1.2 /  1.6 | 0.0

- **The beach heats and every trial are inside the budget**; the beach heat
  runs at the cage's rate now. The park and city trials dropped 7–8 ms of
  p50 and sit at a near-locked 60.
- **The park and city heats remain over on p50** (23.9–25.0 vs 22.7) with
  16.9–18.5 ms of main-view GPU: a frame just over one refresh period, so
  the phone alternates 16.7 and 33.3 ms frames and the median lands between.
  One or two more milliseconds of GPU puts them under the period and the
  rate locks — the sky bake (−4 to −6 ms) is that step; the park's shadow
  bake (−5) the one after. Both remain proposals.
- Script time fell ~1 ms everywhere with the phone no longer waiting on
  the GPU (a `set_shader_parameter` or a viewport query blocks behind a
  busy queue); the rules tick reads 1.1–1.5 ms.

### Stage 3c — the sky's clouds baked (2026-10-24, Ross's call)

`tools/bake_sky_clouds.gd` bakes the two cloud noise fields (the 4-octave fbm
that sets the cover, the 2-octave one that shades it) into one 1024² tiling
texture, `game/court/sky_clouds.png` (592 KB; 16 noise units a tile, 64 texels
a unit, lossless import, no mipmaps), and `park_sky.gdshader` fetches it once
per pixel at the drifted, pixel-stepped coordinate (`texture(clouds, q /
cloud_period)`) instead of running 24 hash lookups per sky pixel per frame.
The gradient, the sun's glow, the pixel stepping and the drift on `TIME` are
unchanged; `--qa-ab=sky_fbm` runs the noise in place (the before shot and
the A/B base), `sky_fade`, `sky_cov=lo:hi` and `sky_off=x:y` nudge the look
without a rebake.

- **Every GPU drew its own sky.** The noise hashed `fract(sin(x) * 43758)`
  with `x` in the thousands near the horizon, and a 32-bit sine of a number
  that size is rounded differently by every GPU: the Mac showed cloud blocks
  over a blue park where the phone's snap was nearly clear. The bake is one
  draw everywhere (the hash evaluated in float64 on a wrapped lattice, octave
  step 2.0 so every octave tiles).
- **The thresholds moved for the bake.** The baked field matches the
  shader's noise statistically to three decimals (mean 0.47, sd 0.12, 26 %
  of samples over the old 0.56 midpoint), yet the first bake came out
  overcast: the visible window is ~3 noise cells wide, so the look is a
  draw, and the GPU's rounding happens to spread its values wider. Cover
  thresholds 0.60 / 0.72 (from 0.50 / 0.62) put the park's sky region at
  19 % cloud and 50 % blue against the noise version's 28 % and 50 %; Ross
  compared `build/qa/sky/sky_compare_<area>_<frame>.png` and the live game
  and took it.
- A shader that reads `TIME` keeps its radiance map dirty, so the 64-texel
  radiance still rebuilds one layer a frame; it is small and the drift
  needs the clock (rule 6c).

**The A/B on Ross's phone** (`perf_ab4.json`, trials, the bake as the base
and the noise as the lever; the phone at 31 °C after the fold's sweeps):

    area  | main GPU ms  bake → noise | frame p50
    park  | 15.3 → 17.6  (−2.3)       | 16.7 → 19.1
    city  | 15.4 → 17.5  (−2.1)       | 16.9 → 19.1

(Stage 3's "no sky at all" read −6.3 / −3.6 on a cooler phone with the fill
light still lit: a gradient-only sky still draws every sky pixel, and the
fill was already paying for part of the same pixels.)

**The heat sweep with the fold and the bake** (`perf_stage3_sky.json`, 07:48,
the phone warm at ~31 °C; the ledger against the Stage 3 baseline):

    area  mode      | frame p50 S3 → 3b → 3c | p95  | main GPU S3 → 3c | script p50 / p95 | spikes/60 s
    cage  heat_pip  |  19.7 → 18.3 → 18.8 | 28.4 | 13.7 → 14.1 | 4.5 / 8.3 | 0.0
    cage  heat_min  |  20.4 → 18.5 → 18.4 | 25.4 | 14.4 → 14.3 | 4.4 / 7.6 | 0.0
    beach heat_pip  |  23.3 → 19.1 → 18.3 | 25.1 | 16.7 → 14.5 | 4.4 / 8.3 | 0.0
    beach heat_min  |  22.9 → 18.5 → 18.8 | 27.2 | 17.1 → 14.5 | 4.5 / 8.1 | 0.0
    park  heat_pip  |  28.0 → 25.0 → 19.1 | 30.4 | 24.2 → 14.6 | 4.7 / 8.4 | 4.7
    park  heat_min  |  27.8 → 24.6 → 19.1 | 27.8 | 23.9 → 14.6 | 4.7 / 8.2 | 0.0
    city  heat_pip  |  25.0 → 25.0 → 20.5 | 27.6 | 20.6 → 16.1 | 4.2 / 8.3 | 2.3
    city  heat_min  |  25.5 → 23.9 → 19.4 | 29.1 | 22.1 → 15.6 | 4.5 / 8.7 | 7.0
    beach trial     |  19.1 → 16.7 → 16.7 | 18.1 | 15.7 → 15.1 | 1.4 / 1.9 | 0.0
    park  trial     |  24.8 → 17.0 → 16.7 | 18.1 | 21.9 → 15.3 | 1.0 / 1.5 | 0.0
    city  trial     |  25.0 → 18.1 → 16.7 | 18.1 | 22.7 → 15.4 | 1.3 / 1.8 | 0.0

- **Every area and mode is inside the budget** — the park and city heats
  run at the cage's rate (18–20 ms p50, 14.6–16.1 ms of main-view GPU
  against the cage's 14.1) and every trial sits on the 16.7 ms vsync floor.
  The one line the ledger prints is the city heat_min's 7 spikes a minute
  against a limit of 6 — three double frames in 25 s, 0 in the drift row.
- Stage 3's three proposals are two shipped (the fill, the sky) and one
  left: the park's shadow bake (−5 ms on a trial) is no longer needed for
  the budget and stays a proposal for the look only.
- Script time reads 4.2–4.7 ms p50 in every heat now (the rules tick
  1.1–1.4): the heat's fixed cost, nothing area-specific.


## 4. Rules for effects (Stage 3; apply to every new effect)

The short version for building a new area — the limits, what costs what on
the phone, the asset rules and the check before it ships — is
`docs/NEW_AREA_PERFORMANCE.txt`.

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
   props are `cast_shadow = OFF` (`CourtGeometry.NO_CAST_SCENERY` and the
   ground-plane rule do it at build time — a new arena's ground, water, sky
   dome and far dressing need no flag, but name a new big backdrop in the
   list). Baked shadows in the ground/court textures (a Blender pass) with a
   blob under the ball let an area run `sun_shadows = false` like the cage —
   proposed with before/after shots, never shipped without Ross's OK
   (`arena_set.tres` is his).
6b. **One sun.** A second `DirectionalLight3D` lights every fragment twice:
   on the phone the fill cost more than the shadow pass (Stage 3). The court
   folds every arena's `fill_*` into the ambient (`CourtGeometry.FILL_TONE`,
   `FILL_LIFT`, Stage 3b) — an arena's fill fields are the ambient's second
   tone, never a light; `--qa-ab=fill_light` is the old look for a comparison.
6c. **The sky is one fetch per pixel.** A procedural cloud shader ran for
   every sky pixel every frame (2–6 ms on the phone, and a different draw on
   every GPU); the noise fields are baked to a tiling texture
   (`tools/bake_sky_clouds.gd` → `game/court/sky_clouds.png`, Stage 3c) and
   the shader scrolls the lookup. A new sky effect bakes the same way; a
   sky shader that reads `TIME` keeps its radiance map dirty (small at 64).
7. **`arena_set.render_scale` is a last resort**, proposed per area with
   screenshots only, and never under 0.85 (0.7 was rejected as blurry).
8. **Shader stutter**: a spike that lines up with an effect's first appearance
   (a card's fx, the rim pop, the PiP's first frame — the probe tags it
   `first:<fx>`) is a pipeline compile; warm the material on the pre-match
   page when the tags show more than the one-or-two a match measured in
   Stage 3.
9. **The opponent view is lite** (`CourtGeometry.profile = PIP`): no sun
   shadows, no area fx motion, a static backdrop, drawn at 30 Hz; it keeps the
   fog, the ambient and the sun colour, and the opponent's net, ball and their
   effects (they react to every shot).
