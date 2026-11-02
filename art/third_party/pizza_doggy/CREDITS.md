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
  boot splash from it).

## What's here

| File | Contents |
|---|---|
| `brick_wall_pt_2.png` | the 256×256 tile, RGBA, bricks about 24×10 px in a running bond |
| `LICENSE.pdf` | the agreement as downloaded |

## House rules

These are **source** files, not shipped assets. Nothing under `assets/` is edited by
hand: re-run the render tool after replacing the tile. The licence forbids shipping the
tile on its own — the rendered, darkened wall is a game asset inside the game only.
