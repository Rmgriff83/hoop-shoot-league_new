"""Build the park arena (Ross's "Park Area Concept", 2026-10-15): a
neighbourhood park court on a winter morning, laid out from the photo —
the asphalt slab on a strip of lawn, a wide parking lot crossing the view,
a road running off into the distance, a path curving away to the left, a
concrete pad and a notice post on the right, bollards, light poles, a
ballfield fence, low buildings on the horizon, lying snow (plough piles at
the court's edges, kerbside piles, patches that survived in the hollows,
roof caps), a far snow disc, a sky dome and a repeating treeline ring.

NOT here: the trees, the litter and the parked cars (game/view/park_fx.gd
instances the PSX pack from data/park_layout.json at runtime) and the hoop
(assets/hoops/park, which brings its own pole). The falling snow is a
shader at runtime.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_park.py -- --force

Produces  art/blender/park.blend        (source, ignored by Godot) and
          assets/arena/park/park.glb    (game export, Y-up, transforms applied).

Sim frame (like the city): origin at the release plane on the floor, +x
toward the hoop, +z the shooter's right, y up; blender (x, y, z) =
(sim x, -sim z, sim y). Numbers are SIM metres. The slab's edges and the
pole-foot drift MUST match SimGeometry.park() (the soft walls, the prop box).

Runtime contract (game/court/court_geometry.gd + game/view/park_fx.gd):
`Sky` (unshaded; ParkFx puts the sky shader on it), `TreelineRing`
(alpha-cut strip), `NoticeBoard` (the league banner's host, placed by the
ArenaSet's league_banner_* fields), `Park` the static root.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_cage as cage        # noqa: E402  (helpers: s2b, add_quad, add_box, mat_tex, ...)

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "park.blend")
GLB_PATH = os.path.join(ROOT, "assets", "arena", "park", "park.glb")
TEX = lambda name: os.path.join(ROOT, "assets", "textures", name)  # noqa: E731

# ---- the layout, mirrored from core/physics/sim_geometry.gd park() -------------
PARK_DIST = 3.70
COURT_X0, COURT_X1, COURT_HALF_W = -7.0, 6.80, 6.0      # the slab; its sides are the sim's soft walls
FENCE_X = 6.20                                           # SimGeometry.PARK_FENCE_X: the slab runs 0.6 m past it
FENCE_POSTS = [-6.0, -3.6, -1.2, 1.2, 3.6, 6.0]
FENCE_RAILS = [0.20, 0.60, 1.00]
STRIPES = [16.1, 18.7, 21.3]                             # the worn bay stripes on the lot
DRIFT = (4.05, 4.50, 0.18, 0.40)                        # the pole-foot drift = the sim's prop box
SKY_R = 400.0
RING_R, RING_H, RING_C = 95.0, 11.0, (8.0, 4.3, -4.0)

_seed = 7


def rng():
    global _seed
    _seed = (_seed * 16807) % 2147483647
    return _seed / 2147483647


def R(a, b):
    return a + rng() * (b - a)


def noise(x, z):
    return math.sin(x * .21 + math.sin(z * .13) * 1.7) * .5 + math.sin(z * .17 - x * .09 + 1.3) * .35 + math.sin((x + z) * .41) * .15


def on_court(x, z, pad=0.0):
    return x > -7.2 - pad and x < 7.0 + pad and abs(z) < 6.4 + pad


def in_lot(x, z, pad=0.0):
    return (14 - pad < x < 23 + pad and -30.5 - pad < z < 7.5 + pad) or (23 - pad < x < 67 and abs(z + 15) < 3.25 + pad)


def clear(x, z, pad=1.0):
    return not on_court(x, z, pad) and not in_lot(x, z, pad)


# ---- helpers ----------------------------------------------------------------------


def add_cyl(name, radius, height, sim_center, mat, coll, parent, verts=8):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=height, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = o.data.name = name
    o.data.materials.append(mat)
    cage.link_obj(o, coll, parent, cage.s2b(sim_center))
    return o


def quad_xz(name, cx, cz, w, d, y, yaw, mat, coll, parent, repeat):
    """A ground quad w (along x) by d (along z) centred on (cx, cz), yawed about y."""
    c, s = math.cos(yaw), math.sin(yaw)
    pts = []
    for dx, dz in ((-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)):
        pts.append((cx + dx * c - dz * s, y, cz + dx * s + dz * c))
    return cage.add_quad(name, pts, (0, 1, 0), mat, coll, parent, uv_repeat=repeat)


class MeshMerge:
    """Boxes (jittered, rolled, yawed) merged into one mesh: the fence, the stripes."""

    def __init__(self):
        self.bm = bmesh.new()

    def box(self, size, center, yaw=0.0, roll=0.0, jitter=0.0):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=cage.size2b(size), verts=bm.verts)
        if jitter > 0.0:
            for v in bm.verts:
                v.co.x += R(-jitter, jitter)
                v.co.z += R(-jitter, jitter)
        if roll:
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(roll, 3, "Y"), verts=bm.verts)   # about the rail's length (sim z = blender -y)
        if yaw:
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(yaw, 3, "Z"), verts=bm.verts)
        bmesh.ops.translate(bm, vec=Vector(cage.s2b(center)), verts=bm.verts)
        tmp = bpy.data.meshes.new("_merge_tmp")
        bm.to_mesh(tmp)
        bm.free()
        self.bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)

    def finish(self, name, mat, coll, parent):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        # box UVs so the cedar grain reads: project each face by its normal
        o = bpy.data.objects.new(name, me)
        me.materials.append(mat)
        cage.link_obj(o, coll, parent, (0, 0, 0))
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        try:
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.cube_project(cube_size=0.5)
            bpy.ops.object.mode_set(mode="OBJECT")
        except Exception:
            pass
        o.select_set(False)
        return o


class SnowMerge:
    """Every lying-snow piece into one bmesh → one mesh."""

    def __init__(self):
        self.bm = bmesh.new()

    def _take(self, bm):
        tmp = bpy.data.meshes.new("_snow_tmp")
        bm.to_mesh(tmp)
        bm.free()
        self.bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)

    def drift(self, x, z, sx, sy, sz, rot=None):
        """A lumpy, asymmetric half-sphere sunk into the ground so its edges read soft."""
        if rot is None:
            rot = R(0, 3.14)
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=7, v_segments=4, radius=1.0)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-4], context="VERTS")
        skew = R(-.35, .35)
        for v in bm.verts:
            xx, yy, zz = v.co.x, v.co.y, v.co.z
            v.co.x = xx * (1 + R(-.22, .22))
            v.co.y = yy * (1 + R(-.22, .22))
            v.co.z = zz * R(.55, 1.2) * (1 + xx * skew)
        bmesh.ops.scale(bm, vec=(sx, sz, sy), verts=bm.verts)              # blender z is up
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(rot, 3, "Z"), verts=bm.verts)
        bmesh.ops.translate(bm, vec=Vector(cage.s2b((x, -sy * .35, z))), verts=bm.verts)
        self._take(bm)

    def patch(self, x, z, r, y=0.004):
        n = 7 + int(R(0, 6))
        stretch, rot = R(.5, 1.6), R(0, 3.14)
        pts = []
        for i in range(n):
            a = i / n * math.pi * 2
            rr = r * R(.45, 1.2)
            px, pz = math.cos(a) * rr * stretch, math.sin(a) * rr
            qx, qz = px * math.cos(rot) - pz * math.sin(rot), px * math.sin(rot) + pz * math.cos(rot)
            pts.append(cage.s2b((x + qx, y, z + qz)))
        bm = bmesh.new()
        verts = [bm.verts.new(p) for p in pts]
        f = bm.faces.new(verts)
        bm.normal_update()
        if f.normal.z < 0:
            bmesh.ops.reverse_faces(bm, faces=[f])
        self._take(bm)

    def box(self, size, center):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=cage.size2b(size), verts=bm.verts)
        bmesh.ops.translate(bm, vec=Vector(cage.s2b(center)), verts=bm.verts)
        self._take(bm)

    def finish(self, name, mat, coll, parent):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        me.materials.append(mat)
        o = bpy.data.objects.new(name, me)
        cage.link_obj(o, coll, parent, (0, 0, 0))
        return o


def add_sky(coll, parent, mat):
    """The dome: a sphere seen from inside (faces flipped), centred on the court."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=SKY_R)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Sky")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new("Sky", me)
    cage.link_obj(o, coll, parent, cage.s2b((0, 0, 0)))
    return o


