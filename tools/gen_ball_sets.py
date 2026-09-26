#!/usr/bin/env python3
"""Write every ball's .tres from the manifest, and print the registry lines.

  python3 tools/gen_ball_sets.py

Reads assets/balls/ball_manifest.json (written by
tools/aseprite/gen_ball_wrap.lua from its STYLES table, the single source of
truth for the roster) and writes assets/balls/<id>/ball_set.tres for each.

These are generated rather than hand-typed for a specific reason:
CosmeticLibrary.balls() filters with `if s is BallSet`, so a .tres that fails to
load yields null, fails that test, and is silently dropped -- no error, no
warning, the ball simply does not exist. Across twenty hand-authored resources
that is the likeliest failure and the hardest to spot.

Every ball shares the classic glb and the classic bounce clips; only `skin_path`
differs. Sharing another set's sfx is the established pattern -- see
assets/hoops/street/hoop_set.tres, which borrows the classic hoop's.
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
MANIFEST = os.path.join(ROOT, "assets", "balls", "ball_manifest.json")
MODEL = "res://assets/balls/classic/basketball.glb"
BOUNCE = ", ".join(
    '"res://assets/balls/classic/sfx/bounce_%02d.wav"' % i for i in range(1, 16))

TEMPLATE = '''[gd_resource type="Resource" script_class="BallSet" load_steps=2 format=3]

[ext_resource type="Script" path="res://game/cosmetics/ball_set.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{id}"
display_name = "{name}"
price_coins = {price}
model_path = "{model}"
skin_path = "{skin}"
bounce_clips = PackedStringArray({bounce})
'''


def main() -> None:
    with open(MANIFEST) as f:
        balls = json.load(f)
    seen = set()
    lines = []
    for b in balls:
        if b["id"] in seen:
            raise SystemExit("duplicate ball id: %s" % b["id"])
        seen.add(b["id"])
        # starter_ball() returns the FIRST set priced 0, and a test asserts that
        # is classic. A second free ball would silently steal it.
        if b["price"] == 0 and b["id"] != "classic":
            raise SystemExit("%s is priced 0; only classic may be" % b["id"])
        skin = os.path.join(ROOT, b["skin"][len("res://"):])
        if not os.path.exists(skin):
            raise SystemExit("%s: missing skin %s" % (b["id"], b["skin"]))
        folder = os.path.join(ROOT, "assets", "balls", b["id"])
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "ball_set.tres"), "w") as f:
            f.write(TEMPLATE.format(id=b["id"], name=b["name"], price=b["price"],
                                    model=MODEL, skin=b["skin"], bounce=BOUNCE))
        lines.append('\t"res://assets/balls/%s/ball_set.tres",' % b["id"])
    print("wrote %d ball sets" % len(balls))
    print("\n--- paste into CosmeticLibrary.BALLS ---")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
