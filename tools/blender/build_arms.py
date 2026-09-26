"""Build the Hoop Shoot first-person shooter ARMS in Blender.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_arms.py -- --force
  ...add --render to also write the framing contact sheets to art/renders/arms/

Produces  art/blender/arms.blend        (source, hand-editable, ignored by Godot)
          assets/arms/default/arms_r.glb + arms_l.glb   (game exports)   [phase 4]

PHASE 0 (this revision): NO ARMS YET.  The framing proof only — the cameras that
exactly replicate the in-game view, a wire frustum you can pose against, a ball
proxy, and three candidate stick-arm anchors to choose between.  Everything here
is measured from the real game, not guessed:

  game/screens/time_trial_screen.gd:_set_spot()
      _cam.position = _spot - _fwd * 1.35 + Vector3(0, 1.55, 0)
      _cam.look_at(hoop_x, arena_set.camera_look_height, hoop_z)
      _pool.rest_pos = _spot + Vector3(0, 1.25, 0)
  assets/arena/*/arena_set.tres   camera_fov = 60.0, camera_look_height = 2.2
  Godot Camera3D defaults          keep_aspect = KEEP_HEIGHT  -> 60 deg is VERTICAL
                                   near = 0.05
  project.godot                    viewport 720 x 1280 (portrait)

SIM SPACE (same convention as build_cage.py), origin at the SHOOTING SPOT:
  +x toward the hoop, +y up, +z the shooter's RIGHT.
  The camera sits at (-1.35, 1.55, 0); the hand plane is x = 0; the ball rests
  at (0, 1.25, 0).  Blender is Z-up, so build with s2b() and export +Y up.

WHY THE CAMERA IS NOT FIRST PERSON: the ball floats on a plane 1.35 m from the
eye -- about 2.4x human arm's reach.  The shoulders are therefore invisible
cheats placed off-frame, and only the forearm and hand are ever on screen.  The
whole question this phase answers is WHERE to put the shoulder, because that
choice decides whether the elbow is on screen at all -- and the elbow sliding
under the ball is the entire point of the feature.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")) \
    if "__file__" in globals() else "/Users/rossgriffus/Documents/projects/godot/hoop_shoot"
BLEND_PATH = os.path.join(ROOT, "art", "blender", "arms.blend")
RENDER_DIR = os.path.join(ROOT, "art", "renders", "arms")
TEX = lambda name: os.path.join(ROOT, "assets", "textures", name)

FPS = 30

# --- the game, verified ------------------------------------------------------
EYE_H = 1.55                 # camera height above the spot
CAM_BACK = 1.35              # camera distance behind the spot == hand-plane depth
LOOK_H = 2.2                 # ArenaSet.camera_look_height (both arenas)
FOV_V = 60.0                 # ArenaSet.camera_fov, VERTICAL because KEEP_HEIGHT
NEAR = 0.05                  # Godot Camera3D default
REST_BALL_Y = 1.25           # BallPool rest hold
R_BALL = 0.121               # SimConstants.R_BALL

BEACH_DIST = 2.9 * 1.175     # SimGeometry.BEACH_DIST -> 3.4075; all 5 beach spots
ARCADE_DIST = 2.6            # SimGeometry.arcade() default
RES_DESIGN = (720, 1280)     # project viewport
RES_NARROW = (591, 1280)     # 19.5:9 -- what actually ships on a modern phone

# Ball heights worth checking. The finger puts the ball wherever it likes:
# FlickInput.GRAB_ZONE_TOP_FRAC = 0.45 caps a grab at screen y >= 576 -> world
# y <= 1.82, and every pixel of downward pull drags it further down.
BALL_HEIGHTS = [("high", 1.70), ("rest", REST_BALL_Y), ("pull", 1.05)]

# --- the rig, in human proportions ------------------------------------------
# The arms are a real two-bone chain.  The shoulder is an invisible cheat placed
# off-frame; only the forearm and hand are ever on screen.  Crucially the ELBOW
# BEND absorbs the ball dropping toward the shoulder as you pull -- that fold is
# the motion the whole feature is built on.
UPPER_L, FORE_L = 0.32, 0.27         # shoulder->elbow, elbow->wrist (human)
ARM_SCALE = 1.0                      # <1 = stubbier, more stylised arms
# A real shoulder drops a little when you pull the ball down -- not the full
# 30 cm, but not zero either. Pinning it in world space forces the elbow to fold
# to 142 deg at full pull, which reads as a chicken wing; letting it follow a
# third of the ball's travel keeps the bend inside a natural 31-112 deg.
SHOULDER_FOLLOW = 0.35

# Phase-0 result. The shoulder sits ON THE HAND PLANE (sim x = 0, the same depth
# as the ball), low and close to the centreline. That one choice is what keeps
# the elbow on screen through the whole wind-up, with no gameplay change at all:
# the frame's bottom edge drops as depth increases, so an elbow at the ball's
# depth stays inside it, while one placed nearer the camera falls out.
SHOULDER_R = (0.00, 0.80, 0.18)
SHOULDER_L = (-0.03, 0.87, -0.24)    # guide side sits higher and wider: NOT a mirror
POLE_R = (0.15, -1.0, 1.0)           # shooting elbow hangs down-and-out. Solved, not
                                     # guessed: this is the one config where the elbow
                                     # stays on screen at every pull, the bend rises
                                     # monotonically 38->142 deg, and the forearm rotates
                                     # one way throughout (no mid-gesture flip).
POLE_L = (0.10, -0.55, -1.0)         # guide elbow points sideways, not down
R_PALM = 0.136                       # wrist distance from the ball centre. The ball is
                                     # 0.121, so this leaves just enough for the palm slab
                                     # -- any more and the hands visibly float beside it.
PALM_SINK = 0.008                    # how far the knuckles press INTO the ball past the
                                     # palm sphere, so the hand grips rather than hovers
DIGIT_CURL = -38.0                   # degrees the fingers wrap over the ball

# Where each wrist sits, as a direction out from the ball's centre.
# Sim axes: +x toward the hoop, +y up, +z the shooter's right. So -x is the side
# nearest the camera -- the side a shooting hand is actually on.
#
# The shooting hand starts on the lower-right-rear of the ball and slides to
# BEHIND AND UNDER it: palm cupping the bottom third, back of the hand toward the
# camera, fingers spread up across the ball's face. That is a real shooting grip;
# gripping the ball's side is how you carry it, not how you shoot it.
PALM_OPEN_R = (-0.30, -0.35, 0.89)
PALM_UNDER_R = (-0.45, -0.88, 0.12)
# The guide hand never goes under the ball -- it rides the SIDE and drifts up.
# Breaking the symmetry is what stops the pair reading as a machine pincer.
PALM_OPEN_L = (-0.30, -0.22, -0.93)
PALM_UNDER_L = (-0.42, 0.15, -0.90)

# Fingers wrap UP the ball's face rather than following the forearm round its
# side, so the shooting hand's fingertips finish near the ball's equator -- they
# read as spread fingers on the ball instead of a fist round the back.
WRAP_REF = (0.0, 1.0, 0.0)

# How far the ball actually falls across a full wind-up.  Today the game moves
# the ball 1 px per px of finger travel (gain 1.0), which drags the hands off the
# bottom of the screen exactly when the pose matters most.  Phase 0 renders both.
BALL_TOP, BALL_BOTTOM = 1.42, 1.12   # measured from real grab points + a 52 deg arc
DROP_GAIN = 1.0
BALL_LIFT = 0.0                      # constant offset between the finger and the ball

# The three ways to keep the hands on screen through a deep pull. Phase 0 renders
# all three so the call is made on pictures.
SCHEMES = {
    # Settled in phase 0: gameplay untouched, human proportions. Stubbier arms
    # were tested and are WORSE -- a shorter arm keeps the elbow near the hand,
    # so when the hand nears the bottom edge the elbow goes off with it.
    "1_chosen": dict(gain=1.00, lift=0.00, scale=1.00,
                     label="gameplay untouched, human arms, shoulder on the hand plane"),
}


def s2b(p):
    """sim (x, y, z) -> blender (x, -z, y)."""
    return (p[0], -p[2], p[1])


def size2b(s):
    return (s[0], s[2], s[1])


# --- vector helpers + two-bone IK -------------------------------------------

def _sub(a, b): return tuple(a[i] - b[i] for i in range(3))
def _add(a, b): return tuple(a[i] + b[i] for i in range(3))
def _mul(a, s): return tuple(c * s for c in a)
def _dot(a, b): return sum(a[i] * b[i] for i in range(3))
def _len(a): return math.sqrt(_dot(a, a))


def _norm(a):
    m = _len(a)
    return tuple(c / m for c in a) if m > 1e-9 else a


def solve_elbow(shoulder, wrist, pole, scale=None):
    """Two-bone IK. The elbow is placed on the circle of valid solutions, on the
    side the pole vector points to. Returns None if the target is out of reach."""
    sc = ARM_SCALE if scale is None else scale
    up_l, fore_l = UPPER_L * sc, FORE_L * sc
    d = _sub(wrist, shoulder)
    L = _len(d)
    if L > up_l + fore_l:
        print("  !! OUT OF REACH: shoulder->wrist %.3f m > arm %.3f m -- the hand "
              "would detach from the ball" % (L, up_l + fore_l))
    L = max(min(L, up_l + fore_l - 1e-4), abs(up_l - fore_l) + 1e-4)
    uhat = _norm(d)
    a = (up_l ** 2 - fore_l ** 2 + L * L) / (2 * L)
    h = math.sqrt(max(up_l ** 2 - a * a, 0.0))
    perp = _sub(pole, _mul(uhat, _dot(pole, uhat)))
    if _len(perp) < 1e-6:
        return None
    return _add(_add(shoulder, _mul(uhat, a)), _mul(_norm(perp), h))


def ball_y_at(pull01, gain=None, lift=None):
    """Where the ball sits at a given wind-up. gain 1.0 / lift 0 is today's game."""
    g = DROP_GAIN if gain is None else gain
    return BALL_TOP + (BALL_LIFT if lift is None else lift) \
        - g * pull01 * (BALL_TOP - BALL_BOTTOM)


