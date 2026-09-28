"""Build the chain-net hoop for the city court: the street hoop's regulation
1.83 x 1.05 m board as white perforated steel with a red target, the gym rim,
and a NET of steel links — the same tapered 12-strand lattice as the nylon
net (NetSim reads its vertices) but one ring taller and skinned with
hoop_chain.png, so it reads as chain and the sim's chain feel
(SimGeometry.city(): CHAIN_NET_DRAG / CHAIN_NET_WALL_E) has a body to match.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_chain_hoop.py

Produces  art/blender/chain_hoop.blend  (source, ignored by Godot) and
          assets/hoops/chain/hoop.glb   (game export, Y-up, transforms applied).

Same conventions as build_street_hoop.py: origin is the RIM CENTRE, blender
(x, y, z) = (sim x, -sim z, sim y); add_gym_rim.apply() adds the neck,
spring box, flange and hooks and wires the net alpha for the exporter.

CREATOR script: refuses to overwrite an existing chain_hoop.blend unless run
with `-- --force`. Never touches the other hoops.
"""
import math
import os
import sys
import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_hoop as bh          # noqa: E402
import add_gym_rim as gym        # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "chain_hoop.blend")
GLB_PATH = os.path.join(ROOT, "assets", "hoops", "chain", "hoop.glb")
TEX = lambda name: os.path.join(ROOT, "assets", "textures", name)

R_RIM = bh.R_RIM
R_TUBE = bh.R_TUBE
BOARD_OFF = bh.BOARD_OFF
BOARD_BOTTOM = -0.15
BOARD_TOP = 0.90
BOARD_HALF_W = 0.915
BOARD_THICK = 0.05
NET_BOTTOM_R = bh.NET_BOTTOM_R
NET_HEIGHT = bh.NET_HEIGHT
NET_RINGS = 4                  # vertical cuts: 5 rings of links
POLE_X = BOARD_OFF + 0.3
ARM_Y = 0.35


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    coll = bpy.data.collections.new("Hoop")
    bpy.context.scene.collection.children.link(coll)

    root = bpy.data.objects.new("HoopRoot", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.15
    bh.link_obj(root, coll)

    body = bh.mat_flat("Chain_Body", (200, 204, 210), roughness=0.5)
    face = bh.mat_tex("Chain_Face", TEX("city_board.png"))
    metal = bh.mat_flat("Chain_Metal", (54, 58, 66))
    rim_mat = bh.mat_tex("Rim", TEX("hoop_rim.png"))
    net_mat = bh.mat_tex("Net", TEX("hoop_chain.png"), alpha_clip=True, double_sided=True)

    h = BOARD_TOP - BOARD_BOTTOM
    board = bh.add_box("Backboard", (BOARD_THICK, BOARD_HALF_W * 2, h),
                       (BOARD_OFF + BOARD_THICK / 2, 0, (BOARD_TOP + BOARD_BOTTOM) / 2), body, coll, root)
    board.data.materials.append(face)
    bm = bmesh.new()
    bm.from_mesh(board.data)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        if f.normal.x < -0.5:
            f.material_index = 1
            for loop in f.loops:
                y, z = loop.vert.co.y, loop.vert.co.z
                loop[uv].uv = ((BOARD_HALF_W - y) / (2 * BOARD_HALF_W), (z + h / 2) / h)
    bm.to_mesh(board.data)
    bm.free()

    bh.add_box("BoardArm", (0.25, 0.10, 0.06), (BOARD_OFF + BOARD_THICK + 0.125, 0, ARM_Y), metal, coll, root)
    bh.add_box("BoardYoke", (0.06, 0.14, 0.70), (POLE_X - 0.08, 0, ARM_Y), metal, coll, root)
    # A steel strap across the board's back and a brace up to the arm.
    bh.add_box("BoardStrap", (0.02, BOARD_HALF_W * 2 - 0.1, 0.08), (BOARD_OFF + BOARD_THICK + 0.01, 0, ARM_Y), metal, coll, root)

    pivot = bpy.data.objects.new("RimPivot", None)
    pivot.empty_display_type = "SPHERE"
    pivot.empty_display_size = 0.05
    bh.link_obj(pivot, coll, root, (R_RIM, 0, 0))

    bpy.ops.mesh.primitive_torus_add(major_radius=R_RIM, minor_radius=R_TUBE,
                                     major_segments=20, minor_segments=6, location=(0, 0, 0))
    rim = bpy.context.active_object
    rim.name = rim.data.name = "Rim"
    rim.data.materials.append(rim_mat)
    bh.link_obj(rim, coll, pivot, (-R_RIM, 0, 0))

    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=R_RIM, depth=NET_HEIGHT,
                                        end_fill_type="NOTHING", location=(0, 0, 0))
    net = bpy.context.active_object
    net.name = net.data.name = "Net"
    bm = bmesh.new()
    bm.from_mesh(net.data)
    vertical = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 1e-6]
    bmesh.ops.subdivide_edges(bm, edges=vertical, cuts=NET_RINGS, use_grid_fill=True)
    for v in bm.verts:
        t = (NET_HEIGHT / 2 - v.co.z) / NET_HEIGHT
        r = R_RIM + (NET_BOTTOM_R - R_RIM) * t
        ang = math.atan2(v.co.y, v.co.x)
        v.co.x, v.co.y = r * math.cos(ang), r * math.sin(ang)
    uvl = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for loop in f.loops:
            u, vv = loop[uvl].uv
            loop[uvl].uv = (u * 3.0, vv)
    bm.to_mesh(net.data)
    bm.free()
    net.data.materials.append(net_mat)
    bh.link_obj(net, coll, pivot, (-R_RIM, 0, -NET_HEIGHT / 2))

    meshes = [o for o in coll.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.shade_flat()
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.select_all(action="DESELECT")
    return coll


if __name__ == "__main__" and bpy.app.background:
    if os.path.exists(BLEND_PATH) and "--force" not in sys.argv:
        print("REFUSING: %s exists (hand edits live there). Re-run with `-- --force` to rebuild." % BLEND_PATH)
        sys.exit(0)
    c = build()
    gym.apply()
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    gym.export_glb(GLB_PATH)
    for o in c.objects:
        d = tuple(round(x, 3) for x in o.dimensions) if o.type == "MESH" else "-"
        print("OBJ %-14s parent=%-9s loc=%s dims=%s" % (
            o.name, o.parent.name if o.parent else "-", tuple(round(x, 3) for x in o.location), d))
    print("SAVED", BLEND_PATH)
