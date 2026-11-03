# PSX Textures II — Pizza Doggy

- **Source:** https://pizzadoggy.itch.io/psx-textures-2 ("PSX Textures II", Pizza Doggy;
  the tile is listed as `brick_wall_pt_2` in the free-assets browser at
  https://pizzadoggy.com — Ross supplied the png on 2026-11-01)
- **Licence:** Pizza Doggy's Game Assets License Agreement, November 2025 (`LICENSE.pdf`
  beside this file, from https://pizzadoggy.com/other-downloads/License%20Agreement.pdf):
  a non-exclusive, worldwide, perpetual licence to use, modify and incorporate the assets
  in any game, commercial or not, no royalties; **never** resell, redistribute or share
  the assets on their own (edited or not), never bundle them in packs, templates or
  open-source projects for reuse, never use them as AI training data or input.
  Ownership stays with Pizza Doggy. Attribution appreciated, not required (the suggested
  line is "Game Assets by Pizza Doggy" plus a link) — credited in `data/credits.json`
  (the in-game credits screen, MODELS tab).
- **Pulled:** 2026-11-01
- **Used for:** the brick wall behind the splash, the new player page and the area
  archive (`tools/render_brick_wall.gd` tiles the png at 4x nearest, darkens it to a mean of ~24/255 and
  writes `assets/splash/neon_bg.png`; `tools/make_boot_splash.gd` then rebuilds the
  boot splash from it). The same tool writes the tile on its own darkening
  (`CAGE_DARK` 0.6) to `assets/textures/cage_brick.png` for the back wall behind the
  arcade cage's cabinet row (`tools/blender/build_cage.py`, embedded in `cage.glb`).
  `asphalt_old_tr_1.png` (Ross supplied it 2026-11-02 as Pizza Doggy's; the pack it came
  from was not recorded) skins the beach's embankment walls as is, tiled every metre
  (`tools/blender/build_beach.py`, embedded in `beach.glb`). `tools/render_cage_fence.gd`
  cuts the chain-link out of it for the arcade cage's side and top fences and its gate
  (`assets/textures/cage_fence_asphalt.png`, embedded in `cage.glb`).
  `small_stones_tr_1.png` (Ross supplied it 2026-11-02, pack not recorded) skins the park's
  `Court` slab as is, tiled every metre, and `grass_pt_3.png` (same) its `Lawn`, every 4 m
  (`tools/blender/build_park.py`, embedded in `park.glb`). The city's ground wears
  `asphalt_old_tr_1.png` and its fence the cage's cut (`tools/blender/build_city.py`).
  `dirt_pt_10.png` also gives the arcade cage's machine row its grain, reduced to a grey
  128 px tile by `tools/render_machine_grain.gd` (`assets/textures/cage_machine_grain.png`).
  `snow_tr_1.png` (Ross supplied it 2026-11-03, pack not recorded) is the park's lying snow, lifted by `tools/render_park_snow.gd`
  (`assets/textures/park_snow_drift.png`). `building_ceiling_pt_1.png` (same) is grain over
  the arcade hall's ceiling colour (`tools/render_cage_ceiling.gd`,
  `assets/textures/cage_ceiling_grain.png`).
  `dirt_pt_5.png` (same) gives the beach's sand its grain and `dirt_pt_10.png` (same) the grey
  of its court and backboard: `tools/render_beach_grain.gd` keeps our colours and takes only the
  dirt's light and dark (`beach_sand_dirt.png`, `beach_court_grain.png`, `street_board_grain.png`).
  `water_2.png` (Ross confirmed it as Pizza Doggy's 2026-11-03, pack not recorded) does the same
  for the water (`beach_water_grain.png`).

## What's here

| File | Contents |
|---|---|
| `brick_wall_pt_2.png` | the 256×256 tile, RGBA, bricks about 24×10 px in a running bond |
| `asphalt_old_tr_1.png` | the 512×512 tile, RGBA (opaque), dark grey pitted surface, seamless |
| `small_stones_tr_1.png` | the 512×512 tile, RGBA (opaque), small dark grey stones, seamless |
| `grass_pt_3.png` | the 512×512 tile, RGBA (opaque), dark green winter grass, seamless |
| `dirt_pt_5.png` | the 512×512 tile, dark brown-grey dirt, seamless |
| `dirt_pt_10.png` | the 512×512 tile, dark brown rocky dirt, seamless |
| `water_2.png` | the 256×256 tile, soft teal water, seamless |
| `snow_tr_1.png` | the 512×512 tile, RGBA (opaque), wind-lined grey snow, seamless |
| `building_ceiling_pt_1.png` | the 512×512 tile, a rough grey panel in a pale green-grey frame |
| `LICENSE.pdf` | the agreement as downloaded |

## House rules

These are **source** files, not shipped assets. Nothing under `assets/` is edited by
hand: re-run the render tool after replacing the tile. The licence forbids shipping the
tile on its own — the rendered, darkened wall is a game asset inside the game only.
