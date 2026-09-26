"""Give the hoop a real gym rim: a finer round-rod ring, a one-piece neck
(tongue + two arms) welded to the ring and bolted to the board through a
flange, a breakaway spring housing under the neck, and 12 net hooks.

Real-rim numbers this follows (FIBA equipment rules / manufacturer specs):
ring inside diameter 450-459 mm, rod 16-20 mm ROUND solid steel, inside
back of the ring 151 mm from the board face, net attached in 12 places.

Idempotent: keeps the `Rim` object (it carries the Swish NLA keys) and only
swaps its mesh; removes the old `Bracket` and any prior Neck*/RimPlate/
SpringBox/NetHook* objects before recreating them. Never rebuilds anything
else — hand edits to the rest of hoop.blend are untouched.

Inside Blender (MCP / Text Editor), with hoop.blend open:
    exec(open("tools/blender/add_gym_rim.py").read()); apply(); export_glb()
Headless (saves the .blend and exports the .glb):
    Blender -b art/blender/hoop.blend --python tools/blender/add_gym_rim.py
"""
import math
import os
import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")) \
    if "__file__" in globals() else "/Users/rossgriffus/Documents/projects/godot/hoop_shoot"
GLB_PATH = os.path.join(ROOT, "assets", "hoops", "classic", "hoop.glb")

# Mirrors core/physics/sim_constants.gd + build_hoop.py (rim-centre origin,
# blender (x, y, z) = (sim x, -sim z, sim y)).
R_RIM = 0.2286
R_TUBE = 0.016
BOARD_OFF = 0.3796
NECK_HALF_W = 0.065      # 13 cm neck / flange width
NECK_LEN = BOARD_OFF - R_RIM   # 0.151 m: ring back -> board face
ARM_Z = 0.045            # the two neck arms sit at ±4.5 cm
ARM_SIZE = 0.012
TONGUE_T = 0.006
PLATE_W, PLATE_H, PLATE_T = 0.127, 0.10, 0.008
SPRING_BOX = (0.10, 0.09, 0.08)   # (x depth, y width, z height) in sim terms -> see below
HOOK_R = 0.011           # net hook loop radius
HOOK_TUBE = 0.003
HOOK_COUNT = 12

OWNED = ("Bracket", "NeckTongue", "NeckArm0", "NeckArm1", "SpringBox", "RimPlate")


def _mat(name, fallback_rgb):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        r, g, bb = [c / 255.0 for c in fallback_rgb]
        b.inputs["Base Color"].default_value = (r ** 2.2, g ** 2.2, bb ** 2.2, 1.0)
        b.inputs["Roughness"].default_value = 0.8
        m.diffuse_color = (r ** 2.2, g ** 2.2, bb ** 2.2, 1.0)
    return m


def _link(obj, coll, parent, location):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    coll.objects.link(obj)
    obj.parent = parent
    obj.location = Vector(location)
    return obj