def wrist_at(pull01, ball_y, right=True):
    """The wrist rides the ball's surface, rolling from beside it to under it."""
    o = PALM_OPEN_R if right else PALM_OPEN_L
    v = PALM_UNDER_R if right else PALM_UNDER_L
    d = _norm(tuple(o[i] + pull01 * (v[i] - o[i]) for i in range(3)))
    return (d[0] * R_PALM, ball_y + d[1] * R_PALM, d[2] * R_PALM)


def arm_pose(pull01, right=True, gain=None, lift=None, scale=None):
    """-> (shoulder, elbow, wrist, ball_y) in sim metres.

    A lift raises the WHOLE rig, shoulder included -- it slides the ball and the
    arms up the screen together, leaving the pose itself untouched. Lifting the
    ball alone would put it out of arm's reach and detach the hand."""
    lf = BALL_LIFT if lift is None else lift
    base = SHOULDER_R if right else SHOULDER_L
    by = ball_y_at(pull01, gain, lift)
    sh = (base[0], base[1] + lf - SHOULDER_FOLLOW * (BALL_TOP + lf - by), base[2])
    w = wrist_at(pull01, by, right)
    e = solve_elbow(sh, w, POLE_R if right else POLE_L, scale)
    return sh, e, w, by


def srgb(rgb, a=1.0):
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), a)


