#!/usr/bin/env python3
"""The park's tree and litter placement (docs/BLENDER_101.md → The park): the
design's seeded layout ("Park Area Concept": aspens carry the avenue rows,
pines fill the gaps, the big trees right, the left group past the path, the
trees behind the camera, the tall aspen leaning in over the board, two
stumps, a mossy rock and the fallen pine along the lot) ported once into
data/park_layout.json, which game/view/park_fx.gd instances at runtime.

    python3 tools/gen_park_layout.py

Deterministic (the design's 16807 LCG, seed 7): the same file every run. Sim
metres: x toward the hoop, z the shooter's right, y up.
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "data", "park_layout.json")

_seed = 7


def rng():
    global _seed
    _seed = (_seed * 16807) % 2147483647
    return _seed / 2147483647


def R(a, b):
    return a + rng() * (b - a)


LISTS = ["aspen_tree_01", "aspen_tree_02", "aspen_tree_01", "aspen_tree_02", "pine_tree_01_a", "pine_tree_01_b", "pine_tree_01_c"]
rows = []


def T(x, z, s=1.0, k=None):
    model = LISTS[k] if k is not None else LISTS[int(rng() * len(LISTS))]
    rows.append({"model": model, "x": round(x, 3), "y": 0.0, "z": round(z, 3), "s": round(s * R(0.9, 1.15), 3), "ry": round(R(0, 6.28), 3)})


# the row along the far side of the lot
z = -34.0
while z <= 16.0:
    T(25.5 + R(-1, 1.5), z, 1.25)
    z += R(4.5, 6.5)
# the avenue down the road
x = 29.0
while x <= 60.0:
    T(x, -19.6 + R(-0.6, 0.6), 1.1)
    T(x + 2.5, -10.4 + R(-0.6, 0.6), 1.1)
    x += R(5, 7)
# the big trees right
for x, z, s, k in [(12.5, 9.5, 1.45, 0), (17.5, 14.5, 1.3, 1), (11, 17, 1.2, 5), (23, 19, 1.3, 0), (8.5, 13, 1.1, 4)]:
    T(x, z, s, k)
# left, past the path
for x, z, s, k in [(16.5, -26, 1.3, 1), (8, -27, 1.2, 0), (21, -32, 1.1, 6), (3, -22, 1.25, 4)]:
    T(x, z, s, k)
# Nothing behind the camera: the shooter never turns round, so the design's
# three trees back there and the one far left past the path (-4, -24) were
# never in any spot's view cone (checked 2026-10-16) and are left out.
# the tree from the photo: a tall aspen just off-frame left, leaning in over the board
rows.append({"model": "aspen_tree_01", "x": 4.6, "y": 0.0, "z": -5.4, "s": 1.3, "ry": 2.4, "rx": 0.12})
rows.append({"model": "pine_tree_01_a", "x": 34.0, "y": 0.0, "z": -31.0, "s": 0.9, "ry": 0.4})
rows.append({"model": "pine_tree_01_b", "x": 39.0, "y": 0.0, "z": -27.0, "s": 1.0, "ry": 1.2})
# ground litter, kept minimal: two stumps, one big mossy rock, one log along the lot
rows.append({"model": "pine_tree_stump_01", "x": 8.2, "y": -0.04, "z": -6.5, "s": 1.05, "ry": 0.4})
rows.append({"model": "pine_tree_stump_01", "x": 11.8, "y": -0.06, "z": 12.2, "s": 0.95, "ry": 2.2})
rows.append({"model": "rock_01_large_mossy", "x": 10.2, "y": -0.06, "z": 6.6, "s": 1.5, "sy": 1.1, "ry": 0.7})
rows.append({"model": "fallen_pine_tree_01", "x": 13.5, "y": 0.0, "z": -13.6, "s": 1.15, "ry": 0.03})

# The far aspens (2026-10-16, the park running lighter): aspen_tree_01 is
# 2562 triangles and was two thirds of every instanced triangle; the six on
# the avenue at x >= 29 m become aspen_tree_02 (945) scaled by their height
# ratio (9.9 / 5.7) so the tree line keeps its silhouette and density at
# 30-55 m, where the shape difference does not read. The seven nearer ones
# stay the big aspen.
FAR_ASPEN_X = 29.0
ASPEN_HEIGHT_RATIO = 1.74
for r in rows:
    if r["model"] == "aspen_tree_01" and r["x"] >= FAR_ASPEN_X:
        r["model"] = "aspen_tree_02"
        r["s"] = round(r["s"] * ASPEN_HEIGHT_RATIO, 3)

doc = {"generated_by": "tools/gen_park_layout.py", "seed": 7, "rows": rows}
with open(OUT, "w") as f:
    json.dump(doc, f, indent=1)
    f.write("\n")
trees = sum(1 for r in rows if "tree_0" in r["model"] and "stump" not in r["model"] and "fallen" not in r["model"])
print("park layout: %d rows, %d trees -> %s" % (len(rows), trees, OUT))
