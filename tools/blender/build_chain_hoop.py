"""Build the chain-net hoop for the city court, after Ross's references
(2026-09-27; white board 2026-09-30): a slightly dirty WHITE board, the regulation 1.83 x 1.05 m
rectangle with its two lower corners chamfered 45 deg over 0.22 m, a riveted
rolled edge, a bare steel gym rim (add_gym_rim's neck, flange, spring box and
12 hooks), a net of chain links — a diamond lattice of 12 chains NetSim
drives and renders as a multimesh of real links (net_sim.gd set_chain),
open at the bottom — and a
GOOSENECK pole: one bent steel tube from the ground on the sim's pole line
(board face + 0.3 m) up and over to a bolted mount on the board's back. The
arena builds no pole for the city; this hoop brings its own.

The sim keeps the rectangle collider (SimGeometry.city(): board 1.83 x 1.05,
a straight pole cylinder r 0.06): the chamfer is 0.22 m at the far bottom
corners, where a ball is a wide miss, and the tube above the bend is out of
any ball's way.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_chain_hoop.py

Produces  art/blender/chain_hoop.blend  (source, ignored by Godot) and
          assets/hoops/chain/hoop.glb   (game export, Y-up, transforms applied).

Same conventions as build_street_hoop.py: origin is the RIM CENTRE, blender
(x, y, z) = (sim x, -sim z, sim y). CREATOR script: refuses to overwrite an
existing chain_hoop.blend unless run with `-- --force`.
"""
import math
import os
import sys
import bmesh
import bpy
from mathutils import Vector

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
BOARD_THICK = 0.04
CHAMFER = 0.22
FRAME = 0.05
NET_BOTTOM_R = bh.NET_BOTTOM_R
NET_HEIGHT = bh.NET_HEIGHT
NET_RINGS = 4
POLE_X = BOARD_OFF + 0.3       # the sim's pole line (SimGeometry pole_off)
POLE_R = 0.06                  # SimGeometry.city() pole_r
GROUND = -2.44                 # the floor, in rim-centre space (rim 8 ft up)
MOUNT_X = BOARD_OFF + BOARD_THICK + 0.02   # the board's back, where the tube lands
MOUNT_Z = BOARD_BOTTOM + (BOARD_TOP - BOARD_BOTTOM) * 0.62
BEND_R = POLE_X - MOUNT_X       # the bend spans exactly pole line -> board back (0.24 m)
NECK_Z = MOUNT_Z - BEND_R       # where the vertical run starts to bend


