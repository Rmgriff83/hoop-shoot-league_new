"""Swap the street hoop's board texture in the live file and re-export, keeping
its hand-keyed Miss clip (build_street_hoop.py -- --force would lose it).

  /Applications/Blender.app/Contents/MacOS/Blender -b art/blender/street_hoop.blend \
      --python tools/blender/reskin_street_hoop.py
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import add_swish_anim  # noqa: E402  (export_glb: the settings that keep the clip)

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
FACE_TEX = os.path.join(ROOT, "assets", "textures", "street_board_grain.png")
GLB_PATH = os.path.join(ROOT, "assets", "hoops", "street", "hoop.glb")

if __name__ == "__main__" and bpy.app.background:
    node = next(n for n in bpy.data.materials["Street_Face"].node_tree.nodes if n.type == "TEX_IMAGE")
    old = node.image
    node.image = bpy.data.images.load(FACE_TEX)
    if old is not None and old.users == 0:
        bpy.data.images.remove(old)
    bpy.ops.wm.save_mainfile()
    add_swish_anim.export_glb(GLB_PATH)
