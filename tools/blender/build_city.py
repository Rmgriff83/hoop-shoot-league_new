"""Build the city arena: an inner-city cage court at dusk — a teal blacktop
slab inside a chain-link fence, a two-lane street behind the hoop's fence
(cars drive it: game/view/city_fx.gd), brick tenements and two glass towers
beyond, brick walls flanking the court (one with a mural), street trees,
floodlight poles, a dusk sky cylinder and the hoop's in-ground pole.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_city.py

Produces  art/blender/city.blend        (source, ignored by Godot) and
          assets/arena/city/city.glb    (game export, Y-up, transforms applied).

Sim frame (like the cage and the beach): origin at the release plane on the
floor, +x toward the hoop and the street, +z shooter's right, y up;
blender (x, y, z) = (sim x, -sim z, sim y). Numbers are SIM metres.

Runtime contract (game/court/court_geometry.gd + game/view/city_fx.gd): the
empty `Pole` is placed by Godot behind the board; `StreetRig` (an empty on
the street's centre line) gives CityFx the lane line; every `Windows*` face
gets the windows shader (lit panes switching on and off); `FloodHead*` quads
are unshaded; `TreeRig*` billboards turn to the camera; `ScoreboardRig` /
`LedFace` host the ground LED board. `City` is the static root / shake handle.

CREATOR script: refuses to overwrite an existing city.blend unless run with
`-- --force`. Never touches the other arenas.
"""
import math
import os
import sys
import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_cage as cage        # noqa: E402  (helpers: s2b, add_quad, add_box, mat_tex, ...)

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "city.blend")
GLB_PATH = os.path.join(ROOT, "assets", "arena", "city", "city.glb")
TEX = lambda name: os.path.join(ROOT, "assets", "textures", name)

CITY_DIST = 2.9 * 1.25                    # SimGeometry.CITY_DIST
BOARD_X = CITY_DIST + 0.3796
POLE_X = BOARD_X + 0.3                    # CourtGeometry.CROSSBAR_X_OFF
# The lined slab: 14.6 x 15.2 m, authored in city_court.png with the rim at
# x 3.625 and the baseline at 4.6 (so it stays behind the pole at 4.30).
COURT_X0, COURT_X1, COURT_HALF_W = -9.9, 4.7, 7.6
# Knee-high wall + chain-link fence, the beach's loop: SimGeometry.city()'s
# walls MUST match these.
WALL_T = 0.25
WALL_H = 0.45
FENCE_TOP = 3.6
ENC_X0, ENC_X1, ENC_HALF_W = -11.2, 5.7, 8.6
# The street behind the back fence: kerb, sidewalk, two lanes, far sidewalk.
KERB_H = 0.12
WALK_X0, WALK_X1 = ENC_X1 + 0.25, 7.6
ROAD_X0, ROAD_X1 = 7.6, 14.6
FAR_X0, FAR_X1 = 14.6, 16.3
STREET_X = (ROAD_X0 + ROAD_X1) / 2.0       # 11.1: CityFx.STREET_X
STREET_HALF_LEN = 46.0
BLOCK_X0 = 25.0                            # the tenement row starts here (a vacant lot between)
SKY_R, SKY_Y0, SKY_Y1 = 60.0, -3.0, 50.0
# Window grid: a city_windows tile is 4 windows across (8 m) by 4 storeys
# (12.8 m); a city_tower tile is 4 panes (4 m) by 8 panes (8 m).
WIN_TILE = (8.0, 12.8)
TOWER_TILE = (4.0, 8.0)
BRICK_PER_M = 0.4


