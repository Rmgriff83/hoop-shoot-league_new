# Low Poly Buildings Pack — Sam Grady

- **Source:** https://samgrady.itch.io/low-poly-buildings-pack ("low-poly buildings pack", SamGrady)
- **Licence:** Creative Commons Attribution 4.0 International (CC BY 4.0) — credit "Sam Grady"
  (the author's note: "you can use it in your game. Just make sure to credit me in the credits").
  Credited in `data/credits.json` (the in-game credits screen).
- **Pulled:** 2026-09-27
- **Used for:** the buildings around the city court (`tools/blender/build_city.py`
  imports the OBJs into `assets/arena/city/city.glb`).

## What's here

| File | Contents |
|---|---|
| `building_01..11_smooth.obj` | CopperCube exports, Y-up, metres at city-block scale, one `mat0` each, v in −1..0 |
| `diffuse_.jpg` | the shared 256×256 photo facade atlas (pure blue = unused padding) |
| `alpha_.jpg` | a cut-out mask for the railing region only (not used) |

## House rules

These are **source** files, not shipped assets. `tools/aseprite/conform_buildings.lua`
turns the atlas into `assets/textures/city_facades.png` (+ the derived window mask
the window maps were retired 2026-10-01); nothing under `assets/` is edited by hand.