def add_ring(coll, parent, mat, repeats=7):
    """The treeline: an open cylinder seen from inside, the strip wrapped `repeats` times."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    n = 64
    lo, hi = [], []
    for i in range(n):
        a = i / n * math.pi * 2
        x, z = math.cos(a) * RING_R, math.sin(a) * RING_R
        lo.append(bm.verts.new(cage.s2b((x, -RING_H / 2, z))))
        hi.append(bm.verts.new(cage.s2b((x, RING_H / 2, z))))
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new([lo[i], lo[j], hi[j], hi[i]])
        u0, u1 = i / n * repeats, (i + 1) / n * repeats
        for loop in f.loops:
            v = loop.vert
            u = u0 if v in (lo[i], hi[i]) else u1
            loop[uv].uv = (u, 0.0 if v in (lo[i], lo[j]) else 1.0)
    bm.normal_update()
    # faces must point inward (toward the court at the centre)
    for f in bm.faces:
        c = f.calc_center_median()
        if f.normal.dot(-c) < 0:
            bmesh.ops.reverse_faces(bm, faces=[f])
    me = bpy.data.meshes.new("TreelineRing")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new("TreelineRing", me)
    cage.link_obj(o, coll, parent, cage.s2b(RING_C))
    return o


# ---- the arena ----------------------------------------------------------------------


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    coll = bpy.data.collections.new("Park")
    scene.collection.children.link(coll)
    c_ground, c_props, c_sky, c_snow = cage.sub(coll, "Ground"), cage.sub(coll, "Props"), cage.sub(coll, "Sky"), cage.sub(coll, "Snow")

    asphalt = cage.mat_tex("Park_Asphalt", TEX("park_asphalt.png"))
    grass = cage.mat_tex("Park_Grass", TEX("park_grass.png"))
    snow = cage.mat_flat("Park_Snow", (238, 243, 246), roughness=0.9)
    far_snow = cage.mat_flat("Park_FarSnow", (228, 234, 238), roughness=1.0)
    concrete = cage.mat_flat("Park_Concrete", (185, 182, 174), roughness=0.95)
    brick = cage.mat_flat("Park_Brick", (138, 90, 72), roughness=0.95)
    beige = cage.mat_flat("Park_Beige", (189, 179, 158), roughness=0.95)
    post = cage.mat_flat("Park_Post", (74, 58, 48), roughness=0.9)
    sign = cage.mat_flat("Park_Sign", (237, 237, 230), roughness=0.9)
    lamp = cage.mat_flat("Park_Lamp", (106, 108, 112), roughness=0.7)
    fence = cage.mat_flat("Park_Fence", (120, 122, 126), roughness=0.8)
    sky = cage.mat_flat("Park_Sky", (204, 214, 224), roughness=1.0)
    cedar = cage.mat_tex("Park_Cedar", TEX("park_cedar.png"))
    stripe = cage.mat_flat("Park_Stripe", (233, 228, 214), roughness=0.95)
    ring = cage.mat_tex("Park_Treeline", TEX("park_treeline_strip.png"), alpha_clip=True, double_sided=True, emissive=True)

    root = cage.add_empty("Park", coll, None, (0, 0, 0))

    # Ground: the lawn, the slab, the lot, the road, the path, the pads.
    quad_xz("Lawn", 20.0, 0.0, 240.0, 240.0, -0.03, 0.0, grass, c_ground, root, (60.0, 60.0))
    w = COURT_X1 - COURT_X0
    quad_xz("Court", (COURT_X0 + COURT_X1) / 2, 0.0, w, COURT_HALF_W * 2, 0.0, 0.0, asphalt, c_ground, root, (9.75, 10.0))
    cage.add_box("CourtEdge", (w + 0.1, 0.08, COURT_HALF_W * 2 + 0.1), ((COURT_X0 + COURT_X1) / 2, -0.06, 0), asphalt, c_ground, root)
    quad_xz("ParkingLot", 18.5, -11.5, 9.0, 38.0, -0.005, 0.0, asphalt, c_ground, root, (10.0, 12.0))
    quad_xz("Road", 45.0, -15.0, 44.0, 6.5, -0.01, 0.0, asphalt, c_ground, root, (12.0, 2.0))
    quad_xz("Path", 9.6, -18.5, 15.0, 1.8, -0.01, 2.16, asphalt, c_ground, root, (4.0, 1.0))
    cage.add_box("ConcretePad", (1.8, 0.05, 3.4), (15.5, -0.01, 12.5), concrete, c_ground, root)
    cage.add_box("PoleFooting", (0.42, 0.04, 0.42), (4.27, 0.0, 0.0), concrete, c_ground, root)

    # The horizon: five low buildings, brick and beige alternating; their snow roofs.
    lying = SnowMerge()
    for i, (x, z, wz, h, d) in enumerate([(84, -30, 18, 3, 10), (86, -10, 14, 2.5, 16), (82, 6, 22, 3.2, 9), (88, 26, 16, 4, 10), (70, -40, 12, 2.4, 8)]):
        cage.add_box("Building%d" % i, (d, h, wz), (x, h / 2, z), beige if i % 2 else brick, c_props, root)
        lying.box((d + .2, .25, wz + .2), (x, h + .12, z))
    # The ballfield fence far left, the tall light poles (one straight up behind the hoop).
    z = -36.0
    k = 0
    while z <= -24.0:
        add_cyl("FencePost%d" % k, 0.04, 2.4, (30.0, 1.2, z), fence, c_props, root, verts=4)
        z += 3.0
        k += 1
    cage.add_box("FenceRail", (0.05, 0.05, 12.0), (30.0, 2.4, -30.0), fence, c_props, root)
    for i, (x, z) in enumerate([(24.5, .6), (27, -9), (40, -22)]):
        add_cyl("LampPost%d" % i, 0.09, 7.5, (x, 3.75, z), lamp, c_props, root, verts=6)
        cage.add_box("LampHead%d" % i, (0.9, 0.18, 0.3), (x - .4, 7.4, z), lamp, c_props, root)
    # Bollards at the lot's edge, the notice post and its board on the right.
    for i, (x, z) in enumerate([(14.3, -9.6), (14.3, -12.2)]):
        add_cyl("Bollard%d" % i, 0.06, 1.0, (x, 0.5, z), post, c_props, root, verts=6)
    cage.add_box("NoticePost", (0.08, 1.1, 0.08), (12.6, 0.55, 5.6), post, c_props, root)
    cage.add_box("NoticeBoard", (0.04, 0.42, 0.32), (12.57, 1.05, 5.6), sign, c_props, root)
    # The parking bays: three worn stripes, two bays, the car in the left one.
    stripes = MeshMerge()
    for sx in STRIPES:
        stripes.box((0.11, 0.012, 5.0), (sx, 0.012, 0.1))
    stripes.finish("BayStripes", stripe, c_props, root)

    # Lying snow (toned down): short uneven plough piles at the court's edges,
    # the pole-foot drift (the sim's prop box), dustings on the corners, snow
    # that survived in the lawn's hollows, kerbside piles, a little on the pad.
    for x, z, kk in [(-5.6, -6.5, 1.6), (-2.1, -6.6, 1.1), (1.8, -6.4, 1.4), (-6.9, -3.2, .9), (-3.8, 6.6, .9), (2.6, 6.5, .7), (-7.3, 2.4, .6)]:
        lying.drift(x, z, R(.7, 1.3) * kk, R(.08, .18) * kk, R(.35, .6) * kk)
    dx0, dx1, dh, dz = DRIFT
    lying.drift((dx0 + dx1) / 2, 0.05, (dx1 - dx0) / 2 + 0.03, dh * 0.4, dz * 0.55, 0.4)
    for i in range(9):
        x = R(-7, -5.6) if rng() < .5 else R(-4, 4.4)
        z = (-1 if rng() < .5 else 1) * R(5.1, 6)
        lying.patch(x, z, R(.15, .45), .003)
    count = 0
    for i in range(260):
        if count >= 400:
            break
        x, z = R(-12, 42), R(-34, 34)
        if not clear(x, z, .2):
            continue
        n = noise(x * .6, z * .6) + (.2 if z < 0 else 0)
        if n < .25:
            continue
        lying.patch(x, z, R(.3, 1.4) * (n + .4), -0.008)
        count += 1
    for x, z, kk in [(14.4, -22, 1.4), (14.4, 6.4, 1), (22.6, -4, 1.2), (22.6, 5.5, .9)]:
        lying.drift(x, z, R(.8, 1.4) * kk, R(.2, .4) * kk, R(.6, 1) * kk)
    lying.patch(12.6, 5.6, .4, -.005)
    lying.drift(8.4, -6.3, .5, .08, .4)                 # by the stump
    lying.drift(13.2, -16, 1.6, .07, .3, 0.0)           # along the fallen log
    lying.patch(18.7, 2.3, .4, .006)                     # drifted over a stripe end or two
    lying.patch(21.2, -1.9, .3, .006)
    # The split-rail cedar fence behind the hoop (the sim's back wall):
    # mortised posts, three rails a bay overlapping inside each post, snow
    # on the post tops and along the top rails, piled at every foot.
    wood = MeshMerge()
    for z in FENCE_POSTS:
        ph = 1.22 + R(-.04, .04)
        wood.box((0.15, ph, 0.13), (FENCE_X, ph / 2 - .02, z), yaw=R(-.08, .08))
        lying.box((0.17, 0.025, 0.15), (FENCE_X, ph - .005, z))
        lying.drift(FENCE_X + R(-.1, .1), z, .22, .06, .18)
    for b in range(len(FENCE_POSTS) - 1):
        z0, z1 = FENCE_POSTS[b], FENCE_POSTS[b + 1]
        L = (z1 - z0) + .26
        for k, y in enumerate(FENCE_RAILS):
            sag = R(-.02, .015)
            wood.box((0.06 + R(0, .02), 0.12 + R(-.015, .015), L), (FENCE_X + (.02 if k % 2 else -.02), y + sag, (z0 + z1) / 2), roll=R(-.25, .25), jitter=.008)
            if k == len(FENCE_RAILS) - 1:
                lying.box((0.05, 0.025, L * R(.55, .85)), (FENCE_X, y + sag + .07, (z0 + z1) / 2 + R(-.3, .3)))
    wood.finish("SplitRailFence", cedar, c_props, root)
    lying.finish("SnowLying", snow, c_snow, root)

    # The far snow disc, the sky dome, the treeline ring.
    bpy.ops.mesh.primitive_circle_add(vertices=48, radius=96.0, fill_type="NGON", location=(0, 0, 0))
    far = bpy.context.active_object
    far.name = far.data.name = "FarSnow"
    far.data.materials.append(far_snow)
    cage.link_obj(far, c_ground, root, cage.s2b((8.0, -0.06, -4.0)))
    add_sky(c_sky, root, sky)
    add_ring(c_sky, root, ring)

    meshes = [o for o in coll.all_objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_flat()
    bpy.ops.object.select_all(action="DESELECT")
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
    print("park: %d objects, %d tris -> %s" % (len(c.all_objects), tris, GLB_PATH))
