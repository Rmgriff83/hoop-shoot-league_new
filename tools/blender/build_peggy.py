"""PEGGY, the drop machine (docs/LOCKER.md): the v2 carnival cabinet model.

  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_peggy.py -- --force

Writes art/blender/peggy.blend and assets/locker/peggy.glb. Modelled on
Ross's design (peggy-cabinet-v2.js, 2026-10-15): a face of wavy sunburst
wings ringed with coloured bulbs under a marquee arch, a dark speckled board
of gold pegs with teal zigzag bumpers (twelve rows), a sloped black prize
tray with orange acrylic bay walls, and a deep console with a joystick that
drives the crane and a big orange DROP button. No hall, floor or glass: the
page's wash shows through around the cabinet. Nothing is animated here:
Godot drives every moving part (game/ui/peggy_machine.gd) by node name, so
the NAMES are the contract — Peg%03d / Bumper%03d / Divider%d follow the
exact table in core/locker/peggy_board.gd (PEGS below mirrors it;
tests/test_peggy.gd checks the glb against the core within a millimetre).

Sim frame: x right, y up, z toward the player; origin on the floor under the
cabinet's centre. Board units are 0.1 m: a board (x, y) sits at
(x * 0.1, BOARD_Y0 + y * 0.1) on the cabinet.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_cage import add_box, add_empty, add_quad, export_glb, link_obj, mat_flat, mat_tex, s2b, sub  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "peggy.blend")
GLB_PATH = os.path.join(ROOT, "assets", "locker", "peggy.glb")
TEX = lambda n: os.path.join(ROOT, "assets", "textures", n)  # noqa: E731

# ---- the board, mirrored from core/locker/peggy_board.gd ----------------------
U = 0.1
WALL_X, SLOTS, DIV_H, DIV_TOP_R = 3.5, 7, 1.2, 0.06
ROWS, ROW_DY, PEG_R, BUMP_R, PUCK_R = 12, 0.8, 0.12, 0.45, 0.25
Y_TOP = DIV_H + 1.0 + ROWS * ROW_DY
RELEASE_Y = Y_TOP + 1.2
AIM_MAX = WALL_X - BUMP_R - PUCK_R - 0.02
BOARD_Y0 = 0.54                      # the slot floor, metres
BZ = 0.06                            # the board's front face
PZ = BZ + 0.02                       # the pegs' plane
FW, FH = 1.12, 2.46                  # the face quad


def pegs():
    """[(x, y, r, kind)] in the core's order: an even row's left bumper, its
    five pegs, its right bumper; an odd row's six pegs; then the divider tops."""
    out = []
    for r in range(ROWS):
        y = Y_TOP - r * ROW_DY
        if r % 2 == 0:
            out.append((-WALL_X, y, BUMP_R, "bumper"))
            for k in range(5):
                out.append((-2.0 + k, y, PEG_R, "peg"))
            out.append((WALL_X, y, BUMP_R, "bumper"))
        else:
            for k in range(6):
                out.append((-2.5 + k, y, PEG_R, "peg"))
    for k in range(SLOTS - 1):
        out.append((-2.5 + k, DIV_H, DIV_TOP_R, "divider"))
    return out


def B(x, y, z=PZ):
    return (x * U, BOARD_Y0 + y * U, z)


# ---- helpers ------------------------------------------------------------------


def mat_alpha(name, rgb, alpha, roughness=0.35):
    """A see-through flat material (acrylic): glTF alphaMode BLEND."""
    m = mat_flat(name, rgb, roughness=roughness)
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Alpha"].default_value = alpha
    for attr, val in (("blend_method", "BLEND"), ("surface_render_method", "BLENDED")):
        try:
            setattr(m, attr, val)
        except Exception:
            pass
    m.use_backface_culling = False
    return m


def _finish(o, name, mat, coll, parent, sim_center):
    o.name = o.data.name = name
    o.data.materials.append(mat)
    link_obj(o, coll, parent, s2b(sim_center))
    return o


def add_cyl(name, radius, depth, sim_center, mat, coll, parent, axis="z", verts=16):
    """A cylinder; axis "z" points toward the player (a peg, a cap)."""
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=verts, location=(0, 0, 0))
    o = bpy.context.active_object
    if axis == "z":
        o.rotation_euler = (math.radians(90.0), 0.0, 0.0)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return _finish(o, name, mat, coll, parent, sim_center)


def add_sphere(name, radius, sim_center, mat, coll, parent, seg=12, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=seg, ring_count=rings, location=(0, 0, 0))
    return _finish(bpy.context.active_object, name, mat, coll, parent, sim_center)