def principled(mat):
    """Look the shader up by TYPE -- node names are localised on a non-English UI."""
    return next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def mat_flat(name, rgb, roughness=1.0, emissive=False):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = principled(m)
    b.inputs["Base Color"].default_value = srgb(rgb)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = 0.0
    if emissive:
        b.inputs["Emission Color"].default_value = srgb(rgb)
        b.inputs["Emission Strength"].default_value = 1.0
    m.diffuse_color = srgb(rgb)
    return m


def mat_tex(name, path, roughness=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    b = principled(m)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = 0.0
    tex = nodes.get("Skin") or nodes.new("ShaderNodeTexImage")
    tex.name = tex.label = "Skin"
    tex.location = (b.location.x - 420, b.location.y)
    img = bpy.data.images.get(os.path.basename(path)) or bpy.data.images.load(path)
    tex.image = img
    tex.interpolation = "Closest"       # nearest-neighbour: crisp pixels
    links.new(tex.outputs["Color"], b.inputs["Base Color"])
    return m


def sub(parent, name):
    c = bpy.data.collections.new(name)
    parent.children.link(c)
    return c


def link_obj(o, coll, parent, sim_loc):
    for c in list(o.users_collection):
        c.objects.unlink(o)
    coll.objects.link(o)
    if parent is not None:
        o.parent = parent
    o.location = Vector(s2b(sim_loc))
    return o


def empty(name, sim_loc, coll, parent=None, display="PLAIN_AXES", size=0.08):
    o = bpy.data.objects.new(name, None)
    o.empty_display_type = display
    o.empty_display_size = size
    return link_obj(o, coll, parent, sim_loc)


def cyl_between(name, a, b, radius, mat, coll, segments=6):
    """A capsule-less cylinder from sim point a to sim point b -- stick-arm proxy."""
    A, B = Vector(s2b(a)), Vector(s2b(b))
    d = B - A
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments, radius=radius, depth=d.length,
                                        location=(A + B) / 2.0)
    o = bpy.context.active_object
    o.name = o.data.name = name
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    o.data.materials.append(mat)
    bpy.ops.object.shade_flat()
    for c in list(o.users_collection):
        c.objects.unlink(o)
    coll.objects.link(o)
    return o



# =============================================================================
# Phase 1: real geometry. Rigid segments, each mesh's ORIGIN at its proximal
# joint, parented in a chain -- the same no-armature technique as hometown's
# build_sim.py. Every segment is modelled along its LOCAL +Z so a joint is just
# a rotation, which is what both Blender's Graph Editor and Godot will drive.
# =============================================================================

# Proportions in sim metres. Lengths are human; the ball is 0.242 m across, so a
# hand has to read at roughly 0.17 m tip-to-wrist or it looks like a doll's.
# Each segment starts with a ring at NEGATIVE t, i.e. behind its own joint, so
# the limb overlaps itself at every hinge. Without it a bent elbow opens a
# visible hole between two rigid prisms -- the classic giveaway of a jointed rig.
SEG = dict(
    upper=dict(sides=5, rings=[(-0.10, 0.044), (0.00, 0.058), (0.55, 0.052), (1.00, 0.050)]),
    fore=dict(sides=6, rings=[(-0.20, 0.044), (-0.06, 0.055), (0.00, 0.054),
                              (0.30, 0.049), (0.72, 0.038), (1.00, 0.031)]),
)
CUFF_W, CUFF_R = 0.026, 0.037      # wristband: a colour break exactly at the joint
PALM = (0.090, 0.032, 0.095)       # across, thick, wrist->knuckles
DIGITS = [                          # (name, local x offset, length, radius, splay deg)
    ("Index",   0.033, 0.072, 0.0115,  10.0),
    ("MidRing", 0.004, 0.080, 0.0175,   0.0),   # middle+ring fused: the standard cheat
    ("Pinky",  -0.032, 0.060, 0.0105, -13.0),
]
THUMB = dict(x=0.050, length=0.062, radius=0.0135, yaw=62.0, pitch=-34.0)


