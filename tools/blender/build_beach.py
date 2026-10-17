"""Build the beach arena: an outdoor court slab facing the ocean, sand, a
subdivided ocean plane (Godot's ocean.gdshader moves its vertices), a foam
strip the tide slides, a sunset sky panel, ten `PalmRig` handles for the 3D
coconut palms (the unit model exports to palm.glb; BeachFx instances it) and
the hoop's in-ground pole. Production pass 2026-10-16 (design "Beach Concept"
34a): board-formed concrete walls, pale concrete caps + apron, rippled sand,
weathered asphalt, the 3D palms and one-mesh vertex-coloured umbrellas.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_beach.py

Produces  art/blender/beach.blend         (source, ignored by Godot),
          assets/arena/beach/beach.glb    (game export, Y-up, transforms applied) and
          assets/arena/beach/palm.glb     (the unit palm: PalmTrunk + PalmFronds).

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
import random
import sys
import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_cage as cage        # noqa: E402  (helpers: s2b, add_quad, add_box, mat_tex, ...)

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "beach.blend")
GLB_PATH = os.path.join(ROOT, "assets", "arena", "beach", "beach.glb")
PALM_GLB_PATH = os.path.join(ROOT, "assets", "arena", "beach", "palm.glb")
TEX = lambda name: os.path.join(ROOT, "assets", "textures", name)

BEACH_DIST = 2.9 * 1.175                  # SimGeometry.BEACH_DIST
BOARD_X = BEACH_DIST + 0.3796
POLE_X = BOARD_X + 0.3                    # CourtGeometry.CROSSBAR_X_OFF
COURT_X0, COURT_X1, COURT_HALF_W = -9.9, 4.3, 7.6
SAND_X0, SAND_X1 = 4.5, 18.0
# Knee-high concrete wall (the embankment) enclosing the whole court, set
# back from the baseline so the hoop has room; rectangle x ENC_X0..ENC_X1,
# z ±ENC_HALF_W. The chain-link fence above it came off on 2026-10-02; the
# sim's walls (SimGeometry.beach) still stand there, unseen.
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


def add_box_uv(name, sim_size, sim_center, mat, coll, parent, uv_m):
    """add_box whose faces are UV-mapped from their SIM position in `uv_m`-metre
    tiles (vertical faces: along × height, with v = 0 at the ground), so a
    texture authored as one course of wall reads the same on every box."""
    o = cage.add_box(name, sim_size, sim_center, mat, coll, parent)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    uvl = bm.loops.layers.uv.verify()
    ox, oy, oz = o.location
    for f in bm.faces:
        n = f.normal
        for loop in f.loops:
            x, y, z = loop.vert.co.x + ox, loop.vert.co.y + oy, loop.vert.co.z + oz  # blender, z up
            if abs(n.z) > 0.5:
                loop[uvl].uv = (x / uv_m, y / uv_m)
            elif abs(n.x) > 0.5:
                loop[uvl].uv = (y / uv_m, z / uv_m)
            else:
                loop[uvl].uv = (x / uv_m, z / uv_m)
    bm.to_mesh(o.data)
    bm.free()
    return o


# ---- The coconut palm (design "Beach Concept" 34a): a unit-height model ------------
# Built in the design's frame (y up, x the lean) and exported on its own to
# palm.glb; BeachFx draws all ten in two MultiMeshes placed by the PalmRig
# empties (scale = the tree's height, yaw = the lean, away from the court).
PALM_HEIGHTS = (4.4, 4.4, 3.8, 3.4, 3.8, 3.8, 4.2, 4.2, 3.6, 3.6)
PALM_SPOTS = ((6.5, -2.1), (6.5, 2.1),                    # flanking the hoop (design: 0.7 × the old z)
              (10.0, -21.0), (11.2, -9.5), (11.2, 9.5), (10.0, 21.0),
              (3.5, -9.2), (3.5, 9.2), (-4.0, -9.4), (-4.0, 9.4))
FRONDS = 11


def _catmull(pts, t):
    n = len(pts) - 1
    seg = min(int(t * n), n - 1)
    u = t * n - seg
    p0, p1, p2, p3 = pts[max(seg - 1, 0)], pts[seg], pts[seg + 1], pts[min(seg + 2, n)]
    return 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u * u * u)


def _trunk_top():
    return Vector((0.42 - 0.06, 1.0, 0.0))


def build_palm_trunk(coll, mat, rnd):
    """A tube along the leaning, up-curving spine, 12 rings of 7, tapered
    (1.35 - 0.5k wide, a flare at the foot), UV u around / v along × 9, with
    five coconuts under the crown. One mesh: PalmTrunk."""
    pts = [Vector((0.42 * (k / 10.0) ** 1.6 - 0.06 * (k / 10.0), k / 10.0, 0.0)) for k in range(11)]
    rings, sides = 12, 7
    verts, faces, uvs = [], [], {}
    for i in range(rings + 1):
        k = i / rings
        c = _catmull(pts, k)
        tng = (_catmull(pts, min(1.0, k + 0.01)) - _catmull(pts, max(0.0, k - 0.01))).normalized()
        nrm = tng.cross(Vector((0, 0, 1))).normalized()
        bin_ = tng.cross(nrm).normalized()
        w = 1.35 - 0.5 * k + ((0.06 - k) * 6 if k < 0.06 else 0.0)
        for j in range(sides):
            a = 2 * math.pi * j / sides
            verts.append(c + (nrm * math.cos(a) + bin_ * math.sin(a)) * 0.022 * w)
    for i in range(rings):
        for j in range(sides):
            a, b = i * sides + j, i * sides + (j + 1) % sides
            faces.append((a, b, b + sides, a + sides))
            uvs[len(faces) - 1] = [(j / sides, i / rings * 9), ((j + 1) / sides, i / rings * 9),
                                   ((j + 1) / sides, (i + 1) / rings * 9), (j / sides, (i + 1) / rings * 9)]
    top = _trunk_top()
    for i in range(5):
        a = i * 1.26
        centre = Vector((top.x + math.cos(a) * 0.035, top.y - 0.03 - (i % 2) * 0.02, math.sin(a) * 0.035))
        base = len(verts)
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.028)
        bm.verts.ensure_lookup_table()
        verts += [centre + v.co for v in bm.verts]
        for f in bm.faces:
            faces.append(tuple(base + v.index for v in f.verts))
            uvs[len(faces) - 1] = [(0.5, 0.5)] * len(f.verts)
        bm.free()
    return _mesh_from(coll, "PalmTrunk", mat, verts, faces, uvs)


def build_palm_fronds(coll, mat, rnd):
    """Eleven V-folded strips arching out and drooping from the trunk top, the
    design's spine (rise by f % 3, length 0.52..0.66, droop 0.55 L k²), three
    verts per ring; UV (0 | 0.5 | 1, k), UV2 = (phase / 32, direction / 2π)
    per frond for palm3d.gdshader's flutter. One mesh: PalmFronds."""
    top = _trunk_top()
    verts, faces, uvs, uv2s = [], [], {}, {}
    S = 10
    for f in range(FRONDS):
        a = f / FRONDS * math.pi * 2 + rnd.random() * 0.3
        up = 0.55 if f % 3 == 0 else (0.15 if f % 3 == 1 else -0.15)
        L = 0.52 + rnd.random() * 0.14
        d = Vector((math.cos(a), 0.0, math.sin(a)))
        side = Vector((-d.z, 0.0, d.x))
        phase = f * 2.39 + rnd.random() * 3
        base = len(verts)
        ring_pts = []
        for i in range(S + 1):
            k = i / S
            out = L * k
            y = top.y + up * L * k - 0.55 * L * k * k * (1 - up * 0.6)
            c = Vector((top.x, 0.0, 0.0)) + d * out
            c.y = y
            w = 0.085 * math.sin(math.pi * min(1.0, 0.15 + k * 0.95)) + 0.01
            fold = 0.03 * (1 - k)
            verts += [c - side * w + Vector((0, -fold, 0)), c + Vector((0, fold * 0.5, 0)), c + side * w + Vector((0, -fold, 0))]
            ring_pts.append(k)
        ex = sum(verts[base + j].x - top.x for j in range(3 * (S + 1)))
        ez = sum(verts[base + j].z for j in range(3 * (S + 1)))
        ang = math.atan2(ez, ex) % (2 * math.pi)
        for i in range(S):
            b = base + i * 3
            for tri in ((b, b + 3, b + 1), (b + 1, b + 3, b + 4), (b + 1, b + 4, b + 2), (b + 2, b + 4, b + 5)):
                faces.append(tri)
                uvs[len(faces) - 1] = [(((v - base) % 3) * 0.5, 1.0 - ring_pts[(v - base) // 3]) for v in tri]
                uv2s[len(faces) - 1] = [(phase / 32.0, 1.0 - ang / (2 * math.pi))] * 3
    return _mesh_from(coll, "PalmFronds", mat, verts, faces, uvs, uv2s)


def _mesh_from(coll, name, mat, verts, faces, uvs, uv2s=None, colors=None):
    """A mesh object from design-frame (y up) verts; per-face UV lists (and UV2,
    vertex colours) applied by face index. Linked under no parent at the origin."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([cage.s2b((v.x, v.y, v.z)) for v in verts], [], faces)
    me.validate()
    uvl = me.uv_layers.new(name="UVMap")
    uv2 = me.uv_layers.new(name="UV2") if uv2s is not None else None
    for poly in me.polygons:
        for li, loop in enumerate(poly.loop_indices):
            uvl.data[loop].uv = uvs[poly.index][li]
            if uv2 is not None:
                uv2.data[loop].uv = uv2s[poly.index][li]
    if colors is not None:
        attr = me.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="POINT")
        flat = []
        for c in colors:
            flat += list(c)
        attr.data.foreach_set("color", flat)
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    cage.link_obj(o, coll, None, (0, 0, 0))
    return o


def mat_vcol_tex(name, path):
    """Vertex colour × a texture (the umbrellas' dither): Color Attribute and
    Image Texture multiplied into Base Color. The exporter writes COLOR_0 and
    the texture; Godot multiplies them (albedo from vertex colour + albedo map)."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    b = nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.9
    b.inputs["Metallic"].default_value = 0.0
    vc = nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    vc.location = (b.location.x - 600, b.location.y)
    tex = nodes.new("ShaderNodeTexImage")
    tex.name = tex.label = "Skin"
    tex.image = bpy.data.images.get(os.path.basename(path)) or bpy.data.images.load(path)
    tex.interpolation = "Closest"
    tex.location = (b.location.x - 600, b.location.y - 300)
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    mix.location = (b.location.x - 250, b.location.y)
    links.new(vc.outputs["Color"], mix.inputs[6])
    links.new(tex.outputs["Color"], mix.inputs[7])
    links.new(mix.outputs[2], b.inputs["Base Color"])
    m.use_backface_culling = False
    return m


class TriMerge:
    """Triangles with a colour each (design frame, y up) merged into one
    vertex-coloured mesh with position-mapped UVs: the umbrellas."""

    def __init__(self):
        self.verts, self.cols, self.faces = [], [], []

    def tri(self, a, b, c, col):
        base = len(self.verts)
        self.verts += [Vector(a), Vector(b), Vector(c)]
        self.cols += [cage.srgb(col)] * 3
        self.faces.append((base, base + 1, base + 2))

    def finish(self, name, coll, parent, mat, uv_fn):
        uvs = {i: [uv_fn(self.verts[v]) for v in f] for i, f in enumerate(self.faces)}
        o = _mesh_from(coll, name, mat, self.verts, self.faces, uvs, None, self.cols)
        cage.link_obj(o, coll, parent, (0, 0, 0))
        return o


UMB_WHITE, UMB_RED, UMB_RIB, UMB_POLE, UMB_MET = (240, 240, 235), (220, 60, 50), (90, 78, 68), (216, 210, 198), (138, 130, 120)


def build_umbrella(name, coll, parent, mat):
    """The design's umbrella: six alternating gores that dome (0.30 (1 - t²) -
    0.06 t over r 1.15), a 0.12 valance flap per gore, dark ribs under the
    seams and stretchers to a hub at y -0.42, a four-sided finial, a 4-sided
    pole from -2.05 to 0.26 with a collar. One mesh, 1 draw (was 3)."""
    R, G, SEG = 1.15, 6, 2
    m = TriMerge()

    def cp(a, t):
        return Vector((R * t * math.cos(a), 0.30 * (1 - t * t) - 0.06 * t, R * t * math.sin(a)))

    for g in range(G):
        col = UMB_RED if g % 2 else UMB_WHITE
        a0, a1 = g / G * math.pi * 2, (g + 1) / G * math.pi * 2
        for sg in range(SEG):
            t0, t1 = sg / SEG, (sg + 1) / SEG
            p00, p01, p10, p11 = cp(a0, t0), cp(a1, t0), cp(a0, t1), cp(a1, t1)
            m.tri(p00, p10, p11, col)
            m.tri(p00, p11, p01, col)
        q0, q1 = cp(a0, 1), cp(a1, 1)
        r0 = Vector((q0.x * 1.01, q0.y - 0.12, q0.z * 1.01))
        r1 = Vector((q1.x * 1.01, q1.y - 0.12, q1.z * 1.01))
        m.tri(q0, r0, r1, col)
        m.tri(q0, r1, q1, col)

    def strip(p0, p1, w, col):
        d = p1 - p0
        sd = Vector((-d.z, 0.0, d.x)).normalized() * w
        m.tri(p0 - sd, p1 - sd, p1 + sd, col)
        m.tri(p0 - sd, p1 + sd, p0 + sd, col)

    for g in range(G):
        a = g / G * math.pi * 2
        for sg in range(SEG):
            strip(cp(a, sg / SEG) + Vector((0, -0.012, 0)), cp(a, (sg + 1) / SEG) + Vector((0, -0.012, 0)), 0.012, UMB_RIB)
        mid, hub = cp(a, 0.55) + Vector((0, -0.02, 0)), Vector((0, -0.42, 0))
        sd = Vector((math.cos(a + math.pi / 2), 0.0, math.sin(a + math.pi / 2))) * 0.008
        m.tri(hub - sd, mid - sd, mid + sd, UMB_MET)
        m.tri(hub - sd, mid + sd, hub + sd, UMB_MET)
    base, tip = Vector((0, 0.27, 0)), Vector((0, 0.40, 0))
    for i in range(4):
        b0, b1 = i / 4 * math.pi * 2, (i + 1) / 4 * math.pi * 2
        m.tri(base + Vector((0.05 * math.cos(b0), 0, 0.05 * math.sin(b0))), tip, base + Vector((0.05 * math.cos(b1), 0, 0.05 * math.sin(b1))), UMB_RIB)

    def cyl(y0, y1, r, n, col):
        for i in range(n):
            b0, b1 = i / n * math.pi * 2, (i + 1) / n * math.pi * 2
            c0, s0, c1, s1 = math.cos(b0) * r, math.sin(b0) * r, math.cos(b1) * r, math.sin(b1) * r
            A, B, C, D = Vector((c0, y0, s0)), Vector((c1, y0, s1)), Vector((c1, y1, s1)), Vector((c0, y1, s0))
            m.tri(A, C, B, col)
            m.tri(A, D, C, col)

    cyl(-2.05, 0.26, 0.032, 4, UMB_POLE)
    cyl(-1.06, -0.94, 0.05, 4, UMB_MET)
    return m.finish(name, coll, parent, mat, lambda p: ((p.x + p.z) * 5, p.y * 10 + (p.x - p.z) * 5))


def build_palm_model():
    """The unit palm in its own collection (exported to palm.glb, not part of
    beach.glb). Deterministic: random.Random(7) like the design's LCG seed."""
    coll = bpy.data.collections.new("PalmModel")
    bpy.context.scene.collection.children.link(coll)
    rnd = random.Random(7)
    bark = cage.mat_tex("Palm_Bark", TEX("beach_bark.png"))
    frond = cage.mat_tex("Palm_Frond", TEX("beach_frond.png"), alpha_clip=True, double_sided=True)
    build_palm_trunk(coll, bark, rnd)
    build_palm_fronds(coll, frond, rnd)
    return coll


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
    pole_tex = cage.mat_tex("Beach_Pole", TEX("beach_pole.png"))
    concrete = cage.mat_tex("Beach_Concrete", TEX("beach_concrete.png"))
    # Pale cast concrete on the wall caps AND the apron between the lined slab
    # and the wall (design 34a; the apron was plain blacktop before).
    curb = cage.mat_tex("Beach_Curb", TEX("beach_curb.png"))
    dark = cage.mat_flat("Beach_Dark", (40, 38, 40))
    # Smooth look: linear sampling on every beach skin (the cage stays pixel-crisp).
    for m in (court, sand, water, foam, sky, pole_tex, concrete, curb):
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
                  (0, 1, 0), curb, c_court, root, ((ap_x1 - ap_x0) / 0.5, 2 * ap_w / 0.5))
    cage.add_quad("Court", [(COURT_X0, 0, -w), (COURT_X1, 0, -w), (COURT_X1, 0, w), (COURT_X0, 0, w)],
                  (0, 1, 0), court, c_court, root, (1.0, 1.0))
    # The knee-high wall around the whole court: four boxes.
    corners = [(ENC_X0, -ENC_HALF_W), (ENC_X1, -ENC_HALF_W), (ENC_X1, ENC_HALF_W), (ENC_X0, ENC_HALF_W)]
    # Wall: four boxes, each extended by the wall thickness so corners are solid.
    for k in range(4):
        (ax, az), (bx, bz) = corners[k], corners[(k + 1) % 4]
        length = math.hypot(bx - ax, bz - az)
        cx, cz = (ax + bx) / 2.0, (az + bz) / 2.0
        along_x = abs(bx - ax) > abs(bz - az)
        size = (length + WALL_T, WALL_H, WALL_T) if along_x else (WALL_T, WALL_H, length + WALL_T)
        # Board-formed concrete: one texture height = the wall's height, the
        # courses running along it; the caps in 0.5 m tiles of pale concrete.
        add_box_uv("Wall%d" % k, size, (cx, WALL_H / 2.0, cz), concrete, c_court, root, WALL_H)
        add_box_uv("WallCap%d" % k, (size[0] + 0.06, 0.06, size[2] + 0.06), (cx, WALL_H + 0.03, cz), curb, c_court, root, 0.5)
    # No chain-link on the beach (Ross, 2026-10-02): just the concrete
    # embankment. The league chalkboard that stood on the wall cap came down
    # on 2026-10-16 (no league_banner_* fields in the beach ArenaSet now).

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

    # Palms (design 34a, 2026-10-16): 3D coconut palms, no longer billboards.
    # Each `PalmRig%d` empty carries its tree's transform — scale = the tree's
    # height (the old quad's, ×1.05, varied ±8 %), yaw = the lean, away from
    # the court at (3, 0) with a spread — and BeachFx draws the unit model
    # (palm.glb) at every rig in two MultiMeshes. The pair flanking the hoop
    # sits a bit further in (z ±2.1); the rest keep their 2026-10-02 spots.
    prnd = random.Random(7)
    for i, (x, z) in enumerate(PALM_SPOTS):
        prig = cage.add_empty("PalmRig%d" % i, c_props, root, (x, 0.0, z))
        hgt = PALM_HEIGHTS[i] * 1.05 * (0.92 + prnd.random() * 0.16)
        prig.scale = (hgt, hgt, hgt)
        prig.rotation_euler = (0.0, 0.0, math.atan2(-z, x - 3.0) + (prnd.random() - 0.5) * 1.2)

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
    umb_mat = mat_vcol_tex("Umbrella", TEX("beach_dither.png"))
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
            # The design's umbrella as one vertex-coloured mesh (UmbMesh%d) on
            # the `Umbrella%d` rig BeachFx rocks; the canopy sits at y 2.05.
            urig = cage.add_empty("Umbrella%d" % i, c_people, rig, (0.2, 0.0, -0.75))
            umb = build_umbrella("UmbMesh%d" % i, c_people, urig, umb_mat)
            umb.location = cage.s2b((0.0, 2.05, 0.0))
            umb.rotation_euler = (0.0, 0.0, i * 0.4)
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
    pc = build_palm_model()
    for o in pc.all_objects:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.shade_flat()
    bpy.ops.object.select_all(action="DESELECT")
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    cage.export_glb(c, GLB_PATH)
    cage.export_glb(pc, PALM_GLB_PATH)
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
