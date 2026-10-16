"""Build the park hoop (Ross's "Park Area Concept", 2026-10-15): a slim WHITE
park board, 1.40 x 1.05 x 0.022 m, with a black edge band and the black
shooting square painted on its face (park_board.png), the gym rim + net
(add_gym_rim's neck, flange, spring box and hooks — the net itself is
NetBodies' cotton at runtime), and a BLACK in-ground pole 0.17 m behind the
board, braced straight to the board's back. No LED scoreboard: the park's
score lives on the HUD (CourtGeometry binds LedFace only when it exists).

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_park_hoop.py -- --force

Produces  art/blender/park_hoop.blend   (source, ignored by Godot) and
          assets/hoops/park/hoop.glb    (game export, Y-up, transforms applied).

Same conventions as build_street_hoop.py: origin is the RIM CENTRE, blender
(x, y, z) = (sim x, -sim z, sim y). The sim keeps SimGeometry.park(): board
half-width 0.70, bottom 0.15 under the rim, pole r 0.07 at +0.17 behind the
board face. CREATOR script: refuses to overwrite an existing park_hoop.blend
unless run with `-- --force`.
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
BLEND_PATH = os.path.join(ROOT, "art", "blender", "park_hoop.blend")
GLB_PATH = os.path.join(ROOT, "assets", "hoops", "park", "hoop.glb")
TEX = lambda name: os.path.join(ROOT, "assets", "textures", name)

R_RIM = bh.R_RIM
R_TUBE = bh.R_TUBE
BOARD_OFF = bh.BOARD_OFF
BOARD_BOTTOM = -0.15
BOARD_TOP = 0.90
BOARD_HALF_W = 0.70            # SimGeometry.PARK_BOARD_HALF_W
BOARD_THICK = 0.022
BAND = 0.012                   # the black edge band proud of the board on every side
NET_BOTTOM_R = bh.NET_BOTTOM_R
NET_HEIGHT = bh.NET_HEIGHT
POLE_X = BOARD_OFF + 0.17      # SimGeometry.PARK_POLE_OFF behind the board face
POLE_R = 0.07                  # SimGeometry.PARK_POLE_R
GROUND = -2.44                 # the floor, in rim-centre space (rim 8 ft up)
POLE_TOP = BOARD_TOP + 0.05


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    coll = bpy.data.collections.new("Hoop")      # add_gym_rim looks this name up
    bpy.context.scene.collection.children.link(coll)

    root = bpy.data.objects.new("HoopRoot", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.15
    bh.link_obj(root, coll)

    body = bh.mat_flat("Park_Body", (232, 232, 228))
    face = bh.mat_tex("Park_Face", TEX("park_board.png"))
    band = bh.mat_flat("Park_Band", (28, 28, 30))
    steel = bh.mat_flat("Park_Steel", (58, 60, 64), roughness=0.7)
    pole = bh.mat_tex("Park_Pole", TEX("park_pole.png"))
    rim_mat = bh.mat_tex("Rim", TEX("hoop_rim.png"))
    net_mat = bh.mat_tex("Net", TEX("hoop_net.png"), alpha_clip=True, double_sided=True)

    # The board: a slim white slab, its textured front face (slot 1).
    h = BOARD_TOP - BOARD_BOTTOM
    cz = (BOARD_TOP + BOARD_BOTTOM) / 2
    board = bh.add_box("Backboard", (BOARD_THICK, BOARD_HALF_W * 2, h),
                       (BOARD_OFF + BOARD_THICK / 2, 0, cz), body, coll, root)
    board.data.materials.append(face)
    bm = bmesh.new()
    bm.from_mesh(board.data)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        if f.normal.x < -0.5:  # front face, toward the shooter
            f.material_index = 1
            for loop in f.loops:
                y, z = loop.vert.co.y, loop.vert.co.z
                loop[uv].uv = ((BOARD_HALF_W - y) / (2 * BOARD_HALF_W), (z + h / 2) / h)
    bm.to_mesh(board.data)
    bm.free()
    # The black band: a slightly bigger slab just behind the face.
    bh.add_box("BoardBand", (BOARD_THICK + 0.004, BOARD_HALF_W * 2 + 2 * BAND, h + 2 * BAND),
               (BOARD_OFF + BOARD_THICK / 2 + 0.004, 0, cz), band, coll, root)

    # The pole from the ground to just over the board, a brace to the board's back.
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=POLE_R, depth=POLE_TOP - GROUND, location=(0, 0, 0))
    p = bpy.context.active_object
    p.name = p.data.name = "Pole"
    p.data.materials.append(pole)
    bh.link_obj(p, coll, root, (POLE_X, 0, (POLE_TOP + GROUND) / 2))
    bh.add_box("Brace", (POLE_X - (BOARD_OFF + BOARD_THICK) + 0.02, 0.08, 0.10),
               ((POLE_X + BOARD_OFF + BOARD_THICK) / 2, 0, cz + 0.25), steel, coll, root)
    bh.add_box("BraceLow", (POLE_X - (BOARD_OFF + BOARD_THICK) + 0.02, 0.06, 0.08),
               ((POLE_X + BOARD_OFF + BOARD_THICK) / 2, 0, cz - 0.3), steel, coll, root)

    # Rim pivot at the ring's back edge; ring + net hang under it.
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
    bmesh.ops.subdivide_edges(bm, edges=vertical, cuts=3, use_grid_fill=True)
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
    gym.apply()                       # neck, spring box, flange, 12 hooks; net alpha direct
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    gym.export_glb(GLB_PATH)
    print("park hoop: %d objects -> %s" % (len(c.objects), GLB_PATH))
