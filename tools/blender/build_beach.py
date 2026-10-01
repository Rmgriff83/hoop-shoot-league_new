"""Build the beach arena: an outdoor court slab facing the ocean, sand, a
subdivided ocean plane (Godot's ocean.gdshader moves its vertices), a foam
strip the tide slides, a sunset sky panel, palm billboards and the hoop's
in-ground pole.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_beach.py

Produces  art/blender/beach.blend         (source, ignored by Godot) and
          assets/arena/beach/beach.glb    (game export, Y-up, transforms applied).

Sim frame (like the cage): origin at the release plane on the floor, +x toward
the hoop and the ocean, +z shooter's right, y up; blender (x, y, z) =
(sim x, -sim z, sim y). Numbers are SIM metres.

Runtime contract (game/court/court_geometry.gd): the empty `Pole` is placed by
Godot at (board_x + 0.3, 0, hoop_z); `Ocean` gets the wave shader and `Shore`
the tide (game/view/beach_fx.gd). `Beach` is the static root / shake handle.

CREATOR script: refuses to overwrite an existing beach.blend unless run with
`-- --force`. Never touches cage.blend or hoop.blend.
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
BLEND_PATH = os.path.join(ROOT, "art", "blender", "beach.blend")
GLB_PATH = os.path.join(ROOT, "assets", "arena", "beach", "beach.glb")
TEX = lambda name: os.path.join(ROOT, "assets", "textures", name)

BEACH_DIST = 2.9 * 1.175                  # SimGeometry.BEACH_DIST
BOARD_X = BEACH_DIST + 0.3796
POLE_X = BOARD_X + 0.3                    # CourtGeometry.CROSSBAR_X_OFF
COURT_X0, COURT_X1, COURT_HALF_W = -9.9, 4.3, 7.6
SAND_X0, SAND_X1 = 4.5, 18.0
# Knee-high concrete wall + chain-link fence enclosing the whole court, set
# back from the baseline so the hoop has room; rectangle x ENC_X0..ENC_X1, z ±ENC_HALF_W.
WALL_T = 0.25
WALL_H = 0.45
FENCE_TOP = 3.6
# Per side, in `corners` order: k=0 is the z=-8.6 run, k=1 the BACK (x=+5.7,
# behind the hoop), k=2 the z=+8.6 run, k=3 behind the shooter. The back is
# shorter so the sea shows over it. It cannot go below ~3.1: the league
# standings banner hangs there at y 2.35 with a 1.35 m height, so its top edge
# is 3.025 and a lower fence would leave it floating.
FENCE_TOPS = [FENCE_TOP, 3.15, FENCE_TOP, FENCE_TOP]
ENC_X0, ENC_X1, ENC_HALF_W = -11.2, 5.7, 8.6
SHORE_X0, SHORE_X1 = 12.5, 13.6
OCEAN_X0, OCEAN_X1 = 13.0, 75.0       # runs out past the sky cylinder (r 60) so no seam shows
WIDE = 45.0
OCEAN_HALF_W = 75.0
SKY_R, SKY_Y0, SKY_Y1 = 60.0, -3.0, 50.0


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = cage.FPS
    scene.unit_settings.system = "METRIC"
    coll = bpy.data.collections.new("Beach")
    scene.collection.children.link(coll)
    c_court, c_sand, c_sea = cage.sub(coll, "Court"), cage.sub(coll, "Sand"), cage.sub(coll, "Sea")
    c_sky, c_props, c_pole = cage.sub(coll, "Sky"), cage.sub(coll, "Props"), cage.sub(coll, "Pole")

    court = cage.mat_tex("Beach_Court", TEX("beach_court.png"))
    sand = cage.mat_tex("Beach_Sand", TEX("beach_sand.png"))
    water = cage.mat_tex("Beach_Water", TEX("beach_water.png"), double_sided=True)
    foam = cage.mat_tex("Beach_Foam", TEX("beach_foam.png"), double_sided=True)
    sky = cage.mat_tex("Beach_Sky", TEX("beach_sky.png"), emissive=True)
    palm = cage.mat_tex("Beach_Palm", TEX("beach_palm.png"), alpha_clip=True, double_sided=True)
    pole_tex = cage.mat_tex("Beach_Pole", TEX("beach_pole.png"))
    concrete = cage.mat_tex("Beach_Concrete", TEX("beach_concrete.png"))
    fence = cage.mat_tex("Beach_Fence", TEX("cage_mesh.png"), alpha_clip=True, double_sided=True)
    curb = cage.mat_flat("Beach_Curb", (150, 146, 140))
    # The apron: plain blacktop filling the gap between the lined slab and the
    # wall. Sampled from beach_court.png's asphalt tone so the seam disappears.
    apron = cage.mat_flat("Beach_Apron", (58, 56, 60), roughness=1.0)
    dark = cage.mat_flat("Beach_Dark", (40, 38, 40))
    # Smooth look: linear sampling on every beach skin (the cage stays pixel-crisp).
    for m in (court, sand, water, foam, sky, palm, pole_tex, concrete):
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE":
                n.interpolation = "Linear"
    for attr, val in (("blend_method", "BLEND"),):
        try:
            setattr(foam, attr, val)
        except Exception:
            pass

    root = cage.add_empty("Beach", c_court, None, (0, 0, 0))
    w = COURT_HALF_W
    # Plain blacktop out to the wall, UNDER the lined slab, so sand no longer
    # reaches into the court. The Court quad itself must not grow: its texture
    # is authored for exactly 14.2 x 15.2 m with the rim at x 3.4075, so
    # stretching it would slide every painted line off the hoop.
    ap_x0, ap_x1 = ENC_X0 + WALL_T, ENC_X1 - WALL_T
    ap_w = ENC_HALF_W - WALL_T
    cage.add_quad("CourtApron", [(ap_x0, -0.002, -ap_w), (ap_x1, -0.002, -ap_w),
                                 (ap_x1, -0.002, ap_w), (ap_x0, -0.002, ap_w)],
                  (0, 1, 0), apron, c_court, root, ((ap_x1 - ap_x0) * 0.5, 2 * ap_w * 0.5))
    cage.add_quad("Court", [(COURT_X0, 0, -w), (COURT_X1, 0, -w), (COURT_X1, 0, w), (COURT_X0, 0, w)],
                  (0, 1, 0), court, c_court, root, (1.0, 1.0))
    # Knee-high wall + chain-link fence around the whole court: ONE continuous
    # loop. The fence is a single strip mesh (4 faces sharing corner vertices),
    # the rail a loop of boxes overlapping at the corners, one post per corner.
    corners = [(ENC_X0, -ENC_HALF_W), (ENC_X1, -ENC_HALF_W), (ENC_X1, ENC_HALF_W), (ENC_X0, ENC_HALF_W)]
    # Wall: four boxes, each extended by the wall thickness so corners are solid.
    for k in range(4):
        (ax, az), (bx, bz) = corners[k], corners[(k + 1) % 4]
        length = math.hypot(bx - ax, bz - az)
        cx, cz = (ax + bx) / 2.0, (az + bz) / 2.0
        along_x = abs(bx - ax) > abs(bz - az)
        size = (length + WALL_T, WALL_H, WALL_T) if along_x else (WALL_T, WALL_H, length + WALL_T)
        cage.add_box("Wall%d" % k, size, (cx, WALL_H / 2.0, cz), concrete, c_court, root)
        cage.add_box("WallCap%d" % k, (size[0] + 0.06, 0.06, size[2] + 0.06), (cx, WALL_H + 0.03, cz), curb, c_court, root)
        top = FENCE_TOPS[k]
        rail = (length + 0.05, 0.05, 0.05) if along_x else (0.05, 0.05, length + 0.05)
        cage.add_box("FenceRail%d" % k, rail, (cx, top, cz), dark, c_court, root)
        # Intermediate posts (corners get theirs below, once).
        n_posts = max(2, int(round(length / 2.6)) + 1)
        for i in range(1, n_posts - 1):
            t = i / (n_posts - 1)
            px, pz = ax + (bx - ax) * t, az + (bz - az) * t
            cage.add_box("FencePost%d_%d" % (k, i), (0.08, top - WALL_H + 0.1, 0.08), (px, (WALL_H + top) / 2.0, pz), dark, c_court, root)
    # A corner belongs to two runs; it takes the TALLER so the side fence does
    # not dip where it meets the shortened back.
    for k, (px, pz) in enumerate(corners):
        ctop = max(FENCE_TOPS[k], FENCE_TOPS[(k - 1) % 4])
        cage.add_box("FenceCorner%d" % k, (0.10, ctop - WALL_H + 0.1, 0.10), (px, (WALL_H + ctop) / 2.0, pz), dark, c_court, root)
    # The mesh: FOUR independent faces. They used to share one top vertex ring,
    # which is why every side had to be the same height — lowering the back
    # would have dragged the ends of both side runs down with it.
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.verify()
    u = 0.0
    for k in range(4):
        (ax, az), (bx, bz) = corners[k], corners[(k + 1) % 4]
        length = math.hypot(bx - ax, bz - az)
        top = FENCE_TOPS[k]
        v0 = bm.verts.new(cage.s2b((ax, WALL_H, az)))
        v1 = bm.verts.new(cage.s2b((bx, WALL_H, bz)))
        v2 = bm.verts.new(cage.s2b((bx, top, bz)))
        v3 = bm.verts.new(cage.s2b((ax, top, az)))
        f = bm.faces.new((v0, v1, v2, v3))
        u0, u1 = u * 1.25, (u + length) * 1.25
        vv = (top - WALL_H) * 1.25   # per-face, so the mesh cells stay square
        for loop, uvc in zip(f.loops, ((u0, 0.0), (u1, 0.0), (u1, vv), (u0, vv))):
            loop[uvl].uv = uvc
        u += length
    me = bpy.data.meshes.new("Fence")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(fence)
    fence_obj = bpy.data.objects.new("Fence", me)
    cage.link_obj(fence_obj, c_court, root, (0, 0, 0))

    # Sand everywhere around the court (the slab sits 5 mm above it), out to the shoreline.
    cage.add_quad("Sand", [(-40, -0.005, -WIDE), (SAND_X1, -0.005, -WIDE), (SAND_X1, -0.005, WIDE), (-40, -0.005, WIDE)],
                  (0, 1, 0), sand, c_sand, root, ((SAND_X1 + 40) * 0.67, 2 * WIDE * 0.67))

    # Ocean: a subdivided grid the shader displaces. UV u = 0 at the shore edge.
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=96, y_subdivisions=48, size=1.0, location=(0, 0, 0))
    ocean = bpy.context.active_object
    ocean.name = ocean.data.name = "Ocean"
    ocean.scale = (OCEAN_X1 - OCEAN_X0, 2 * OCEAN_HALF_W, 1.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ocean.data.materials.append(water)
    cage.link_obj(ocean, c_sea, root, cage.s2b(((OCEAN_X0 + OCEAN_X1) / 2, 0.02, 0)))

    cage.add_quad("Shore", [(SHORE_X0, 0.04, -WIDE), (SHORE_X0, 0.04, WIDE), (SHORE_X1, 0.04, WIDE), (SHORE_X1, 0.04, -WIDE)],
                  (0, 1, 0), foam, c_sea, root, (2 * WIDE, 1.0))

    # Sky: an open cylinder seen from inside so the dusk gradient is there in every
    # direction. The texture's warm right edge (u→1) is placed at the east (+z),
    # where the key light is.
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
            ang = math.atan2(-co.y, co.x)            # sim azimuth: 0 = +x (ahead), +z = east
            u = ((ang - math.pi / 2) / (2 * math.pi)) % 1.0   # east (+z) -> u ≈ 0/1 seam (the glow)
            v = (co.z + (SKY_Y1 - SKY_Y0) / 2) / (SKY_Y1 - SKY_Y0)
            loop[uvl].uv = (u, v)
    # Fix the seam: loops that wrapped (u≈0 next to u≈1) get u+1 so the face doesn't stretch.
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

    # Palms all around: the near/far pairs ahead, a pair beside each baseline corner,
    # and a pair behind the shooter's flanks. Each palm is a quad under its own
    # `PalmRig` empty at the trunk base, so BeachFx can turn it to face the camera.
    for i, (x, z, wdt, hgt) in enumerate(((6.5, -3.0, 2.8, 4.4), (6.5, 3.0, 2.8, 4.4),      # just outside the back fence
                                           (8.8, -4.8, 2.4, 3.8), (8.8, 4.8, 2.4, 3.8),
                                           (3.5, -9.2, 2.6, 4.2), (3.5, 9.2, 2.6, 4.2),
                                           (-4.0, -9.4, 2.4, 3.6), (-4.0, 9.4, 2.4, 3.6))):
        prig = cage.add_empty("PalmRig%d" % i, c_props, root, (x, 0.0, z))
        cage.add_quad("Palm%d" % i, [(x, 0, z - wdt / 2), (x, 0, z + wdt / 2), (x, hgt, z + wdt / 2), (x, hgt, z - wdt / 2)],
                      (-1, 0, 0), palm, c_props, prig, (1.0, 1.0), origin=(x, 0.0, z))

    led_off = cage.mat_tex("Beach_LedOff", TEX("hoop_led_off.png"))
    # An old-school boombox sits on the wall's ledge (left of the pole line); the
    # reader board sits on top of it.
    ledge_y = WALL_H + 0.06
    bb_w, bb_h, bb_d = 0.70, 0.28, 0.22
    bb_x, bb_z = ENC_X1 - 0.115, -0.72          # back edge just in front of the fence line
    bb_body = cage.mat_flat("Boombox_Body", (44, 44, 48), roughness=0.7)
    bb_face = cage.mat_flat("Boombox_Face", (96, 98, 104), roughness=0.8)
    bb_grille = cage.mat_flat("Boombox_Grille", (22, 22, 24), roughness=1.0)
    bb_ring = cage.mat_flat("Boombox_Ring", (150, 150, 158), roughness=0.5)
    bb_red = cage.mat_flat("Boombox_Red", (220, 60, 50), roughness=0.6)
    cage.add_box("Boombox", (bb_d, bb_h, bb_w), (bb_x, ledge_y + bb_h / 2.0, bb_z), bb_body, c_props, root)
    face_x = bb_x - bb_d / 2.0 - 0.006
    cage.add_box("BoomboxFace", (0.012, bb_h - 0.04, bb_w - 0.04), (face_x, ledge_y + bb_h / 2.0, bb_z), bb_face, c_props, root)
    for i, dz in enumerate((-0.23, 0.23)):
        # Speaker: a short cylinder poking out of the face, with a bright ring.
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.095, depth=0.014, location=(0, 0, 0))
        spk = bpy.context.active_object
        spk.name = spk.data.name = "BoomboxSpeaker%d" % i
        spk.rotation_euler = (0.0, math.pi / 2, 0.0)       # axis along blender x = sim x
        spk.data.materials.append(bb_grille)
        cage.link_obj(spk, c_props, root, cage.s2b((face_x - 0.01, ledge_y + bb_h / 2.0 - 0.01, bb_z + dz)))
        bpy.ops.mesh.primitive_torus_add(major_radius=0.095, minor_radius=0.008, major_segments=16, minor_segments=4, location=(0, 0, 0))
        ring = bpy.context.active_object
        ring.name = ring.data.name = "BoomboxRing%d" % i
        ring.rotation_euler = (0.0, math.pi / 2, 0.0)
        ring.data.materials.append(bb_ring)
        cage.link_obj(ring, c_props, root, cage.s2b((face_x - 0.014, ledge_y + bb_h / 2.0 - 0.01, bb_z + dz)))
    cage.add_box("BoomboxDeck", (0.01, 0.07, 0.16), (face_x - 0.006, ledge_y + bb_h / 2.0 + 0.02, bb_z), bb_grille, c_props, root)
    cage.add_box("BoomboxLed", (0.01, 0.015, 0.015), (face_x - 0.008, ledge_y + bb_h - 0.05, bb_z + 0.1), bb_red, c_props, root)
    ant = cage.add_box("BoomboxAntenna", (0.012, 0.42, 0.012), (bb_x + 0.04, ledge_y + bb_h + 0.2, bb_z - 0.3), bb_ring, c_props, root)
    ant.rotation_euler = (0.35, 0.0, 0.0)
    sb_x, sb_y, sb_z = bb_x, ledge_y + bb_h, bb_z          # straight on the boombox's top
    rig = cage.add_empty("ScoreboardRig", c_props, root, (sb_x, sb_y, sb_z))
    cage.add_box("ScoreboardBody", (0.14, 0.30, 0.66), (0.0, 0.15, 0.0), dark, c_props, rig)
    cage.add_quad("LedFace", [(-0.072, 0.105, -0.30), (-0.072, 0.105, 0.30), (-0.072, 0.205, 0.30), (-0.072, 0.205, -0.30)],
                  (-1, 0, 0), led_off, c_props, rig, (1.0, 1.0), origin=(0, 0, 0))
    cage.add_box("ScoreboardTrim", (0.15, 0.02, 0.68), (0.0, 0.305, 0.0), curb, c_props, rig)

    # ---- Tourists lounging on the sand between the fence and the shore (clear
    # of the palm trunks). Blocky N64 people on towels; two groups have an
    # umbrella, one a cooler. `Arm%d` empties let BeachFx wave an arm now and
    # then; `Umbrella%d` rigs sway gently. Everything is relative to its
    # `TouristRig%d` so the group can be turned as one.
    c_people = cage.sub(coll, "Tourists")
    towels = [cage.mat_flat("Towel0", (220, 70, 60)), cage.mat_flat("Towel1", (60, 120, 210)), cage.mat_flat("Towel2", (240, 200, 80))]
    umb_a = cage.mat_flat("UmbrellaA", (240, 240, 235))
    umb_b = cage.mat_flat("UmbrellaB", (220, 60, 50))
    cooler_m = cage.mat_flat("Cooler", (40, 90, 180))
    for i, (x, z, yaw, umbrella, has_cooler) in enumerate(((10.3, -6.4, 0.35, True, False), (10.8, 1.4, -0.2, True, True), (9.9, 6.6, 0.15, False, False))):
        rig = cage.add_empty("TouristRig%d" % i, c_people, root, (x, 0.0, z))
        rig.rotation_euler = (0.0, 0.0, yaw)
        cage.add_quad("Towel%d" % i, [(x - 0.95, 0.008, z - 0.5), (x + 0.95, 0.008, z - 0.5), (x + 0.95, 0.008, z + 0.5), (x - 0.95, 0.008, z + 0.5)],
                      (0, 1, 0), towels[i], c_people, rig, (1.0, 1.0), origin=(x, 0.0, z))
        # Nobody on the towels (Ross, 2026-09-30): the towels, umbrellas and
        # cooler stay as an empty pitch — the loungers' blocky bodies read
        # wrong from the court.
        if umbrella:
            urig = cage.add_empty("Umbrella%d" % i, c_people, rig, (0.2, 0.0, -0.75))
            cage.add_box("UmbPole%d" % i, (0.04, 2.0, 0.04), (0.0, 1.0, 0.0), cage.mat_flat("UmbPole", (120, 110, 100)), c_people, urig)
            bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=1.15, radius2=0.0, depth=0.5, location=(0, 0, 0))
            cone = bpy.context.active_object
            cone.name = cone.data.name = "UmbCanopy%d" % i
            cone.data.materials.append(umb_a)
            cone.data.materials.append(umb_b)
            for pi, poly in enumerate(cone.data.polygons):
                poly.material_index = pi % 2 if len(poly.vertices) == 3 else 0
            cage.link_obj(cone, c_people, urig, cage.s2b((0.0, 2.05, 0.0)))
        if has_cooler:
            cage.add_box("Cooler%d" % i, (0.4, 0.3, 0.28), (-0.95, 0.15, 0.75), cooler_m, c_people, rig)

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

    # ScorePop: the cabinet hops and squashes on every make (one NLA track = one
    # Godot clip, played by CourtGeometry.play_arena("ScorePop")).
    for t, sz, sy in [(0.0, 1.0, 1.0), (0.06, 1.12, 0.86), (0.16, 0.94, 1.10), (0.28, 1.03, 0.97), (0.4, 1.0, 1.0)]:
        rig.scale = (sz, sz, sy)   # blender z = sim y
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
        d = tuple(round(x, 3) for x in o.dimensions) if o.type == "MESH" else "-"
        print("OBJ %-12s parent=%-7s loc=%s dims=%s" % (
            o.name, o.parent.name if o.parent else "-", tuple(round(x, 3) for x in o.location), d))
    print("TRIS", tris)
    print("SAVED", BLEND_PATH)
