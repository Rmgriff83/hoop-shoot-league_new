"""PEGGY, the locker's drop machine (docs/LOCKER.md): the cabinet model.

  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_peggy.py -- --force

Writes art/blender/peggy.blend and assets/locker/peggy.glb. A red arcade
cabinet with a bulb marquee, a navy peg board behind a glass pane, seven prize
bays under the slots (a frosted pane over each, the real ball meshes are
instanced there at runtime), a rail with a carriage and the puck, and a deck
with the big red button and the ticket slot. Nothing is animated here: Godot
drives every moving part (game/ui/peggy_panel.gd) by node name, so the NAMES
are the contract — Peg%03d / Bumper%03d / Divider%d follow the exact table
in core/locker/peggy_board.gd (PEGS below mirrors it; tests/test_peggy.gd
checks the glb against the core within a millimetre).

Sim frame: x right, y up, z toward the player; origin on the floor under the
cabinet's centre. Board units are 0.1 m: a board (x, y) sits at
(x * 0.1, BOARD_Y0 + y * 0.1) on the cabinet.
"""
import math
import os
import sys

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
WALL_X, SLOTS, DIV_H, DIV_TOP_R = 3.5, 7, 1.2, 0.08
ROWS, ROW_DY, PEG_R, BUMP_R = 10, 0.8, 0.12, 0.30
Y_TOP = DIV_H + 1.0 + ROWS * ROW_DY
RELEASE_Y = Y_TOP + 1.2
AIM_MAX = 1.0
BOARD_Y0 = 0.52                      # the slot floor, metres
BOARD_Z = 0.17                       # the board's front face
PEG_Z = BOARD_Z + 0.015


def pegs():
    """[(x, y, r, kind)] in the core's order: per row the left bumper, the
    pegs left to right, the right bumper; then the divider tops."""
    out = []
    for r in range(ROWS):
        y = Y_TOP - r * ROW_DY
        out.append((-WALL_X, y, BUMP_R, "bumper"))
        xs = [-2.5 + k for k in range(6)] if r % 2 == 0 else [-2.0 + k for k in range(5)]
        for x in xs:
            out.append((x, y, PEG_R, "peg"))
        out.append((WALL_X, y, BUMP_R, "bumper"))
    for k in range(SLOTS - 1):
        out.append((-2.5 + k, DIV_H, DIV_TOP_R, "divider"))
    return out


def board_to_sim(x, y, z=PEG_Z):
    return (x * U, BOARD_Y0 + y * U, z)


# ---- helpers ------------------------------------------------------------------


def mat_alpha(name, rgb, alpha):
    """A see-through flat material (glass, frost): glTF alphaMode BLEND."""
    m = mat_flat(name, rgb, roughness=0.35)
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Alpha"].default_value = alpha
    for attr, val in (("blend_method", "BLEND"), ("surface_render_method", "BLENDED")):
        try:
            setattr(m, attr, val)
        except Exception:
            pass
    m.use_backface_culling = True
    return m


def add_cyl(name, radius, depth, sim_center, mat, coll, parent, axis="z"):
    """A cylinder; axis "z" points toward the player (a peg), "y" stands up (a cap)."""
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=20, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = o.data.name = name
    if axis == "z":
        o.rotation_euler = (math.radians(90.0), 0.0, 0.0)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    o.data.materials.append(mat)
    link_obj(o, coll, parent, s2b(sim_center))
    return o


