"""Build the city arena: an inner-city cage court at dusk — a teal blacktop
slab inside a chain-link fence, a two-lane street behind the hoop's fence
(cars drive it: game/view/city_fx.gd), real-scale city blocks beyond it from
Sam Grady's Low Poly Buildings Pack (art/third_party/buildings, CC BY 4.0:
low-rises across the street, mid-rises behind, two towers at the back, and
low-rises flanking the court and behind the shooter), hoardings on the
vacant lot, street trees, floodlight poles, a dusk sky cylinder and the
hoop's in-ground pole.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_city.py

Produces  art/blender/city.blend        (source, ignored by Godot) and
          assets/arena/city/city.glb    (game export, Y-up, transforms applied).

Sim frame (like the cage and the beach): origin at the release plane on the
floor, +x toward the hoop and the street, +z shooter's right, y up;
blender (x, y, z) = (sim x, -sim z, sim y). Numbers are SIM metres.

Runtime contract (game/court/court_geometry.gd + game/view/city_fx.gd): the
empty `Pole` is placed by Godot behind the board; `StreetRig` (an empty on
the street's centre line) gives CityFx the lane line; every `Building*` mesh
gets the facade shader (dusk + lit panes switching on and off); `FloodHead*` quads
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
STREET_HALF_LEN = 100.0
BLOCK_X0 = 22.0                            # the frontage row starts here (a vacant lot between)
# Real-scale blocks (the towers stand 118 m tall, 300 m out): a big sky.
SKY_R, SKY_Y0, SKY_Y1 = 300.0, -3.0, 240.0
GROUND = 320.0
PACK = os.path.join(ROOT, "art", "third_party", "buildings")
# The pack's buildings: file → (x extent, height, z extent) in metres, from
# their bounding boxes (CopperCube exports, Y-up, centred in x/z).
PACK_DIMS = {
    1: (70, 41, 90), 2: (140, 118, 95), 3: (90, 31, 70), 4: (90, 61, 70), 5: (60, 41, 60),
    6: (81, 20, 26), 7: (60, 15, 30), 8: (30, 27, 30), 9: (120, 28, 30), 10: (70, 16, 20), 11: (80, 85, 60),
}
# Where each stands (sim metres, footprint centre on the ground) and its yaw
# (degrees about y; the model's x extent runs along sim x — toward the hoop —
# at yaw 0, so the frontage row turns 90 to lay its long run along the street).
# Rows: A the frontage across the street (x 22+), B the mid-rises (x 60+),
# C the skyline (x 140+), plus the flanks beside the court and the block
# behind the shooter.
LAYOUT = [
    # Row A, across the street: the grand stone block dead ahead (its ornate
    # facade, 41 m, clears the fence line from the key), shops and a brick
    # office down the street either side, long runs along z.
    ("Building01", 1, (66.0, 0.0), 0.0), ("Building10", 10, (32.0, -85.0), 90.0), ("Building07", 7, (37.0, 75.0), 90.0),
    # Row B: the office block, small blocks down the street.
    ("Building09", 9, (110.0, -100.0), 90.0), ("Building05", 5, (70.0, 150.0), 0.0), ("Building08", 8, (70.0, -170.0), 0.0),
    ("Building06", 6, (60.0, 225.0), 90.0),
    # Row C: the skyline — the towers close enough to rise above the frontage.
    ("Building11", 11, (150.0, -30.0), 0.0), ("Building02", 2, (170.0, 70.0), 0.0), ("Building04", 4, (150.0, -180.0), 0.0),
    ("Building03", 3, (150.0, 170.0), 0.0),
    # The flanks beside the court and the block behind the shooter.
    ("Building12", 7, (-25.0, -28.0), 180.0), ("Building13", 10, (-30.0, 22.0), 0.0), ("Building14", 6, (-60.0, 0.0), 90.0),
]


def _building(name, index, mat, coll, parent, sim_xz, yaw_deg):
    """Import one pack OBJ (Y-up metres), shift its CopperCube v (−1..0) into
    0..1, give it the shared facade material, put its origin at the footprint
    centre on the ground and stand it at `sim_xz` turned by `yaw_deg`."""
    path = os.path.join(PACK, "building_%02d_smooth.obj" % index)
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=path, forward_axis="NEGATIVE_Z", up_axis="Y")
    new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    if not new:
        raise RuntimeError("nothing imported from %s" % path)
    bpy.ops.object.select_all(action="DESELECT")
    for o in new:
        o.select_set(True)
    bpy.context.view_layer.objects.active = new[0]
    if len(new) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = obj.data.name = name
    # The importer keeps its Y-up → Z-up conversion as a rotation on the
    # OBJECT; bake it into the vertices before measuring the footprint (or the
    # yaw below would replace it and stand every building on its side).
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = obj.data
    me.materials.clear()
    me.materials.append(mat)
    for poly in me.polygons:
        poly.material_index = 0
    bm = bmesh.new()
    bm.from_mesh(me)
    uvl = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for loop in f.loops:
            u, v = loop[uvl].uv
            loop[uvl].uv = (u, v + 1.0)
    # Origin: footprint centre, ground level (blender z is up after import).
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    cx, cy, z0 = (min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0, min(zs)
    for v in bm.verts:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= z0
    bm.to_mesh(me)
    bm.free()
    cage.link_obj(obj, coll, parent, cage.s2b((sim_xz[0], 0.0, sim_xz[1])))
    obj.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    return obj


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
    facade = cage.mat_tex("City_Facade", TEX("city_facades.png"))
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
    for m in (court, asphalt, sky, tree, mural, walk, concrete, facade):
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
    cage.add_quad("Ground", [(-GROUND, -0.01, -GROUND), (GROUND, -0.01, -GROUND), (GROUND, -0.01, GROUND), (-GROUND, -0.01, GROUND)],
                  (0, 1, 0), asphalt, c_street, root, (GROUND, GROUND))

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

    # ---- The blocks: Sam Grady's pack at real scale (see LAYOUT). Nothing
    # stands between the far sidewalk and the frontage: the facades ARE the view.
    for name, index, xz, yaw in LAYOUT:
        _building(name, index, facade, c_blocks, root, xz, yaw)

    # ---- Trees at the court's corners, billboarded by CityFx.
    for i, (x, z) in enumerate(((-12.3, -9.6), (-12.3, 9.6), (6.6, -10.6), (6.6, 10.6))):
        wdt, hgt = 3.2, 4.8
        trig = cage.add_empty("TreeRig%d" % i, c_props, root, (x, 0.0, z))
        cage.add_quad("Tree%d" % i, [(x, 0, z - wdt / 2), (x, 0, z + wdt / 2), (x, hgt, z + wdt / 2), (x, hgt, z - wdt / 2)],
                      (-1, 0, 0), tree, c_props, trig, (1.0, 1.0), origin=(x, 0.0, z))

    # ---- Floodlight poles at all four corners of the court, heads aimed at
    # it (CityFx hangs a SpotLight3D on every FloodHead* — the court's light).
    for i, (fx, fz, toward) in enumerate(((-10.5, -7.9, 1), (-10.5, 7.9, 1), (7.0, -9.4, -1), (7.0, 9.4, -1))):
        cage.add_box("FloodPost%d" % i, (0.16, 8.0, 0.16), (fx, 4.0, fz), pole_tex, c_props, root)
        cage.add_box("FloodArm%d" % i, (1.2, 0.1, 0.1), (fx + 0.6 * toward, 8.0, fz), steel, c_props, root)
        cage.add_box("FloodBox%d" % i, (0.5, 0.36, 0.7), (fx + 1.3 * toward, 7.9, fz), dark, c_props, root)
        hx = fx + 1.56 * toward
        cage.add_quad("FloodHead%d" % i, [(hx, 7.72, fz - 0.33), (hx, 7.72, fz + 0.33), (hx, 8.08, fz + 0.33), (hx, 8.08, fz - 0.33)],
                      (toward, 0, 0), flood, c_props, root, (1.0, 1.0))

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