def _tube(name, points, radius, mat, coll, parent, sides=12):
    """A tube swept along a polyline (blender coords): rings of `sides` verts
    at every point, quads between them, caps at both ends."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(points):
        prev_p = points[max(i - 1, 0)]
        next_p = points[min(i + 1, len(points) - 1)]
        tangent = (Vector(next_p) - Vector(prev_p)).normalized()
        up = Vector((0, 1, 0)) if abs(tangent.y) < 0.9 else Vector((1, 0, 0))
        a = tangent.cross(up).normalized()
        b = tangent.cross(a).normalized()
        ring = []
        for k in range(sides):
            ang = math.tau * k / sides
            ring.append(bm.verts.new(Vector(p) + a * (radius * math.cos(ang)) + b * (radius * math.sin(ang))))
        rings.append(ring)
    uvl = bm.loops.layers.uv.verify()
    for i in range(len(rings) - 1):
        for k in range(sides):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
            for loop, uv in zip(f.loops, ((k / sides, i * 0.3), ((k + 1) / sides, i * 0.3), ((k + 1) / sides, (i + 1) * 0.3), (k / sides, (i + 1) * 0.3))):
                loop[uvl].uv = uv
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    bh.link_obj(obj, coll, parent, (0, 0, 0))
    return obj


def _board(coll, parent, body, face, edge):
    """The chamfered steel board: an extruded outline, its front face
    UV-mapped over city_board.png in board space."""
    h = BOARD_TOP - BOARD_BOTTOM
    w = BOARD_HALF_W
    # outline in the board's plane: (y lateral, z up), counter-clockwise seen from the shooter (-x)
    outline = [(-w, BOARD_BOTTOM + CHAMFER), (-w + CHAMFER, BOARD_BOTTOM), (w - CHAMFER, BOARD_BOTTOM),
               (w, BOARD_BOTTOM + CHAMFER), (w, BOARD_TOP), (-w, BOARD_TOP)]
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.verify()
    front = [bm.verts.new((BOARD_OFF, y, z)) for (y, z) in outline]
    back = [bm.verts.new((BOARD_OFF + BOARD_THICK, y, z)) for (y, z) in outline]
    ff = bm.faces.new(tuple(reversed(front)))          # normal toward -x (the shooter)
    fb = bm.faces.new(tuple(back))
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        bm.faces.new((front[i], back[i], back[j], front[j]))
    bm.normal_update()
    for f in bm.faces:
        if f.normal.x < -0.5:
            f.material_index = 1
            for loop in f.loops:
                y, z = loop.vert.co.y, loop.vert.co.z
                loop[uvl].uv = ((w - y) / (2 * w), (z - BOARD_BOTTOM) / h)
        else:
            f.material_index = 0
            for loop in f.loops:
                loop[uvl].uv = (loop.vert.co.y * 2.0, loop.vert.co.z * 2.0)
    me = bpy.data.meshes.new("Backboard")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(body)
    me.materials.append(face)
    obj = bpy.data.objects.new("Backboard", me)
    bh.link_obj(obj, coll, parent, (0, 0, 0))
    # The rolled edge: thin steel boxes along the top and the two sides.
    t = 0.012
    bh.add_box("EdgeTop", (BOARD_THICK + 0.02, 2 * w + 0.02, t), (BOARD_OFF + BOARD_THICK / 2, 0, BOARD_TOP), edge, coll, parent)
    for s in (-1, 1):
        bh.add_box("EdgeSide%d" % (s + 1), (BOARD_THICK + 0.02, t, h - CHAMFER + 0.02),
                   (BOARD_OFF + BOARD_THICK / 2, s * w, (BOARD_TOP + BOARD_BOTTOM + CHAMFER) / 2), edge, coll, parent)
    return obj


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    coll = bpy.data.collections.new("Hoop")
    bpy.context.scene.collection.children.link(coll)

    root = bpy.data.objects.new("HoopRoot", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.15
    bh.link_obj(root, coll)

    body = bh.mat_flat("Chain_Body", (62, 68, 80), roughness=0.7)   # the board's sides: dark slate like the frame
    face = bh.mat_tex("Chain_Face", TEX("city_board.png"))
    steel = bh.mat_tex("Chain_Steel", TEX("city_steel.png"))
    edge = bh.mat_tex("Chain_Edge", TEX("city_edge.png"))   # the board's dark slate rolled edge
    bolt = bh.mat_flat("Chain_Bolt", (90, 94, 104), roughness=0.5)
    rim_mat = bh.mat_tex("Rim", TEX("hoop_rim_steel.png"))
    net_mat = bh.mat_tex("Net", TEX("hoop_chain.png"), alpha_clip=True, double_sided=True)

    _board(coll, root, body, face, edge)

    # The gooseneck: up from the ground on the pole line, a bend forward, and
    # a short run to a bolted mount plate on the board's back.
    # A quarter circle from the top of the vertical run, curling forward (-x)
    # so the tube arrives horizontal at the board's back, then the mount.
    pts = [(POLE_X, 0.0, GROUND), (POLE_X, 0.0, NECK_Z)]
    cx, cz = POLE_X - BEND_R, NECK_Z            # the bend's centre
    for k in range(1, 9):
        a = math.pi / 2 * k / 8                  # 0 = at the pole, pi/2 = above the centre, heading -x
        pts.append((cx + BEND_R * math.cos(a), 0.0, cz + BEND_R * math.sin(a)))
    mount = (MOUNT_X, 0.0, MOUNT_Z)
    pts.append((mount[0] - 0.02, 0.0, MOUNT_Z))
    _tube("Gooseneck", pts, POLE_R, steel, coll, root)
    bh.add_box("MountPlate", (0.02, 0.24, 0.20), (mount[0] + 0.01, 0.0, mount[2]), steel, coll, root)
    for sy in (-1, 1):
        for sz in (-1, 1):
            bh.add_box("MountBolt%d%d" % (sy + 1, sz + 1), (0.02, 0.03, 0.03), (mount[0] + 0.03, sy * 0.09, mount[2] + sz * 0.07), bolt, coll, root)
    bh.add_box("PoleSleeve", (0.2, 0.2, 0.25), (POLE_X, 0.0, GROUND + 0.125), bolt, coll, root)

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

    # The net: a DIAMOND lattice, the chain net's own topology — 5 rings of 12
    # nodes, each ring turned half a step so every node hangs between the two
    # above it; the triangles between rings make the two diagonal families
    # (the chains NetSim renders as links) plus each ring's horizontals (kept
    # as invisible stiffeners). Top ring at the rim under the 12 hooks, the
    # bottom NET_HEIGHT down at NET_BOTTOM_R.
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.verify()
    rings = []
    for r in range(NET_RINGS + 1):
        t = r / NET_RINGS
        rad = R_RIM + (NET_BOTTOM_R - R_RIM) * t
        z = -NET_HEIGHT * t
        row = []
        for i in range(12):
            ang = math.tau * (i + 0.5 * r) / 12
            row.append(bm.verts.new((rad * math.cos(ang), rad * math.sin(ang), z)))
        rings.append(row)
    for r in range(NET_RINGS):
        for i in range(12):
            a0, a1 = rings[r][i], rings[r][(i + 1) % 12]
            b0, b1 = rings[r + 1][i], rings[r + 1][(i + 1) % 12]
            for tri in ((a0, a1, b0), (a1, b1, b0)):
                f = bm.faces.new(tri)
                for loop in f.loops:
                    v = loop.vert
                    loop[uvl].uv = (math.atan2(v.co.y, v.co.x) / math.tau * 3.0, 1.0 + v.co.z / NET_HEIGHT)
    me = bpy.data.meshes.new("Net")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(net_mat)
    net = bpy.data.objects.new("Net", me)
    bh.link_obj(net, coll, pivot, (-R_RIM, 0, 0))
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