# ---- the cabinet ----------------------------------------------------------------


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    coll = bpy.data.collections.new("Peggy")
    scene.collection.children.link(coll)
    c_cab, c_board, c_pegs = sub(coll, "Cabinet"), sub(coll, "Board"), sub(coll, "Pegs")
    c_slots, c_deck, c_moving = sub(coll, "Slots"), sub(coll, "Deck"), sub(coll, "Moving")

    red = mat_tex("Peggy_Cabinet", TEX("peggy_cabinet.png"))
    cream = mat_flat("Peggy_Cream", (241, 232, 208), roughness=0.8)
    ink = mat_flat("Peggy_Ink", (26, 22, 24))
    steel = mat_flat("Peggy_Steel", (196, 200, 208), roughness=0.4)
    gold = mat_flat("Peggy_Gold", (240, 184, 74), roughness=0.5)
    navy = mat_tex("Peggy_Board", TEX("peggy_board.png"))
    marquee = mat_tex("Peggy_Marquee", TEX("peggy_marquee.png"), emissive=True)
    bulb = mat_flat("Peggy_Bulb", (255, 232, 170))
    btn_up = mat_tex("Peggy_BtnUp", TEX("peggy_button_up.png"))
    ticket = mat_tex("Peggy_Ticket", TEX("peggy_ticket.png"))
    plate = mat_tex("Peggy_Plate", TEX("peggy_plate_common.png"))
    light = mat_tex("Peggy_Light", TEX("peggy_light.png"), emissive=True)
    glass = mat_alpha("Peggy_Glass", (190, 230, 255), 0.16)
    frost = mat_alpha("Peggy_Frost", (236, 240, 246), 0.55)
    dark = mat_flat("Peggy_Hall", (18, 16, 22))
    floor = mat_flat("Peggy_Floor", (40, 38, 46))

    root = add_empty("PeggyRoot", coll, None, (0, 0, 0))

    # The shell: a tall red box, the glass window cut by a cream bezel.
    add_box("Cabinet", (0.90, 2.05, 0.40), (0, 1.025, -0.05), red, c_cab, root)
    add_box("Kick", (0.90, 0.30, 0.30), (0, 0.15, 0.30), ink, c_cab, root)
    add_box("Deck", (0.90, 0.12, 0.30), (0, 0.36, 0.30), red, c_cab, root)
    add_box("DeckLip", (0.90, 0.02, 0.02), (0, 0.43, 0.45), cream, c_cab, root)
    for name, size, c in (
        ("BezelL", (0.06, 1.40, 0.04), (-0.42, 1.07, 0.24)),
        ("BezelR", (0.06, 1.40, 0.04), (0.42, 1.07, 0.24)),
        ("BezelT", (0.90, 0.04, 0.04), (0, 1.76, 0.24)),
        ("BezelB", (0.90, 0.04, 0.04), (0, 0.38, 0.24)),
    ):
        add_box(name, size, c, cream, c_cab, root)

    # The marquee: a lit face on a box, 18 bulbs around it in one chase order.
    add_box("MarqueeBox", (0.90, 0.26, 0.10), (0, 1.89, 0.16), red, c_cab, root)
    add_quad("MarqueeFace", [(-0.43, 1.78, 0.212), (0.43, 1.78, 0.212), (0.43, 2.00, 0.212), (-0.43, 2.00, 0.212)],
             (0, 0, 1), marquee, c_cab, root)
    path = [(-0.39 + k * 0.13, 1.99) for k in range(7)]
    path += [(0.43, 1.93), (0.43, 1.85)]
    path += [(0.39 - k * 0.13, 1.79) for k in range(7)]
    path += [(-0.43, 1.85), (-0.43, 1.93)]
    for i, (x, y) in enumerate(path):
        add_box("Bulb%03d" % i, (0.03, 0.03, 0.03), (x, y, 0.225), bulb, c_cab, root)

    # The board: navy back, pegs, bumpers, dividers, the shelf the puck lands on.
    add_box("Board", (0.72, 1.34, 0.02), (0, 1.07, BOARD_Z - 0.01), navy, c_board, root)
    add_box("WallL", (0.02, 1.34, 0.06), (-0.37, 1.07, BOARD_Z + 0.02), cream, c_board, root)
    add_box("WallR", (0.02, 1.34, 0.06), (0.37, 1.07, BOARD_Z + 0.02), cream, c_board, root)
    n_peg = n_bump = n_div = 0
    for x, y, r, kind in pegs():
        if kind == "peg":
            add_cyl("Peg%03d" % n_peg, r * U, 0.03, board_to_sim(x, y), steel, c_pegs, root)
            n_peg += 1
        elif kind == "bumper":
            add_cyl("Bumper%03d" % n_bump, r * U, 0.03, board_to_sim(x, y), cream, c_pegs, root)
            n_bump += 1
        else:
            add_cyl("Divider%d" % n_div, r * U, 0.03, board_to_sim(x, y), cream, c_pegs, root)
            add_box("DividerWall%d" % n_div, (0.016, DIV_H * U, 0.03), (x * U, BOARD_Y0 + DIV_H * U * 0.5, PEG_Z),
                    cream, c_pegs, root)
            n_div += 1
    add_box("Shelf", (0.72, 0.012, 0.06), (0, BOARD_Y0 - 0.006, BOARD_Z + 0.02), cream, c_board, root)

    # The prize bays under the shelf: a plate, the ball's empty, a frosted pane.
    for i in range(SLOTS):
        x = (-3.0 + i) * U
        add_quad("SlotPlate%d" % i, [(x - 0.045, 0.405, BOARD_Z + 0.002), (x + 0.045, 0.405, BOARD_Z + 0.002),
                                     (x + 0.045, 0.445, BOARD_Z + 0.002), (x - 0.045, 0.445, BOARD_Z + 0.002)],
                 (0, 0, 1), plate, c_slots, root)
        add_empty("Prize%d" % i, c_slots, root, (x, 0.472, BOARD_Z + 0.03))
        add_quad("Frost%d" % i, [(x - 0.048, 0.40, 0.215), (x + 0.048, 0.40, 0.215),
                                 (x + 0.048, 0.512, 0.215), (x - 0.048, 0.512, 0.215)],
                 (0, 0, 1), frost, c_slots, root)
        add_quad("SlotLight%d" % i, [(x - 0.04, 0.655, BOARD_Z + 0.002), (x + 0.04, 0.655, BOARD_Z + 0.002),
                                     (x + 0.04, 0.67, BOARD_Z + 0.002), (x - 0.04, 0.67, BOARD_Z + 0.002)],
                 (0, 0, 1), light, c_slots, root)
    for k in range(SLOTS + 1):
        add_box("BayWall%d" % k, (0.012, 0.11, 0.05), ((-3.5 + k) * U, 0.46, BOARD_Z + 0.025), ink, c_slots, root)
    add_box("BayFloor", (0.72, 0.01, 0.05), (0, 0.405, BOARD_Z + 0.025), ink, c_slots, root)

    # The rail, the carriage, the puck.
    rail_y = BOARD_Y0 + RELEASE_Y * U + 0.055
    add_box("Rail", (0.72, 0.014, 0.014), (0, rail_y, 0.21), steel, c_board, root)
    add_box("EndStopL", (0.02, 0.04, 0.03), (-(AIM_MAX * U + 0.045), rail_y, 0.21), ink, c_board, root)
    add_box("EndStopR", (0.02, 0.04, 0.03), ((AIM_MAX * U + 0.045), rail_y, 0.21), ink, c_board, root)
    carriage = add_empty("Carriage", c_moving, root, (0, rail_y, 0.21))
    add_box("CarriageBody", (0.06, 0.05, 0.04), (0, -0.01, 0), ink, c_moving, carriage)
    add_box("CarriageJawL", (0.012, 0.045, 0.03), (-0.03, -0.05, 0), steel, c_moving, carriage)
    add_box("CarriageJawR", (0.012, 0.045, 0.03), (0.03, -0.05, 0), steel, c_moving, carriage)
    add_cyl("Puck", 0.025, 0.02, board_to_sim(0.0, RELEASE_Y, PEG_Z), gold, c_moving, root)

    # The glass over the whole board.
    add_quad("Glass", [(-0.39, 0.395, 0.235), (0.39, 0.395, 0.235), (0.39, 1.745, 0.235), (-0.39, 1.745, 0.235)],
             (0, 0, 1), glass, c_board, root)

    # The deck: the big red button, the ticket slot.
    add_box("Button", (0.16, 0.03, 0.16), (0, 0.435, 0.30), ink, c_deck, root)
    add_cyl("BtnCap", 0.06, 0.035, (0, 0.468, 0.30), btn_up, c_deck, root, axis="y")
    add_box("TicketSlot", (0.10, 0.03, 0.05), (0.27, 0.435, 0.30), cream, c_deck, root)
    add_box("TicketSlit", (0.07, 0.004, 0.03), (0.27, 0.452, 0.30), ink, c_deck, root)
    home = add_empty("TicketHome", c_deck, root, (0.27, 0.456, 0.30))
    add_quad("Ticket", [(-0.03, 0, 0.012), (0.03, 0, 0.012), (0.03, 0, -0.012), (-0.03, 0, -0.012)],
             (0, 1, 0), ticket, c_deck, home)

    # The hall behind and the floor.
    add_quad("HallBack", [(-2.5, 0, -0.9), (2.5, 0, -0.9), (2.5, 3.2, -0.9), (-2.5, 3.2, -0.9)], (0, 0, 1), dark, c_cab, root)
    add_quad("Floor", [(-2.5, 0, -1.0), (2.5, 0, -1.0), (2.5, 0, 2.5), (-2.5, 0, 2.5)], (0, 1, 0), floor, c_cab, root)
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