def prism(name, length, sides, rings, mat, coll, cap=True):
    """A tapered prism along LOCAL +Z, origin at the proximal joint (z = 0)."""
    bm = bmesh.new()
    loops = []
    for t, r in rings:
        ring = [bm.verts.new((r * math.cos(2 * math.pi * i / sides + math.pi / sides),
                              r * math.sin(2 * math.pi * i / sides + math.pi / sides),
                              t * length)) for i in range(sides)]
        loops.append(ring)
    for a, b in zip(loops, loops[1:]):
        for i in range(sides):
            bm.faces.new((a[i], a[(i + 1) % sides], b[(i + 1) % sides], b[i]))
    if cap:
        bm.faces.new(list(reversed(loops[0])))
        bm.faces.new(loops[-1])
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    for poly in me.polygons:
        poly.use_smooth = False        # flat shaded, N64 house style
    return o


def box(name, size, centre, mat, coll):
    """Axis-aligned box in LOCAL space (size/centre are local metres)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0] + centre[0],
                       v.co.y * size[1] + centre[1],
                       v.co.z * size[2] + centre[2]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    for poly in me.polygons:
        poly.use_smooth = False
    return o


def aim(obj, origin, target, roll_deg=0.0, up=(0.0, 0.0, 1.0)):
    """Place obj at `origin` (sim) with its local +Z pointing at `target` (sim)."""
    d = Vector(s2b(target)) - Vector(s2b(origin))
    q = d.to_track_quat("Z", "Y")
    obj.location = Vector(s2b(origin))
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = q @ Euler((0.0, 0.0, math.radians(roll_deg))).to_quaternion()
    return d.length


def reparent(child, parent):
    """Parent without moving the child (keep its current world transform).

    The view_layer update is load-bearing: matrix_world is stale until the
    depsgraph has re-evaluated, and parenting off a stale matrix scatters the
    limb across the scene."""
    bpy.context.view_layer.update()
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _perp(v, n):
    """The part of v perpendicular to unit n."""
    return _sub(v, _mul(n, _dot(v, n)))


def b2s(v):
    """blender Vector -> sim tuple (inverse of s2b)."""
    return (v.x, v.z, -v.y)


def aim_matrix(origin, target, roll_deg=0.0):
    """World matrix placing a part at `origin` (sim) with local +Z on `target`."""
    o = Vector(s2b(origin))
    d = Vector(s2b(target)) - o
    if d.length < 1e-7:
        d = Vector((0.0, 0.0, 1.0))
    q = d.to_track_quat("Z", "Y") @ Euler((0.0, 0.0, math.radians(roll_deg))).to_quaternion()
    return Matrix.Translation(o) @ q.to_matrix().to_4x4()


def frame_matrix(origin, z_dir, y_dir):
    """World matrix with local +Z along z_dir and local +Y as close to y_dir as
    possible. Unlike to_track_quat this pins the ROLL, which is what keeps the
    flat of the palm against the ball instead of edge-on to it."""
    z = Vector(s2b(_norm(z_dir)))
    y = Vector(s2b(_norm(y_dir)))
    y = (y - z * y.dot(z))
    y = y.normalized() if y.length > 1e-6 else Vector((0.0, 0.0, 1.0))
    x = y.cross(z)
    m = Matrix.Identity(4)
    m.col[0][:3], m.col[1][:3], m.col[2][:3] = x, y, z
    m.translation = Vector(s2b(origin))
    return m


def set_world(obj, world):
    """Set a part's transform from a WORLD matrix, resolving the parent chain.

    Parts are posed parent-first with a depsgraph update between, because the
    parent's matrix_world has to be current before a child can be solved
    against it."""
    if obj.parent is not None:
        local = (obj.parent.matrix_world @ obj.matrix_parent_inverse).inverted() @ world
    else:
        local = world
    loc, rot, _scale = local.decompose()
    obj.location = loc
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = rot


def wrap_target(knuckle, ball_p, wrap_dir, length, splay_deg, sink):
    """Where a digit's tip should land: further around the ball, at the palm
    radius, fanned sideways by `splay_deg`. Solving against the sphere keeps every
    fingertip ON the surface however the palm has rolled -- a fixed bend angle
    cannot, and drifts up to 20 cm as the hand turns under the ball."""
    r = _norm(_sub(knuckle, ball_p))
    t = _perp(wrap_dir, r)
    t = _norm(t) if _len(t) > 1e-5 else _norm(_cross(r, (0.0, 1.0, 0.0)))
    sidev = _norm(_cross(r, t))
    a = math.radians(splay_deg)
    step = _add(_mul(t, math.cos(a) * length), _mul(sidev, math.sin(a) * length))
    out = _sub(_add(knuckle, step), ball_p)
    return _add(ball_p, _mul(_norm(out), R_PALM - sink))


def hand_frame(w, e, ball_p):
    """(palm normal, wrap direction, knuckle point) for a wrist at w.

    The wrap direction is world UP projected onto the ball's tangent plane, so
    fingers climb the face of the ball. Deriving it from the forearm instead sent
    them round the side, which is a carrying grip, not a shooting one."""
    n = _norm(_sub(ball_p, w))
    f = _perp(WRAP_REF, n)
    if _len(f) < 1e-4:                       # wrist directly under the ball
        f = _perp(_norm(_sub(w, e)), n)
    f = _norm(f) if _len(f) > 1e-5 else (0.0, 1.0, 0.0)
    # Walk along the tangent then project back onto the palm sphere. Subtracting
    # the OLD normal instead would leave the hand drifting off the ball.
    out = _sub(_add(w, _mul(f, PALM[2])), ball_p)
    return n, f, _add(ball_p, _mul(_norm(out), R_PALM - PALM_SINK))


def pose_arm(side, pull01):
    """Drive an already-built arm to the pose for a given wind-up. Rotations
    only -- segment lengths never change, which is what makes this keyframable
    and what Godot will replay."""
    right = side == "R"
    sh, e, w, by = arm_pose(pull01, right)
    ball = (0.0, by, 0.0)
    obj = lambda stem: bpy.data.objects["%s%s" % (stem, side)]
    upd = bpy.context.view_layer.update

    set_world(obj("UpperArm"), aim_matrix(sh, e))
    upd()
    set_world(obj("Forearm"), aim_matrix(e, w))
    upd()
    fd = _norm(_sub(w, e))
    set_world(obj("Cuff"), aim_matrix(_sub(w, _mul(fd, CUFF_W * 1.4)), w))

    n, f, knuckles = hand_frame(w, e, ball)
    palm = obj("Palm")
    set_world(palm, frame_matrix(w, _sub(knuckles, w), n))   # +Y = palm faces the ball
    upd()

    sgn = 1.0 if right else -1.0
    for name, dx, length, radius, splay in DIGITS:
        local = Vector((dx * sgn, 0.0, PALM[2]))
        kn = b2s(palm.matrix_world @ local)
        tip = wrap_target(kn, ball, f, length, splay * sgn, PALM_SINK)
        set_world(bpy.data.objects["%s%s" % (name, side)],
                  frame_matrix(kn, _sub(tip, kn), _norm(_sub(ball, kn))))
    local = Vector((THUMB["x"] * sgn, 0.010, PALM[2] * 0.28))
    kn = b2s(palm.matrix_world @ local)
    tip = wrap_target(kn, ball, f, THUMB["length"], THUMB["yaw"] * sgn, PALM_SINK)
    set_world(obj("Thumb"), frame_matrix(kn, _sub(tip, kn), _norm(_sub(ball, kn))))
    upd()
    return ball


def build_arm(side, coll, skin, kit):
    """Create one arm's meshes and hierarchy. Posing is pose_arm()'s job."""
    grp = sub(coll, "Arm%s" % side)
    upper = prism("UpperArm%s" % side, UPPER_L, SEG["upper"]["sides"],
                  SEG["upper"]["rings"], skin, grp)
    fore = prism("Forearm%s" % side, FORE_L, SEG["fore"]["sides"],
                 SEG["fore"]["rings"], skin, grp)
    cuff = prism("Cuff%s" % side, CUFF_W, 6, [(0.0, CUFF_R), (1.0, CUFF_R)], kit, grp)
    palm = prism("Palm%s" % side, PALM[2], 4,
                 [(-0.22, 0.046), (-0.06, 0.056), (0.0, 0.060),
                  (0.40, 0.066), (1.0, 0.062)], skin, grp)
    for v in palm.data.vertices:                  # flatten the MESH, not the object:
        v.co.y *= 0.62                            # object scale would squash the digits
    palm.data.update()

    digits = []
    for name, dx, length, radius, splay in DIGITS:
        digits.append(prism("%s%s" % (name, side), length, 4,
                            [(-0.30, radius * 0.80), (0.0, radius),
                             (0.55, radius * 0.92), (1.0, radius * 0.72)], skin, grp))
    digits.append(prism("Thumb%s" % side, THUMB["length"], 4,
                        [(-0.30, THUMB["radius"] * 0.8), (0.0, THUMB["radius"]),
                         (1.0, THUMB["radius"] * 0.78)], skin, grp))

    for child, parent in ((fore, upper), (cuff, fore), (palm, fore)):
        child.parent = parent
        child.matrix_parent_inverse = Matrix.Identity(4)
    for d in digits:
        d.parent = palm
        d.matrix_parent_inverse = Matrix.Identity(4)
    return upper


def arm_parts(side):
    """Every object the Load clip has to key, in parent-first order."""
    stems = ["UpperArm", "Forearm", "Cuff", "Palm"] + [d[0] for d in DIGITS] + ["Thumb"]
    return [bpy.data.objects["%s%s" % (st, side)] for st in stems]


LOAD_S = 1.00          # Load clip length. 1.0 s makes Godot's seek() a literal
                       # identity: seek(pull01) IS the pose for that wind-up.


def to_nla(obj, action, track_name):
    """Push an object's action into its own NLA track. The glTF exporter merges
    same-named tracks across objects into ONE Godot animation, which is how a
    clip that drives 18 separate rigid parts arrives as a single clip.

    (Same helper as tools/blender/build_cage.py, plus the 4.4+ slot handling.)"""
    ad = obj.animation_data
    for tr in list(ad.nla_tracks):
        if tr.name == track_name:
            ad.nla_tracks.remove(tr)
    track = ad.nla_tracks.new()
    track.name = track_name
    strip = track.strips.new(track_name, 1, action)
    try:                                   # Blender 4.4+ slotted actions
        if hasattr(strip, "action_slot") and len(action.slots):
            strip.action_slot = action.slots[0]
    except Exception:
        pass
    ad.action = None
    return track


def action_fcurves(act):
    """Every F-curve in an action, on both the legacy and the slotted layout.

    Blender 4.4+ moved curves off Action.fcurves into layers > strips >
    channelbags, and 5.x dropped the old attribute entirely."""
    if hasattr(act, "fcurves"):
        for fc in act.fcurves:
            yield fc
        return
    for layer in act.layers:
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []):
                for fc in bag.fcurves:
                    yield fc


def add_load_clip():
    """The wind-up, authored as ONE scrubbable clip.

    The wind-up is a continuous 0..1 value (pull_px / 410), not a timed event, so
    Godot will pause this clip and seek() it to the live pull rather than play it.
    Scrubbing this timeline in Blender therefore IS what the player sees.

    Every frame is a fresh IK solve rather than an interpolated pose, so the hand
    stays welded to the ball the whole way down -- and the keys are LINEAR for the
    same reason: Bezier handles between dense samples overshoot, which would pop
    the hand off the ball between frames."""
    scene = bpy.context.scene
    n = int(round(LOAD_S * FPS))
    scene.frame_start, scene.frame_end = 1, 1 + n
    parts = arm_parts("R") + arm_parts("L")
    ball = bpy.data.objects["BallTarget"]
    for o in parts + [ball]:
        o.animation_data_clear()

    for i in range(n + 1):
        t, f = i / float(n), 1 + i
        for sd in ("R", "L"):
            pose_arm(sd, t)
        ball.location = Vector(s2b((0.0, ball_y_at(t), 0.0)))
        for o in parts:
            o.keyframe_insert("location", frame=f)
            o.keyframe_insert("rotation_quaternion", frame=f)
        ball.keyframe_insert("location", frame=f)

    for o in parts + [ball]:
        act = o.animation_data.action
        for fc in action_fcurves(act):
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"
        act.name = "Load_%s" % o.name
        to_nla(o, act, "Load")
    print("CLIP Load: %d frames (%.2f s), %d objects keyed" % (n + 1, LOAD_S, len(parts)))


# --- cameras -----------------------------------------------------------------

def hoop_sim(dist):
    """The look target, in sim space relative to the shooting spot."""
    return (dist, LOOK_H, 0.0)


def add_camera(name, dist, res, coll):
    """A Camera3D clone: 60 deg VERTICAL fov, near 0.05, aimed exactly like Godot's look_at."""
    cam_data = bpy.data.cameras.new(name)
    cam_data.sensor_fit = "VERTICAL"          # so angle_y IS the vertical fov
    cam_data.angle_y = math.radians(FOV_V)
    cam_data.clip_start = NEAR
    cam_data.clip_end = 4000.0                # Godot Camera3D default far
    cam_data.show_limits = True
    o = bpy.data.objects.new(name, cam_data)
    coll.objects.link(o)
    o.location = Vector(s2b((-CAM_BACK, EYE_H, 0.0)))
    d = Vector(s2b(hoop_sim(dist))) - o.location
    o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()   # mirrors Godot look_at
    o["res_x"], o["res_y"] = res
    o["hoop_dist"] = dist
    return o


