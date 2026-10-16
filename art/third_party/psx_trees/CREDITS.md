# PSX Trees v1.0 — DanglingBat

- **Source:** https://danglingbat.itch.io/ ("psx-trees_v1.0", DanglingBat; the pack's own page is
  under that account — Ross supplied the zip and the licence on 2026-10-14)
- **Licence:** DanglingBat's Game Assets CC License Agreement (`LICENSE.rtf` / `LICENSE.txt`
  beside this file): use in any game, commercial or not; edit freely; **never** resell,
  redistribute or share the assets on their own (edited or not), never bundle them in packs or
  templates, never use them for AI creation. Attribution appreciated, not required —
  credited in `data/credits.json` (the in-game credits screen).
- **Pulled:** 2026-10-14
- **Used for:** the park's trees, stumps, rocks and fallen log
  (`tools/blender/conform_psx_trees.py` strips each model to its albedo and exports
  `assets/arena/park/trees/<id>.glb`; `game/view/park_fx.gd` instances them from
  `data/park_layout.json`).

## What's here

| File | Contents |
|---|---|
| `models/aspen_tree_01/02.glb` | two leafy aspens, ~2.5K tris, one alpha-cut surface, 512² textures |
| `models/pine_tree_01_a/b/c.glb` | three pines, ~1.2K tris, bark + alpha-cut branch surfaces |
| `models/pine_tree_stump_01.glb`, `pine_tree_trunk_01.glb`, `fallen_pine_tree_01.glb` | litter |
| `models/dead_branch_01/02.glb` | deadfall |
| `models/rock_01_large/small(_mossy).glb` | four rocks |
| `previews/` (not vendored) | the pack's preview renders |

The glbs embed PBR sets (base colour, normal, roughness…); only the base colour ships.

## House rules

These are **source** files, not shipped assets. Nothing under `assets/` is edited by hand:
re-run the conform script after replacing a model. The licence forbids shipping the pack on
its own — the conformed copies are game assets inside the game only.