def add_ring(name, r_in, r_out, sim_center, mat, coll, parent):
    """A flat ring facing the player (the DROP halo)."""
    bpy.ops.mesh.primitive_torus_add(major_radius=(r_in + r_out) / 2.0, minor_radius=(r_out - r_in) / 2.0,
                                     major_segments=24, minor_segments=4, location=(0, 0, 0))
    o = bpy.context.active_object
    o.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return _finish(o, name, mat, coll, parent, sim_center)


def add_prism(name, pts, depth, sim_center, mat, coll, parent):
    """A flat polygon (sim x, y pairs) extruded `depth` toward the player."""
    bm = bmesh.new()
    back = [bm.verts.new(s2b((x, y, 0.0))) for x, y in pts]
    front = [bm.verts.new(s2b((x, y, depth))) for x, y in pts]
    bm.faces.new(back)
    bm.faces.new(list(reversed(front)))
    n = len(pts)
    for i in range(n):
        bm.faces.new([back[i], back[(i + 1) % n], front[(i + 1) % n], front[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    link_obj(o, coll, parent, s2b(sim_center))
    return o


def add_group(name, coll, parent, sim_loc, rot_x=0.0, scale=1.0):
    """An empty with a tilt about the sim x axis (the deck, the tray front)."""
    e = add_empty(name, coll, parent, sim_loc)
    e.rotation_euler = (rot_x, 0.0, 0.0)
    e.scale = (scale, scale, scale)
    return e


def quad_at(name, w, h, sim_center, mat, coll, parent):
    """A w x h quad facing the player, centred on sim_center (its own origin,
    so the machine can move it)."""
    x, y, z = sim_center
    o = add_quad(name, [(x - w / 2, y - h / 2, z), (x + w / 2, y - h / 2, z), (x + w / 2, y + h / 2, z),
                        (x - w / 2, y + h / 2, z)], (0, 0, 1), mat, coll, parent, origin=sim_center)
    o.location = Vector(s2b(sim_center))
    return o


def quad_local(name, w, h, sim_center, mat, coll, parent):
    """A quad under a tilted / scaled group: corners in the GROUP's frame."""
    o = quad_at(name, w, h, (0, 0, 0), mat, coll, parent)
    o.location = Vector(s2b(sim_center))
    return o


# ---- the cabinet ----------------------------------------------------------------


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    coll = bpy.data.collections.new("Peggy")
    scene.collection.children.link(coll)
    c_face, c_board, c_pegs = sub(coll, "Face"), sub(coll, "Board"), sub(coll, "Pegs")
    c_tray, c_console, c_moving = sub(coll, "Tray"), sub(coll, "Console"), sub(coll, "Moving")

    face = mat_tex("Peggy_Face", TEX("peggy_face.png"), alpha_clip=True, double_sided=True)
    board = mat_tex("Peggy_Board", TEX("peggy_board.png"))
    deck_tex = mat_tex("Peggy_Deck", TEX("peggy_deck.png"))
    big_ticket = mat_tex("Peggy_BigTicket", TEX("peggy_big_ticket.png"), alpha_clip=True, double_sided=True)
    glow = mat_tex("Peggy_Glow", TEX("peggy_glow.png"), alpha_clip=True, double_sided=True, emissive=True)
    mystery = mat_tex("Peggy_Mystery", TEX("peggy_mystery_ball_common.png"), alpha_clip=True, double_sided=True)
    dark = mat_flat("Peggy_Dark", (26, 21, 18), roughness=0.9)
    ink = mat_flat("Peggy_Ink", (26, 22, 24), roughness=0.85)
    ink2 = mat_flat("Peggy_Ink2", (34, 28, 32), roughness=0.85)
    body = mat_flat("Peggy_Body", (42, 34, 40), roughness=0.85)
    cream = mat_flat("Peggy_Cream", (241, 232, 208), roughness=0.8)
    gold = mat_flat("Peggy_Gold", (240, 184, 74), roughness=0.5)
    teal = mat_flat("Peggy_Teal", (63, 140, 122), roughness=0.85)
    orange = mat_flat("Peggy_Orange", (232, 112, 58), roughness=0.5)
    steel = mat_flat("Peggy_Steel", (196, 200, 208), roughness=0.4)
    puck = mat_flat("Peggy_Puck", (241, 232, 208), roughness=0.45)
    bulb = mat_flat("Peggy_Bulb", (255, 240, 220), roughness=0.5)
    acrylic = mat_alpha("Peggy_Acrylic", (232, 112, 58), 0.85)
    light = mat_alpha("Peggy_Light", (240, 184, 74), 0.0)
    halo = mat_alpha("Peggy_Halo", (240, 184, 74), 0.0)
    red = mat_flat("Peggy_Red", (232, 48, 46), roughness=0.6)

    root = add_empty("PeggyRoot", coll, None, (0, 0, 0))

    # The face: the sunburst wings and the marquee arch, a dark slab behind.
    quad_at("Face", FW, FH, (0, FH / 2, 0), face, c_face, root)
    add_box("FaceBack", (FW * 0.96, FH * 0.9, 0.05), (0, FH * 0.47, -0.035), dark, c_face, root)

    # The board: the speckled back, the cream top bar, the black side rails.
    bh = (RELEASE_Y + 1.0) * U
    quad_at("Board", 0.72, bh, (0, BOARD_Y0 + bh / 2, BZ), board, c_board, root)
    add_box("TopBar", (0.70, 0.016, 0.04), (0, BOARD_Y0 + bh - 0.012, BZ + 0.03), cream, c_board, root)
    for side, name in ((-1, "RailL"), (1, "RailR")):
        add_box(name, (0.03, bh + 0.02, 0.10), (side * 0.375, BOARD_Y0 + bh / 2, BZ + 0.03), ink2, c_board, root)

    # The pegs, the bumpers (teal wedges on the walls, their node at the
    # sim's circle centre), the divider tops.
    n_peg = n_bump = n_div = 0
    for x, y, r, kind in pegs():
        if kind == "peg":
            add_cyl("Peg%03d" % n_peg, r * U, 0.04, B(x, y), gold, c_pegs, root, verts=10)
            n_peg += 1
        elif kind == "bumper":
            sx = 1.0 if x > 0 else -1.0
            # the wedge's base sits on the wall, its tip 4.5 cm in (the sim's
            # circle reaches that far); built in the node's frame so the node
            # itself is at the circle's centre
            pts = [(sx * 0.01, -0.08), (sx * 0.01 - sx * 0.045, 0.0), (sx * 0.01, 0.08)]
            if sx > 0:
                pts.reverse()
            add_prism("Bumper%03d" % n_bump, pts, 0.03, B(x, y, BZ), teal, c_pegs, root)
            n_bump += 1
        else:
            add_cyl("Divider%d" % n_div, r * U, 0.04, B(x, y), acrylic, c_pegs, root, verts=10)
            n_div += 1

    # The tray: the bins' back, eight acrylic bay walls, the floor, the sloped
    # front; a hidden prize sprite and a slot light per bay.
    add_box("BinBack", (0.72, DIV_H * U, 0.012), (0, BOARD_Y0 + DIV_H * U / 2, BZ + 0.002), ink2, c_tray, root)
    for k in range(SLOTS + 1):
        add_box("BayWall%d" % k, (0.008, DIV_H * U + 0.02, 0.12), ((-3.5 + k) * U, BOARD_Y0 + DIV_H * U / 2, BZ + 0.06),
                acrylic, c_tray, root)
    add_box("TrayFloor", (0.80, 0.03, 0.30), (0, BOARD_Y0 - 0.015, 0.15), ink2, c_tray, root)
    front = add_group("Front", c_tray, root, (0, BOARD_Y0 - 0.03, 0.30), rot_x=-0.95)
    add_box("FrontFace", (0.80, 0.07, 0.02), (0, -0.035, 0), ink, c_tray, front)
    for i in range(SLOTS):
        xx = (-3.0 + i) * U
        prize = add_empty("Prize%d" % i, c_tray, root, (xx, BOARD_Y0 + 0.042, BZ + 0.09))
        quad_local("PrizeSprite%d" % i, 0.078, 0.078, (0, 0, 0), mystery, c_tray, prize)
        quad_at("SlotLight%d" % i, 0.09, DIV_H * U, (xx, BOARD_Y0 + DIV_H * U / 2, BZ + 0.004), light, c_tray, root)

    # The console: a deep body, the tilted deck with the joystick (MOVE) and
    # the big button (DROP), the ticket slot. Scaled up and pulled forward.
    console = add_group("Console", c_console, root, (0, -0.15, 0.08), scale=1.3)
    add_box("ConsoleBody", (0.92, 0.40, 0.42), (0, 0.10, 0.16), ink2, c_console, console)
    add_box("ConsoleLip", (0.94, 0.05, 0.44), (0, 0.29, 0.17), orange, c_console, console)
    deck = add_group("Deck", c_console, console, (0, 0.36, 0.42), rot_x=-0.42)
    add_box("DeckBody", (0.92, 0.46, 0.05), (0, 0, -0.025), body, c_console, deck)
    quad_local("DeckFace", 0.90, 0.36, (0, 0.02, 0.001), deck_tex, c_console, deck)
    joy = add_empty("Joy", c_console, deck, (-0.22, 0.04, 0))
    add_cyl("JoyRing", 0.078, 0.02, (0, 0, 0.01), ink, c_console, joy)
    stick = add_empty("Stick", c_console, joy, (0, 0, 0.02))
    add_cyl("Shaft", 0.012, 0.12, (0, 0, 0.06), steel, c_console, stick, verts=8)
    add_sphere("Knob", 0.06, (0, 0, 0.14), orange, c_console, stick)
    btn = add_empty("Btn", c_console, deck, (0.22, 0.04, 0))
    add_cyl("Bezel", 0.10, 0.03, (0, 0, 0.015), ink, c_console, btn, verts=20)
    cap = add_cyl("Cap", 0.082, 0.04, (0, 0, 0.05), orange, c_console, btn, verts=20)
    xmark = add_empty("XMark", c_console, cap, (0, 0, 0.021))
    for i, rot in enumerate((math.pi / 4, -math.pi / 4)):
        o = add_box("XInk%d" % i, (0.072, 0.018, 0.001), (0, 0, 0), ink, c_console, xmark)
        o.rotation_euler = (0.0, rot, 0.0)
        o = add_box("XRed%d" % i, (0.056, 0.009, 0.002), (0, 0, 0.001), red, c_console, xmark)
        o.rotation_euler = (0.0, rot, 0.0)
    add_ring("Halo", 0.11, 0.13, (0, 0, 0.032), halo, c_console, btn)
    add_box("TicketSlot", (0.10, 0.03, 0.02), (0, 0.15, 0.01), cream, c_console, deck)
    add_box("TicketSlit", (0.07, 0.006, 0.022), (0, 0.15, 0.012), ink, c_console, deck)
    quad_local("Ticket", 0.06, 0.03, (0, 0.19, 0.03), gold, c_console, deck)
    add_empty("SlotMark", c_console, deck, (0, 0.15, 0.02))

    # The big ticket that flies into the slot (moved by the machine).
    quad_at("BigTicket", 0.30, 0.15, (0, 0, 0), big_ticket, c_moving, root)

    # The crane on its rail across the board, the puck.
    rail_y = BOARD_Y0 + RELEASE_Y * U + 0.05
    add_box("Rail", (0.70, 0.012, 0.012), (0, rail_y, BZ + 0.07), steel, c_board, root)
    crane = add_empty("Crane", c_moving, root, (0, rail_y, BZ + 0.07))
    add_box("CraneBody", (0.05, 0.035, 0.035), (0, 0, 0), ink, c_moving, crane)
    add_box("CraneJawL", (0.008, 0.04, 0.02), (-0.022, -0.035, 0), steel, c_moving, crane)
    add_box("CraneJawR", (0.008, 0.04, 0.02), (0.022, -0.035, 0), steel, c_moving, crane)
    add_cyl("Puck", PUCK_R * U, 0.02, B(0.0, RELEASE_Y, PZ), puck, c_moving, root)

    # The bulbs: seven along the arch, nine pairs down the wing edges, each
    # with a star glow; the machine colours and chases them.
    bp = []
    for k in range(7):
        u = -0.82 + k * 0.273
        bp.append((u * 0.5, 2.36 - 0.12 * u * u + 0.03 * math.cos(u * 6)))
    for k in range(9):
        y = 2.0 - k * 0.205
        bp.append((-0.50 + 0.03 * math.sin(k), y))
        bp.append((0.50 - 0.03 * math.sin(k + 1), y))
    for i, (bx, by) in enumerate(bp):
        add_sphere("Bulb%03d" % i, 0.026, (bx, by, 0.03), bulb, c_face, root, seg=10, rings=6)
        quad_at("Glow%03d" % i, 0.12, 0.12, (bx, by, 0.05), glow, c_face, root)
    return coll


if __name__ == "__main__" and bpy.app.background:
    if os.path.exists(BLEND_PATH) and "--force" not in sys.argv:
        print("REFUSING: %s exists. Re-run with `-- --force` to rebuild." % BLEND_PATH)
        sys.exit(0)
    c = build()
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    export_glb(c, GLB_PATH)
    tris = 0
    for o in c.all_objects:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
    print("peggy: %d objects, %d tris -> %s" % (len(c.all_objects), tris, GLB_PATH))