def pitch_deg(dist):
    return math.degrees(math.atan2(LOOK_H - EYE_H, CAM_BACK + dist))


# --- frame maths (the whole point of phase 0) --------------------------------

def frame_slopes(dist):
    """(top, bottom) world-Y slope per metre of depth in front of the EYE."""
    p = math.radians(pitch_deg(dist))
    v = math.radians(FOV_V / 2.0)
    return math.tan(p + v), math.tan(p - v)


def half_width(depth, res):
    """Half the frame width, in metres, `depth` metres in front of the eye."""
    return (res[0] / res[1]) * math.tan(math.radians(FOV_V / 2.0)) * depth


def frame_at(depth, dist, res):
    top, bot = frame_slopes(dist)
    return dict(top=EYE_H + top * depth, bottom=EYE_H + bot * depth,
                half_w=half_width(depth, res))


def build_frame_guide(dist, res, coll, name="FrameGuide"):
    """A wire frustum from the eye out past the hand plane, plus depth rings.

    This is the highest-value object in the file: with it visible in the
    viewport you can SEE whether a joint is on screen while you pose, instead
    of rendering to find out."""
    bm = bmesh.new()
    depths = [0.35, 0.70, 0.95, CAM_BACK, 1.8]
    rings = []
    for d in depths:
        f = frame_at(d, dist, res)
        x = -CAM_BACK + d                      # sim x at this depth
        corners = [(x, f["bottom"], -f["half_w"]), (x, f["bottom"], f["half_w"]),
                   (x, f["top"], f["half_w"]), (x, f["top"], -f["half_w"])]
        rings.append([bm.verts.new(s2b(c)) for c in corners])
    for ring in rings:
        for i in range(4):
            bm.edges.new((ring[i], ring[(i + 1) % 4]))
    for a, b in zip(rings, rings[1:]):
        for i in range(4):
            bm.edges.new((a[i], b[i]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    o.display_type = "WIRE"
    o.hide_render = True                       # review aid, never rendered or exported
    o.show_in_front = True
    return o


def stick_arm(pull01, coll, right=True, gain=None, lift=None, scale=None, tag=""):
    """A 2-segment proxy posed by the IK, so the framing question is answered by
    LOOKING rather than by arithmetic. Replaced by real geometry in phase 1."""
    sh, e, w, by = arm_pose(pull01, right, gain, lift, scale)
    if e is None:
        return None
    side = "R" if right else "L"
    rgb = (235, 150, 120) if right else (150, 190, 235)
    mat = mat_flat("Proxy_%s" % side, rgb, 0.9)
    g = sub(coll, "Arm%s%s" % (side, tag))
    cyl_between("Upper%s" % side, sh, e, 0.055, mat, g)
    cyl_between("Fore%s" % side, e, w, 0.050, mat, g)
    for name, at, r in (("Elbow%s" % side, e, 0.058), ("Hand%s" % side, w, 0.080)):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=5, radius=r,
                                             location=Vector(s2b(at)))
        o = bpy.context.active_object
        o.name = name
        o.data.materials.append(mat)
        bpy.ops.object.shade_flat()
        for c in list(o.users_collection):
            c.objects.unlink(o)
        g.objects.link(o)
    return g


def clear_probes():
    for c in list(bpy.data.collections):
        if c.name.startswith("Arm") and c.name != "Arms":
            for o in list(c.objects):
                bpy.data.objects.remove(o, do_unlink=True)
            bpy.data.collections.remove(c)


def ndc(P, dist, res):
    """sim point -> normalised device coords, +y up. Mirrors the Godot projection."""
    pr = math.radians(pitch_deg(dist))
    fwd = (math.cos(pr), math.sin(pr))
    up = (-math.sin(pr), math.cos(pr))
    v = (P[0] + CAM_BACK, P[1] - EYE_H, P[2])
    df = v[0] * fwd[0] + v[1] * fwd[1]
    if df <= 1e-6:
        return None
    t = math.tan(math.radians(FOV_V / 2.0))
    return (v[2] / df / ((res[0] / res[1]) * t), (v[0] * up[0] + v[1] * up[1]) / df / t)


def report(dist, res, label, gain=None, lift=None, scale=None):
    """The phase-0 verdict: does the pose read, and does it stay on screen?"""
    g = DROP_GAIN if gain is None else gain
    print("\n=== %s  (%dx%d, gain %.2f, lift %.2f m) ==="
          % (label, res[0], res[1], g, BALL_LIFT if lift is None else lift))
    f = frame_at(CAM_BACK, dist, res)
    print("  hand plane: frame y %.3f..%.3f, half-width %.3f, ball = %.0f%% of frame width"
          % (f["bottom"], f["top"], f["half_w"], 100.0 * 2 * R_BALL / (2 * f["half_w"])))
    print("  %-5s %-4s %-6s | %-19s | %-19s | %-8s %s"
          % ("pull", "arc", "ball y", "elbow ndc", "wrist ndc", "forearm", "elbow bend"))
    angs, xs = [], []
    for t in (0.0, 0.25, 0.5, 0.75, 1.0):
        sh, e, w, by = arm_pose(t, True, g, lift, scale)
        if e is None:
            print("  %.2f  OUT OF REACH" % t)
            continue
        pe, pw = ndc(e, dist, res), ndc(w, dist, res)
        ang = math.degrees(math.atan2(pw[0] - pe[0], pw[1] - pe[1]))
        bend = math.degrees(math.acos(max(-1.0, min(1.0,
               _dot(_norm(_sub(e, sh)), _norm(_sub(w, e)))))))
        angs.append(ang)
        xs.append(pe[0])
        print("  %.2f %3.0fd %.3f | (%+.2f,%+.2f) %-6s | (%+.2f,%+.2f) %-6s | %+6.0f  %5.0f deg"
              % (t, 19 + t * 52, by, pe[0], pe[1], "on" if abs(pe[1]) < 1 else "OFF",
                 pw[0], pw[1], "on" if abs(pw[1]) < 1 else "OFF", ang, bend))
    if angs:
        sw_a, sw_x = max(angs) - min(angs), max(xs) - min(xs)
        verdict = "READS" if (sw_a >= 18.0 or sw_x >= 0.35) else "TOO SUBTLE"
        print("  -> forearm angle swing %.0f deg, elbow x swing %.2f ndc  ... %s"
              % (sw_a, sw_x, verdict))


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start, scene.frame_end = 1, 1 + FPS
    scene.unit_settings.system = "METRIC"

    root = bpy.data.collections.new("Arms")
    scene.collection.children.link(root)
    c_cams = sub(root, "Cameras")
    c_guide = sub(root, "Guides")
    c_probe = sub(root, "AnchorProbes")

    # Cameras: every one a byte-for-byte clone of the game's Camera3D.
    cam = add_camera("GameCam", BEACH_DIST, RES_DESIGN, c_cams)
    add_camera("GameCamArcade", ARCADE_DIST, RES_DESIGN, c_cams)
    add_camera("GameCamNarrow", BEACH_DIST, RES_NARROW, c_cams)
    scene.camera = cam

    # A 3/4 review camera -- the ONLY way to watch the elbow do what was asked,
    # because the game camera structurally cannot show it.
    side = bpy.data.cameras.new("SideCam")
    side.lens = 50
    so = bpy.data.objects.new("SideCam", side)
    c_cams.objects.link(so)
    side.lens = 55
    so.location = Vector(s2b((0.80, 1.62, 1.15)))
    so.rotation_euler = (Vector(s2b((-0.02, 1.30, 0.06))) - so.location) \
        .to_track_quat("-Z", "Y").to_euler()

    hand = bpy.data.cameras.new("HandCam")
    hand.lens = 85
    ho = bpy.data.objects.new("HandCam", hand)
    c_cams.objects.link(ho)
    ho.location = Vector(s2b((-0.75, 1.10, 0.42)))
    ho.rotation_euler = (Vector(s2b((-0.04, 1.24, 0.06))) - ho.location) \
        .to_track_quat("-Z", "Y").to_euler()

    build_frame_guide(BEACH_DIST, RES_DESIGN, c_guide, "FrameGuide")
    guide_narrow = build_frame_guide(BEACH_DIST, RES_NARROW, c_guide, "FrameGuideNarrow")
    guide_narrow.hide_viewport = True          # toggle on to check the shipping aspect

    # The ball. BallTarget is the handle everything hangs off; BallProxy is the
    # real game mesh's size and skin so silhouettes are judged honestly.
    # The proxy MUST sit where the pose says the ball is, or every contact
    # measurement is taken against a phantom ball 17 cm away.
    ball_target = empty("BallTarget", (0.0, ball_y_at(0.0), 0.0), c_guide,
                        display="SPHERE", size=0.1)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=25, radius=R_BALL,
                                         location=(0, 0, 0))
    proxy = bpy.context.active_object
    proxy.name = proxy.data.name = "BallProxy"
    bpy.ops.object.shade_flat()
    wrap = TEX("ball_wrap.png")
    proxy.data.materials.append(mat_tex("BallSkin", wrap) if os.path.exists(wrap)
                                else mat_flat("BallOrange", (255, 138, 61), 0.9))
    link_obj(proxy, c_guide, ball_target, (0, 0, 0))

    # Real geometry at the open pose.
    skin = mat_flat("ArmSkin", (232, 176, 141), 0.95)
    kit = mat_flat("ArmKit", (58, 74, 104), 0.9)
    build_arm("R", c_probe, skin, kit)
    build_arm("L", c_probe, skin, kit)
    pose_arm("R", 0.0)
    pose_arm("L", 0.0)
    add_load_clip()

    # Light: a plain sun, enough to read the silhouettes.
    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("Sun", sun_data)
    root.objects.link(sun)
    sun.rotation_euler = (math.radians(52), 0.0, math.radians(-40))
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    next(n for n in world.node_tree.nodes if n.type == "BACKGROUND") \
        .inputs["Color"].default_value = srgb((70, 95, 125))
    scene.world = world
    return scene


