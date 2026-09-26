"""Add the "Miss" rim reaction to a hoop: a short authored twitch of `RimPivot`
(the rim's mount hinge) played by the game whenever the ball hits the rim.
Subtle on purpose, and different per hoop:

  classic (arcade, has LedFace): a tight twang — the front dips 2.5°, overshoots
                                 back, settles in 0.45 s, with a hair of roll.
  street (beach):                a looser sag — dips 1.8°, slower recoil over
                                 0.6 s, with a small lateral wag.

Idempotent: re-running removes the previous Miss track/action first. Never
touches geometry or the other clips (the classic's Swish is left alone).

Headless (saves the .blend and exports the .glb):
    Blender -b art/blender/hoop.blend        --python tools/blender/add_miss_anim.py
    Blender -b art/blender/street_hoop.blend --python tools/blender/add_miss_anim.py
Inside Blender (MCP / Text Editor), with the hoop file open:
    exec(open("tools/blender/add_miss_anim.py").read()); apply(); export_glb()
"""
import math
import os
import sys
import bpy

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else \
    "/Users/rossgriffus/Documents/projects/godot/hoop_shoot/tools/blender"
sys.path.insert(0, HERE)
import add_gym_rim as gym  # noqa: E402  (export_glb with the hoop's exporter settings)

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
FPS = 30
TRACK = "Miss"

# (time s, pitch deg [about blender Y: front of the rim dips], roll deg [about X], yaw deg [about Z])
# Stiff arcade rim: a smaller, quicker dip that dies out fast.
CLASSIC = [
    (0.00, 0.0, 0.0, 0.0),
    (0.04, 1.6, 0.5, 0.0),
    (0.11, -0.6, -0.2, 0.0),
    (0.19, 0.2, 0.05, 0.0),
    (0.30, 0.0, 0.0, 0.0),
]
STREET = [
    (0.00, 0.0, 0.0, 0.0),
    (0.07, 1.8, 0.0, 0.6),
    (0.22, -0.6, 0.0, -0.6),
    (0.40, 0.2, 0.0, 0.2),
    (0.60, 0.0, 0.0, 0.0),
]


def _style():
    return "classic" if bpy.data.objects.get("LedFace") else "street"


def _glb_path():
    if _style() == "classic":
        return os.path.join(ROOT, "assets", "hoops", "classic", "hoop.glb")
    return os.path.join(ROOT, "assets", "hoops", "street", "hoop.glb")


def _clear(pivot):
    if pivot.animation_data is not None:
        for tr in list(pivot.animation_data.nla_tracks):
            if tr.name == TRACK:
                pivot.animation_data.nla_tracks.remove(tr)
        pivot.animation_data.action = None
    for a in list(bpy.data.actions):
        if a.name == TRACK or a.name.startswith(TRACK + "."):
            bpy.data.actions.remove(a)


def _to_nla(obj, action):
    ad = obj.animation_data
    track = ad.nla_tracks.new()
    track.name = TRACK
    strip = track.strips.new(TRACK, 1, action)
    try:  # Blender 4.4+ slotted actions
        if hasattr(strip, "action_slot") and len(action.slots):
            strip.action_slot = action.slots[0]
    except Exception:
        pass
    ad.action = None


def apply():
    pivot = bpy.data.objects["RimPivot"]
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    _clear(pivot)
    keys = CLASSIC if _style() == "classic" else STREET
    pivot.rotation_mode = "XYZ"
    base = tuple(pivot.rotation_euler)
    for t, pitch, roll, yaw in keys:
        f = 1 + int(round(t * FPS))
        pivot.rotation_euler = (base[0] + math.radians(roll), base[1] + math.radians(pitch), base[2] + math.radians(yaw))
        pivot.keyframe_insert("rotation_euler", frame=f)
    pivot.rotation_euler = base
    pivot.animation_data.action.name = TRACK
    _to_nla(pivot, pivot.animation_data.action)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_set(1)
    print("MISS added (%s): %d keys over %.2f s on RimPivot" % (_style(), len(keys), keys[-1][0]))


def export_glb(path=None):
    gym.export_glb(path or _glb_path())


if __name__ == "__main__" and bpy.app.background:
    apply()
    bpy.ops.wm.save_mainfile()
    export_glb()