def _block(name, x0, x1, z0, z1, h, wall_mat, coll, parent, uv_per_m=BRICK_PER_M, windows=None, win_mat=None, win_idx=0):
    """A building: four wall quads + a roof, brick-tiled; `windows` lists the
    faces ("-x", "+x", "-z", "+z") that get a Windows%d quad just in front."""
    faces = {
        "-x": ([(x0, 0, z1), (x0, 0, z0), (x0, h, z0), (x0, h, z1)], (-1, 0, 0), z1 - z0),
        "+x": ([(x1, 0, z0), (x1, 0, z1), (x1, h, z1), (x1, h, z0)], (1, 0, 0), z1 - z0),
        "-z": ([(x0, 0, z0), (x1, 0, z0), (x1, h, z0), (x0, h, z0)], (0, 0, -1), x1 - x0),
        "+z": ([(x1, 0, z1), (x0, 0, z1), (x0, h, z1), (x1, h, z1)], (0, 0, 1), x1 - x0),
    }
    for key, (corners, toward, length) in faces.items():
        cage.add_quad("%s_%s" % (name, key.replace("-", "n").replace("+", "p")), corners, toward, wall_mat, coll, parent,
                      (length * uv_per_m, h * uv_per_m))
    cage.add_quad("%s_roof" % name, [(x0, h, z0), (x1, h, z0), (x1, h, z1), (x0, h, z1)], (0, 1, 0), wall_mat, coll, parent,
                  ((x1 - x0) * uv_per_m, (z1 - z0) * uv_per_m))
    idx = win_idx
    for key in (windows or []):
        corners, toward, length = faces[key]
        eps = 0.02
        off = {"-x": (-eps, 0, 0), "+x": (eps, 0, 0), "-z": (0, 0, -eps), "+z": (0, 0, eps)}[key]
        # Inset the window field a little from the corners and the roof.
        inset = 0.6
        c = []
        for (px, py, pz) in corners:
            nx = px + off[0]
            nz = pz + off[2]
            if key in ("-x", "+x"):
                nz = nz + inset if pz == z0 else nz - inset
            else:
                nx = nx + inset if px == x0 else nx - inset
            ny = 0.9 if py == 0 else h - 0.8
            c.append((nx, ny, nz))
        w = length - 2 * inset
        hh = h - 1.7
        tile = TOWER_TILE if win_mat is not None and win_mat.name.startswith("City_Tower") else WIN_TILE
        cage.add_quad("Windows%d" % idx, c, toward, win_mat, coll, parent, (w / tile[0], hh / tile[1]))
        idx += 1
    return idx


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = cage.FPS
    scene.unit_settings.system = "METRIC"
    coll = bpy.data.collections.new("City")
    scene.collection.children.link(coll)
    c_court, c_street, c_blocks = cage.sub(coll, "Court"), cage.sub(coll, "Street"), cage.sub(coll, "Blocks")
    c_sky, c_props, c_pole = cage.sub(coll, "Sky"), cage.sub(coll, "Props"), cage.sub(coll, "Pole")

    court = cage.mat_tex("City_Court", TEX("city_court.png"))
    asphalt = cage.mat_tex("City_Asphalt", TEX("city_asphalt.png"))
    kerb = cage.mat_tex("City_Kerb", TEX("city_kerb.png"))
    walk = cage.mat_tex("City_Walk", TEX("beach_concrete.png"))
    brick = cage.mat_tex("City_Brick", TEX("city_brick.png"))
    windows = cage.mat_tex("City_Windows", TEX("city_windows.png"), emissive=True)
    tower = cage.mat_tex("City_Tower", TEX("city_tower.png"), emissive=True)
    sky = cage.mat_tex("City_Sky", TEX("city_sky.png"), emissive=True)
    tree = cage.mat_tex("City_Tree", TEX("city_tree.png"), alpha_clip=True, double_sided=True)
    mural = cage.mat_tex("City_Mural", TEX("city_mural.png"))
    flood = cage.mat_tex("City_Flood", TEX("city_flood.png"), alpha_clip=True, emissive=True)
    pole_tex = cage.mat_tex("City_Pole", TEX("beach_pole.png"))
    concrete = cage.mat_tex("City_Concrete", TEX("beach_concrete.png"))
    fence = cage.mat_tex("City_Fence", TEX("cage_mesh.png"), alpha_clip=True, double_sided=True)
    curb = cage.mat_flat("City_Curb", (150, 146, 140))
    apron = cage.mat_flat("City_Apron", (40, 52, 52), roughness=1.0)
    dark = cage.mat_flat("City_Dark", (30, 30, 34))
    steel = cage.mat_flat("City_Steel", (70, 72, 78), roughness=0.6)
    yellow = cage.mat_flat("City_Yellow", (232, 196, 74), roughness=0.9)
    # Smooth look on the big surfaces (the pixel-crisp fence and windows stay nearest).
    for m in (court, asphalt, sky, tree, mural, walk, concrete):
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE":
                n.interpolation = "Linear"

    root = cage.add_empty("City", c_court, None, (0, 0, 0))
    w = COURT_HALF_W
    # Plain blacktop out to the wall, under the lined slab.
    ap_x0, ap_x1 = ENC_X0 + WALL_T, ENC_X1 - WALL_T
    ap_w = ENC_HALF_W - WALL_T
    cage.add_quad("CourtApron", [(ap_x0, -0.002, -ap_w), (ap_x1, -0.002, -ap_w),
                                 (ap_x1, -0.002, ap_w), (ap_x0, -0.002, ap_w)],
                  (0, 1, 0), apron, c_court, root, ((ap_x1 - ap_x0) * 0.5, 2 * ap_w * 0.5))
    cage.add_quad("Court", [(COURT_X0, 0, -w), (COURT_X1, 0, -w), (COURT_X1, 0, w), (COURT_X0, 0, w)],
                  (0, 1, 0), court, c_court, root, (1.0, 1.0))
    # The ground everywhere else: dark wet asphalt out past the sky cylinder.
    cage.add_quad("Ground", [(-70, -0.01, -70), (70, -0.01, -70), (70, -0.01, 70), (-70, -0.01, 70)],
                  (0, 1, 0), asphalt, c_street, root, (70.0, 70.0))

    # Knee-high wall + chain-link fence: one loop, all four sides full height.
    corners = [(ENC_X0, -ENC_HALF_W), (ENC_X1, -ENC_HALF_W), (ENC_X1, ENC_HALF_W), (ENC_X0, ENC_HALF_W)]
    for k in range(4):
        (ax, az), (bx, bz) = corners[k], corners[(k + 1) % 4]
        length = math.hypot(bx - ax, bz - az)
        cx, cz = (ax + bx) / 2.0, (az + bz) / 2.0
        along_x = abs(bx - ax) > abs(bz - az)
        size = (length + WALL_T, WALL_H, WALL_T) if along_x else (WALL_T, WALL_H, length + WALL_T)
        cage.add_box("Wall%d" % k, size, (cx, WALL_H / 2.0, cz), concrete, c_court, root)
        cage.add_box("WallCap%d" % k, (size[0] + 0.06, 0.06, size[2] + 0.06), (cx, WALL_H + 0.03, cz), curb, c_court, root)
        rail = (length + 0.05, 0.05, 0.05) if along_x else (0.05, 0.05, length + 0.05)
        cage.add_box("FenceRail%d" % k, rail, (cx, FENCE_TOP, cz), dark, c_court, root)
        n_posts = max(2, int(round(length / 2.6)) + 1)
        for i in range(1, n_posts - 1):
            t = i / (n_posts - 1)
            px, pz = ax + (bx - ax) * t, az + (bz - az) * t
            cage.add_box("FencePost%d_%d" % (k, i), (0.08, FENCE_TOP - WALL_H + 0.1, 0.08), (px, (WALL_H + FENCE_TOP) / 2.0, pz), dark, c_court, root)
    for k, (px, pz) in enumerate(corners):
        cage.add_box("FenceCorner%d" % k, (0.10, FENCE_TOP - WALL_H + 0.1, 0.10), (px, (WALL_H + FENCE_TOP) / 2.0, pz), dark, c_court, root)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.verify()
    u = 0.0
    for k in range(4):
        (ax, az), (bx, bz) = corners[k], corners[(k + 1) % 4]
        length = math.hypot(bx - ax, bz - az)
        v0 = bm.verts.new(cage.s2b((ax, WALL_H, az)))
        v1 = bm.verts.new(cage.s2b((bx, WALL_H, bz)))
        v2 = bm.verts.new(cage.s2b((bx, FENCE_TOP, bz)))
        v3 = bm.verts.new(cage.s2b((ax, FENCE_TOP, az)))
        f = bm.faces.new((v0, v1, v2, v3))
        u0, u1 = u * 1.25, (u + length) * 1.25
        vv = (FENCE_TOP - WALL_H) * 1.25
        for loop, uvc in zip(f.loops, ((u0, 0.0), (u1, 0.0), (u1, vv), (u0, vv))):
            loop[uvl].uv = uvc
        u += length
    me = bpy.data.meshes.new("Fence")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(fence)
    fence_obj = bpy.data.objects.new("Fence", me)
    cage.link_obj(fence_obj, c_court, root, (0, 0, 0))

    # ---- The street behind the hoop: kerb, sidewalk, road with a dashed
    # centre line, the far sidewalk and kerb. StreetRig marks the lane line.
    L = STREET_HALF_LEN
    for name, x0, x1 in (("KerbNear", ENC_X1, WALK_X0), ("KerbFar", FAR_X1, FAR_X1 + 0.25)):
        cage.add_box(name, (x1 - x0, KERB_H, 2 * L), ((x0 + x1) / 2.0, KERB_H / 2.0, 0.0), kerb, c_street, root)
    cage.add_quad("Sidewalk", [(WALK_X0, KERB_H, -L), (WALK_X1, KERB_H, -L), (WALK_X1, KERB_H, L), (WALK_X0, KERB_H, L)],
                  (0, 1, 0), walk, c_street, root, ((WALK_X1 - WALK_X0) * 0.5, 2 * L * 0.5))
    cage.add_box("KerbRoad", (0.25, KERB_H, 2 * L), (WALK_X1 + 0.125, KERB_H / 2.0, 0.0), kerb, c_street, root)
    cage.add_quad("Road", [(ROAD_X0, 0.004, -L), (ROAD_X1, 0.004, -L), (ROAD_X1, 0.004, L), (ROAD_X0, 0.004, L)],
                  (0, 1, 0), asphalt, c_street, root, ((ROAD_X1 - ROAD_X0) * 0.4, 2 * L * 0.4))
    cage.add_box("KerbFarIn", (0.25, KERB_H, 2 * L), (FAR_X0 + 0.125, KERB_H / 2.0, 0.0), kerb, c_street, root)
    cage.add_quad("SidewalkFar", [(FAR_X0, KERB_H, -L), (FAR_X1, KERB_H, -L), (FAR_X1, KERB_H, L), (FAR_X0, KERB_H, L)],
                  (0, 1, 0), walk, c_street, root, ((FAR_X1 - FAR_X0) * 0.5, 2 * L * 0.5))
    n = 0
    z = -L + 1.0
    while z < L - 1.0:
        cage.add_box("LaneDash%d" % n, (0.12, 0.012, 2.0), (STREET_X, 0.01, z), yellow, c_street, root)
        n += 1
        z += 4.5
    cage.add_empty("StreetRig", c_street, root, (STREET_X, 0.0, 0.0))
    # Street lamps along the far sidewalk (their heads glow, unshaded).
    for i, lz in enumerate(range(-36, 37, 12)):
        lx = FAR_X1 - 0.35
        cage.add_box("LampPost%d" % i, (0.12, 5.2, 0.12), (lx, KERB_H + 2.6, lz), steel, c_street, root)
        cage.add_box("LampArm%d" % i, (1.4, 0.08, 0.08), (lx - 0.7, KERB_H + 5.2, lz), steel, c_street, root)
        cage.add_quad("FloodHeadL%d" % i, [(lx - 1.55, KERB_H + 4.95, lz - 0.28), (lx - 1.0, KERB_H + 4.95, lz - 0.28),
                                            (lx - 1.0, KERB_H + 4.95, lz + 0.28), (lx - 1.55, KERB_H + 4.95, lz + 0.28)],
                      (0, -1, 0), flood, c_street, root, (1.0, 1.0))

    # ---- The blocks: a row of tenements across the street, two towers behind
    # them, brick buildings flanking the court and one behind the shooter.
    win = 0
    row = [(-47, -35, 12.5), (-35, -23, 15.5), (-23, -12, 11.5), (-12, -1, 14.5), (-1, 10, 17.0), (10, 21, 12.0), (21, 33, 14.0), (33, 47, 11.0)]
    for i, (z0, z1, h) in enumerate(row):
        depth = 9.0 + (i % 3) * 1.5
        win = _block("Block%d" % i, BLOCK_X0, BLOCK_X0 + depth, z0 + 0.15, z1 - 0.15, h, brick, c_blocks, root,
                     windows=["-x"], win_mat=windows, win_idx=win)
        # A fire escape: a zigzag of thin landings on every other block.
        if i % 2 == 1:
            fz = (z0 + z1) / 2.0
            for k in range(1, int(h // 3.2)):
                cage.add_box("Escape%d_%d" % (i, k), (0.9, 0.06, 2.6), (BLOCK_X0 - 0.47, k * 3.2, fz), dark, c_blocks, root)
                cage.add_box("EscapeRail%d_%d" % (i, k), (0.04, 0.9, 2.6), (BLOCK_X0 - 0.9, k * 3.2 + 0.45, fz), dark, c_blocks, root)
    # The vacant lot between the far sidewalk and the row: a low wall with
    # a billboard hoarding, so the gap reads as a city block, not a void.
    cage.add_box("LotWall", (0.3, 1.8, 2 * L), (FAR_X1 + 2.0, 0.9, 0.0), brick, c_blocks, root)
    for i, bz in enumerate((-14.0, 6.0)):
        cage.add_box("Hoarding%d" % i, (0.25, 3.2, 7.0), (BLOCK_X0 - 2.0, 4.6, bz), dark, c_blocks, root)
        cage.add_quad("HoardingFace%d" % i, [(BLOCK_X0 - 2.14, 3.1, bz + 3.3), (BLOCK_X0 - 2.14, 3.1, bz - 3.3),
                                              (BLOCK_X0 - 2.14, 6.1, bz - 3.3), (BLOCK_X0 - 2.14, 6.1, bz + 3.3)],
                      (-1, 0, 0), mural, c_blocks, root, (1.0, 1.0))
        cage.add_box("HoardingLeg%d" % i, (0.2, 3.0, 0.2), (BLOCK_X0 - 2.0, 1.5, bz), steel, c_blocks, root)
    # Rooftop water tanks on three of them.
    for i, (z0, z1, h) in ((1, row[1]), (4, row[4]), (6, row[6])):
        bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=1.3, depth=2.6, location=(0, 0, 0))
        tank = bpy.context.active_object
        tank.name = tank.data.name = "Tank%d" % i
        tank.data.materials.append(dark)
        cage.link_obj(tank, c_blocks, root, cage.s2b((BLOCK_X0 + 5.0, h + 1.3 + 0.6, (z0 + z1) / 2.0 + 2.0)))
        cage.add_box("TankLegs%d" % i, (2.0, 0.6, 2.0), (BLOCK_X0 + 5.0, h + 0.3, (z0 + z1) / 2.0 + 2.0), dark, c_blocks, root)
    # Towers: glass, every face lit panes.
    for i, (x0, x1, z0, z1, h) in enumerate(((40.0, 52.0, -30.0, -17.0, 36.0), (42.0, 54.0, 14.0, 27.0, 44.0))):
        win = _block("Tower%d" % i, x0, x1, z0, z1, h, steel, c_blocks, root, uv_per_m=0.25,
                     windows=["-x", "-z", "+z"], win_mat=tower, win_idx=win)
    # Flanking brick buildings (their court-facing walls carry windows; the
    # left one a mural), and the low one behind the shooter.
    win = _block("Flank0", -9.0, 5.6, -16.5, -10.2, 12.0, brick, c_blocks, root, windows=["+z"], win_mat=windows, win_idx=win)
    win = _block("Flank1", -8.0, 5.6, 10.2, 16.5, 10.0, brick, c_blocks, root, windows=["-z"], win_mat=windows, win_idx=win)
    cage.add_quad("Mural", [(-6.5, 0.4, -10.17), (0.5, 0.4, -10.17), (0.5, 3.9, -10.17), (-6.5, 3.9, -10.17)],
                  (0, 0, 1), mural, c_blocks, root, (1.0, 1.0))
    win = _block("Back0", -22.0, -12.6, -11.0, 11.0, 8.0, brick, c_blocks, root, windows=["+x"], win_mat=windows, win_idx=win)

    # ---- Trees at the court's corners, billboarded by CityFx.
    for i, (x, z) in enumerate(((-12.3, -9.6), (-12.3, 9.6), (6.6, -10.6), (6.6, 10.6))):
        wdt, hgt = 3.2, 4.8
        trig = cage.add_empty("TreeRig%d" % i, c_props, root, (x, 0.0, z))
        cage.add_quad("Tree%d" % i, [(x, 0, z - wdt / 2), (x, 0, z + wdt / 2), (x, hgt, z + wdt / 2), (x, hgt, z - wdt / 2)],
                      (-1, 0, 0), tree, c_props, trig, (1.0, 1.0), origin=(x, 0.0, z))

    # ---- Floodlight poles at the shooter's end, heads aimed at the court.
    for i, fz in enumerate((-7.9, 7.9)):
        fx = -10.5
        cage.add_box("FloodPost%d" % i, (0.16, 8.0, 0.16), (fx, 4.0, fz), pole_tex, c_props, root)
        cage.add_box("FloodArm%d" % i, (1.2, 0.1, 0.1), (fx + 0.6, 8.0, fz), steel, c_props, root)
        cage.add_box("FloodBox%d" % i, (0.5, 0.36, 0.7), (fx + 1.3, 7.9, fz), dark, c_props, root)
        cage.add_quad("FloodHead%d" % i, [(fx + 1.56, 7.72, fz - 0.33), (fx + 1.56, 7.72, fz + 0.33),
                                          (fx + 1.56, 8.08, fz + 0.33), (fx + 1.56, 8.08, fz - 0.33)],
                      (1, 0, 0), flood, c_props, root, (1.0, 1.0))

    # ---- Sky: an open cylinder seen from inside (the beach's recipe).
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=SKY_R, depth=SKY_Y1 - SKY_Y0,
                                        end_fill_type="NOTHING", location=(0, 0, 0))
    skyobj = bpy.context.active_object
    skyobj.name = skyobj.data.name = "Sky"
    bm = bmesh.new()
    bm.from_mesh(skyobj.data)
    uvl = bm.loops.layers.uv.verify()
    for f in bm.faces:
        f.normal_flip()
        for loop in f.loops:
            co = loop.vert.co
            ang = math.atan2(-co.y, co.x)
            u = ((ang - math.pi / 2) / (2 * math.pi)) % 1.0
            v = (co.z + (SKY_Y1 - SKY_Y0) / 2) / (SKY_Y1 - SKY_Y0)
            loop[uvl].uv = (u, v)
    for f in bm.faces:
        us = [l[uvl].uv.x for l in f.loops]
        if max(us) - min(us) > 0.5:
            for l in f.loops:
                if l[uvl].uv.x < 0.5:
                    l[uvl].uv = (l[uvl].uv.x + 1.0, l[uvl].uv.y)
    bm.to_mesh(skyobj.data)
    bm.free()
    skyobj.data.materials.append(sky)
    cage.link_obj(skyobj, c_sky, root, (0, 0, (SKY_Y0 + SKY_Y1) / 2))

    # ---- The ground LED board on the wall's ledge (the beach's, no boombox).
    led_off = cage.mat_tex("City_LedOff", TEX("hoop_led_off.png"))
    sb_x, sb_y, sb_z = ENC_X1 - 0.115, WALL_H + 0.06, -0.72
    rig = cage.add_empty("ScoreboardRig", c_props, root, (sb_x, sb_y, sb_z))
    cage.add_box("ScoreboardBase", (0.16, 0.06, 0.70), (0.0, 0.03, 0.0), steel, c_props, rig)
    cage.add_box("ScoreboardBody", (0.14, 0.30, 0.66), (0.0, 0.21, 0.0), dark, c_props, rig)
    cage.add_quad("LedFace", [(-0.072, 0.165, -0.30), (-0.072, 0.165, 0.30), (-0.072, 0.265, 0.30), (-0.072, 0.265, -0.30)],
                  (-1, 0, 0), led_off, c_props, rig, (1.0, 1.0), origin=(0, 0, 0))
    cage.add_box("ScoreboardTrim", (0.15, 0.02, 0.68), (0.0, 0.365, 0.0), curb, c_props, rig)

    # Pole: a top-level empty Godot positions behind the board.
    pole = cage.add_empty("Pole", c_pole, None, (POLE_X, 0.0, 0.0))
    cage.add_box("PoleSleeve", (0.16, 0.30, 0.16), (0, 0.15, 0), dark, c_pole, pole)
    cage.add_box("PolePost", (0.10, 3.4, 0.10), (0, 1.7, 0), pole_tex, c_pole, pole)
    cage.add_box("PoleCap", (0.12, 0.03, 0.12), (0, 3.415, 0), dark, c_pole, pole)

    meshes = [o for o in coll.all_objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.shade_flat()
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.select_all(action="DESELECT")

    # ScorePop: the board hops on every make (CourtGeometry.play_arena("ScorePop")).
    for t, sz, sy in [(0.0, 1.0, 1.0), (0.06, 1.12, 0.86), (0.16, 0.94, 1.10), (0.28, 1.03, 0.97), (0.4, 1.0, 1.0)]:
        rig.scale = (sz, sz, sy)
        rig.keyframe_insert("scale", frame=1 + int(round(t * cage.FPS)))
    rig.animation_data.action.name = "ScorePop"
    cage.to_nla(rig, rig.animation_data.action, "ScorePop")
    return coll


if __name__ == "__main__" and bpy.app.background:
    if os.path.exists(BLEND_PATH) and "--force" not in sys.argv:
        print("REFUSING: %s exists (hand edits live there). Re-run with `-- --force` to rebuild." % BLEND_PATH)
        sys.exit(0)
    c = build()
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    cage.export_glb(c, GLB_PATH)
    tris = 0
    for o in c.all_objects:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
    print("OBJECTS", len(c.all_objects), "TRIS", tris)
    print("SAVED", BLEND_PATH)