def setup_render(scene):
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        pass                                   # older/newer id; whatever is current is valid
    scene.render.film_transparent = False
    scene.render.filter_size = 0.5             # crisp, pixel-art friendly
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"


def render_sweep(scene):
    """Step the Load clip and render it through the real in-game framing."""
    os.makedirs(RENDER_DIR, exist_ok=True)
    setup_render(scene)
    n = int(round(LOAD_S * FPS))
    shots = 0
    for cam_name in ("GameCamNarrow", "SideCam", "HandCam"):
        cam = bpy.data.objects[cam_name]
        scene.camera = cam
        if cam_name in ("SideCam", "HandCam"):
            scene.render.resolution_x = scene.render.resolution_y = 900
        else:
            scene.render.resolution_x, scene.render.resolution_y = RES_NARROW
        for t in (0.0, 0.25, 0.5, 0.75, 1.0):
            scene.frame_set(1 + int(round(t * n)))
            scene.render.filepath = os.path.join(
                RENDER_DIR, "%s_pull%03d.png" % (cam_name, int(t * 100)))
            bpy.ops.render.render(write_still=True)
            shots += 1
    scene.frame_set(1)
    scene.camera = bpy.data.objects["GameCamNarrow"]
    print("RENDERED %d frames to %s" % (shots, RENDER_DIR))


def save():
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("SAVED", BLEND_PATH)


if __name__ == "__main__" and bpy.app.background:
    if os.path.exists(BLEND_PATH) and "--force" not in sys.argv:
        print("REFUSING: %s exists. Re-run with `-- --force` to rebuild it "
              "(hand edits will be lost)." % BLEND_PATH)
        sys.exit(0)
    scene = build()
    for key in sorted(SCHEMES):
        sc = SCHEMES[key]
        report(BEACH_DIST, RES_NARROW, sc["label"], gain=sc["gain"], lift=sc["lift"],
               scale=sc.get("scale"))
    if "--render" in sys.argv:
        render_sweep(scene)
    save()
