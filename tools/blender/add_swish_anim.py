"""Add the "Swish" animation to the hoop: net shape keys (Grab / SnapUp / Back)
that reshape the net the way a backspin swish does — the ball drags the net down
and forward, then the front cords snap UP into the rim interior while the back
flares out, then it recoils and settles — plus a small rim bounce, both in NLA
tracks named "Swish" so the glTF exporter merges them into ONE animation.

Idempotent: re-running removes the previous Swish keys/tracks first, so it is
safe after hand edits to the model. Never rebuilds geometry.

Inside Blender (MCP / Text Editor), with hoop.blend open:
    exec(open("tools/blender/add_swish_anim.py").read()); apply(); export_glb()
Headless (saves the .blend and exports the .glb):
    Blender -b art/blender/hoop.blend --python tools/blender/add_swish_anim.py
"""
import math
import os
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")) \
    if "__file__" in globals() else "/Users/rossgriffus/Documents/projects/godot/hoop_shoot"
GLB_PATH = os.path.join(ROOT, "assets", "hoops", "classic", "hoop.glb")

FPS = 30
LENGTH_S = 0.9
# (time s, Grab, SnapUp, Back, rim z (m), rim tilt x (deg))
KEYS = [
    (0.00, 0.0,  0.0,  0.0,   0.000,  0.0),
    (0.06, 1.0,  0.0,  0.0,  -0.020,  1.5),   # ball drags the net down/forward
    (0.18, 0.15, 1.0,  0.0,   0.012, -1.0),   # front cords rip up into the rim
    (0.32, 0.0,  0.35, 1.0,  -0.006,  0.5),   # recoil: front drops, back sways in
    (0.46, 0.0,  0.5,  0.0,   0.000,  0.0),   # second, smaller snap
    (0.60, 0.0,  0.1,  0.5,   0.000,  0.0),
    (0.74, 0.0,  0.15, 0.0,   0.000,  0.0),
    (0.90, 0.0,  0.0,  0.0,   0.000,  0.0),
]
SHAPE_NAMES = ("Grab", "SnapUp", "Back")


def _weight_fn(net):
    """0 at the top row of the net → 1 at the bottom, eased so the bottom moves most."""
    zs = [v.co.z for v in net.data.vertices]
    zmin, zmax = min(zs), max(zs)
    span = max(zmax - zmin, 1e-9)

    def w(co):
        t = (zmax - co.z) / span
        return t * t
    return w


def _clear(net, rim):
    sk = net.data.shape_keys
    if sk is not None:
        if sk.animation_data is not None:
            for tr in list(sk.animation_data.nla_tracks):
                if tr.name == "Swish":
                    sk.animation_data.nla_tracks.remove(tr)
            sk.animation_data.action = None
        # The script owns every key on the net: drop all but Basis (also clears
        # renamed leftovers like "Back.001" from earlier runs).
        for kb in [k for k in sk.key_blocks if k.name != "Basis"]:
            net.shape_key_remove(kb)
    if rim.animation_data is not None:
        for tr in list(rim.animation_data.nla_tracks):
            if tr.name == "Swish":
                rim.animation_data.nla_tracks.remove(tr)
        rim.animation_data.action = None
    for a in list(bpy.data.actions):
        if a.name.startswith("Swish"):
            bpy.data.actions.remove(a)