def _box(name, size, center, mat, coll, parent):
    """size/center in BLENDER units (already converted), center relative to parent."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = o.data.name = name
    o.scale = Vector(size)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    _link(o, coll, parent, center)
    return o


def _fix_net_alpha():
    """Wire the net texture's Alpha straight into the shader. With a Math node in
    the alpha path the glTF exporter re-encodes the PNG (and Blender 5.2's
    re-encode filled the bottom row solid → a white ring under the net); with a
    direct link it embeds the original file bytes. Godot forces alpha-scissor on
    the net material at load (court_geometry.gd), so the mask look survives."""
    m = bpy.data.materials.get("Net")
    if m is None or not m.use_nodes:
        return
    nodes, links = m.node_tree.nodes, m.node_tree.links
    b = nodes.get("Principled BSDF")
    texs = [n for n in nodes if n.type == "TEX_IMAGE"]
    if b is None or not texs:
        return
    tex = texs[0]
    for l in list(links):
        if l.to_socket == b.inputs["Alpha"]:
            links.remove(l)
    for n in list(nodes):
        if n.type == "MATH":
            nodes.remove(n)
    links.new(tex.outputs["Alpha"], b.inputs["Alpha"])
    m.use_backface_culling = False
    print("NET ALPHA: direct link (exporter keeps the original PNG)")


def _remove_owned():
    for o in list(bpy.data.objects):
        if o.name in OWNED or o.name.startswith("NetHook"):
            me = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            if me is not None and me.users == 0:
                bpy.data.meshes.remove(me)


def apply():
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    coll = bpy.data.collections.get("Hoop") or bpy.context.scene.collection
    root = bpy.data.objects["HoopRoot"]
    pivot = bpy.data.objects["RimPivot"]
    rim = bpy.data.objects["Rim"]
    rim_mat = rim.data.materials[0] if rim.data.materials else _mat("Rim_Paint", (232, 92, 40))
    steel = _mat("Rim_Steel", (52, 54, 60))

    _remove_owned()
    _fix_net_alpha()

    # 0. The ring and net must sit exactly on the physics ring (the assembly
    #    origin is the sim's rim centre; the pivot is at the ring's back edge).
    #    Hand edits had drifted them 6.5 cm toward the board — realign x/y.
    net = bpy.data.objects.get("Net")
    for o in (rim, net):
        if o is not None and (abs(o.location.x + R_RIM) > 1e-4 or abs(o.location.y) > 1e-4):
            print("REALIGN %s from %s to (-R_RIM, 0)" % (o.name, tuple(round(v, 4) for v in o.location)))
            o.location.x, o.location.y = -R_RIM, 0.0
    bpy.context.scene.frame_set(1)   # rest pose (Swish keys are 0 at frame 1)

    # 1. Finer round-rod ring: swap the mesh, keep the object (and its Swish keys).
    bpy.ops.mesh.primitive_torus_add(major_radius=R_RIM, minor_radius=R_TUBE,
                                     major_segments=24, minor_segments=8, location=(0, 0, 0))
    tmp = bpy.context.active_object
    new_mesh = tmp.data
    new_mesh.name = "RimMesh"
    bpy.data.objects.remove(tmp, do_unlink=True)
    old_mesh = rim.data
    rim.data = new_mesh
    rim.data.materials.append(rim_mat)
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)

    # 2. One-piece neck under the pivot (pivot sits at the ring's back edge; the
    #    ring object is at (-R_RIM, 0, 0) under it). Blender x = sim x, y = -sim z,
    #    z = sim y. Ring back (centreline) is at pivot-local x = 0.
    #    Tongue: flat plate continuing the ring back, flush with the tube's top.
    tongue_len = NECK_LEN + R_TUBE
    _box("NeckTongue", (tongue_len, NECK_HALF_W * 2, TONGUE_T),
         (tongue_len / 2 - R_TUBE, 0, R_TUBE - TONGUE_T / 2), rim_mat, coll, pivot)
    #    Two arms under the tongue, from the ring back to the flange.
    for i, y in enumerate((-ARM_Z, ARM_Z)):
        _box("NeckArm%d" % i, (NECK_LEN, ARM_SIZE, ARM_SIZE),
             (NECK_LEN / 2, y, -ARM_SIZE / 2 - TONGUE_T / 2 + R_TUBE - TONGUE_T / 2), rim_mat, coll, pivot)
    #    Breakaway spring housing below the neck, just off the board.
    _box("SpringBox", (SPRING_BOX[0], SPRING_BOX[1], SPRING_BOX[2]),
         (NECK_LEN - SPRING_BOX[0] / 2 - 0.005, 0, -SPRING_BOX[2] / 2 - 0.02), steel, coll, pivot)

    # 3. Flange bolted to the board (static, under the root): centred on the
    #    neck, its face flush on the board face, 4 bolt nubs.
    plate_cx = BOARD_OFF - PLATE_T / 2
    _box("RimPlate", (PLATE_T, PLATE_W, PLATE_H), (plate_cx, 0, PLATE_H / 2 - 0.02), rim_mat, coll, root)
    for i, (y, z) in enumerate(((-0.045, 0.01), (0.045, 0.01), (-0.045, 0.06), (0.045, 0.06))):
        _box("RimPlateBolt%d" % i, (0.006, 0.012, 0.012), (BOARD_OFF - PLATE_T - 0.003, y, z), steel, coll, root)

    # 4. Twelve net hooks: small loops hanging under the ring, one every 30°.
    for i in range(HOOK_COUNT):
        ang = math.tau * i / HOOK_COUNT
        bpy.ops.mesh.primitive_torus_add(major_radius=HOOK_R, minor_radius=HOOK_TUBE,
                                         major_segments=8, minor_segments=4, location=(0, 0, 0))
        h = bpy.context.active_object
        h.name = h.data.name = "NetHook%02d" % i
        h.data.materials.append(rim_mat)
        # Loop plane vertical and tangent to the ring: rotate the torus (xy plane)
        # up about the radial axis, then spin it to the ring angle.
        h.rotation_euler = (math.pi / 2, 0.0, ang)
        x = -R_RIM + R_RIM * math.cos(ang)
        y = R_RIM * math.sin(ang)
        _link(h, coll, pivot, (x, y, -R_TUBE - HOOK_R + 0.002))

    # Flat shading + applied scale on the parts this script owns.
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        if o.name in OWNED or o.name.startswith("NetHook") or o.name.startswith("RimPlateBolt") or o.name == "Rim":
            if o.type == "MESH":
                o.select_set(True)
                bpy.context.view_layer.objects.active = o
                bpy.ops.object.shade_flat()
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.select_all(action="DESELECT")
    print("GYM RIM applied: ring 24x8, neck tongue + 2 arms, spring box, flange, %d hooks" % HOOK_COUNT)


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
    for o in bpy.data.objects:
        d = tuple(round(x, 3) for x in o.dimensions) if o.type == "MESH" else "-"
        print("OBJ %-14s parent=%-9s loc=%s dims=%s" % (
            o.name, o.parent.name if o.parent else "-", tuple(round(x, 3) for x in o.location), d))