def _add_shape_keys(net):
    """Three keys built from two weights per vertex: k (0 at the top ring → 1 at
    the bottom, eased) and where the vertex sits around the net — front = the
    shooter's side (local −x), back = toward the board (+x)."""
    if net.data.shape_keys is None:
        net.shape_key_add(name="Basis", from_mix=False)
    basis = net.data.shape_keys.key_blocks["Basis"]
    w = _weight_fn(net)
    keys = {}
    for name in SHAPE_NAMES:
        kb = net.shape_key_add(name=name, from_mix=False)
        for i, bv in enumerate(basis.data):
            co = bv.co.copy()
            k = w(co)
            r = math.hypot(co.x, co.y)
            front = max(0.0, -co.x / r) if r > 1e-9 else 0.0   # 1 at the shooter side
            back = max(0.0, co.x / r) if r > 1e-9 else 0.0     # 1 at the board side
            if name == "Grab":
                # Ball passing through: everything stretched down, pushed toward the
                # board, the front cords dragged down hardest by the backspin.
                co.z -= (0.07 + 0.04 * front) * k
                co.x += 0.05 * k
            elif name == "SnapUp":
                # The payoff: front cords whip UP and IN toward the rim interior
                # (bottom-front rises ~30 cm, past rim height), the back flares out
                # and hangs low, the sides twist between.
                up = 0.30 * k * front
                pull_in = 1.0 - 0.65 * k * front
                flare = 1.0 + 0.35 * k * back
                co.x *= pull_in * flare
                co.y *= pull_in * flare
                co.z += up - 0.03 * k * back
            else:  # Back — recoil: front drops below rest and swings out, back comes in/up
                dip = 0.06 * k * front
                out = 1.0 + 0.2 * k * front
                tuck = 1.0 - 0.15 * k * back
                co.x *= out * tuck
                co.y *= out * tuck
                co.z += -dip + 0.04 * k * back
            kb.data[i].co = co
        kb.value = 0.0
        keys[name] = kb
    return keys


def _to_nla(id_data, action, track_name="Swish"):
    ad = id_data.animation_data
    track = ad.nla_tracks.new()
    track.name = track_name
    strip = track.strips.new(track_name, 1, action)
    try:  # Blender 4.4+ slotted actions
        if hasattr(strip, "action_slot") and len(action.slots):
            strip.action_slot = action.slots[0]
    except Exception:
        pass
    ad.action = None


def apply():
    net = bpy.data.objects["Net"]
    rim = bpy.data.objects["Rim"]
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start = 1
    scene.frame_end = 1 + int(round(LENGTH_S * FPS))
    _clear(net, rim)
    keys = _add_shape_keys(net)

    # Keyframe the shape-key values (action lives on the Key datablock).
    sk = net.data.shape_keys
    for (t, grab, snap, back, _rz, _rx) in KEYS:
        f = 1 + int(round(t * FPS))
        for name, val in (("Grab", grab), ("SnapUp", snap), ("Back", back)):
            keys[name].value = val
            keys[name].keyframe_insert("value", frame=f)
    sk.animation_data.action.name = "SwishKeys"
    _to_nla(sk, sk.animation_data.action)

    # Rim bounce: local z dip with overshoot + a tiny tilt. RimPivot stays free
    # for the game's physics-driven wobble.
    base_loc = rim.location.copy()
    base_rot = rim.rotation_euler.copy()
    for (t, _g, _s, _b, rz, rx) in KEYS:
        f = 1 + int(round(t * FPS))
        rim.location = (base_loc.x, base_loc.y, base_loc.z + rz)
        rim.rotation_euler = (base_rot.x + math.radians(rx), base_rot.y, base_rot.z)
        rim.keyframe_insert("location", index=2, frame=f)
        rim.keyframe_insert("rotation_euler", index=0, frame=f)
    rim.location = base_loc
    rim.rotation_euler = base_rot
    rim.animation_data.action.name = "SwishRim"
    _to_nla(rim, rim.animation_data.action)
    for kb in keys.values():
        kb.value = 0.0
    scene.frame_set(1)
    print("SWISH added: shape keys", list(keys), "frames 1..%d @ %d fps" % (scene.frame_end, FPS))


def export_glb(path=GLB_PATH):
    coll = bpy.data.collections.get("Hoop")
    objs = list(coll.objects) if coll else [o for o in bpy.data.objects if o.name not in ("Camera", "Light")]
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_materials="EXPORT", export_image_format="AUTO",
        export_animations=True, export_animation_mode="NLA_TRACKS",
        export_morph=True, export_morph_animation=True, export_force_sampling=True,
    )
    bpy.ops.object.select_all(action="DESELECT")
    print("EXPORTED", path, os.path.getsize(path), "bytes")


if __name__ == "__main__" and bpy.app.background:
    apply()
    bpy.ops.wm.save_mainfile()
    export_glb()
