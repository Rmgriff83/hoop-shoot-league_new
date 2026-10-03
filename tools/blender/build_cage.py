"""Build the Hoop Shoot arcade cage arena in Blender: steel-tube cage with
chain-link mesh walls, rubber deck with ball-return lip, side rails with a
sliding crossbar + trolley (the hoop's carriage), strung bulbs overhead, and the dim
arcade hall around it.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_cage.py

Produces  art/blender/cage.blend      (source, ignored by Godot) and
          assets/arena/cage/cage.glb  (game export, Y-up, transforms applied).

Coordinates: the arena's origin is the SIM ORIGIN (the shooter's release
plane, floor level, centre lane). Sim space is x toward the hoop, y up,
z lateral (shooter's right); Blender is Z-up, so build with
    blender (x, y, z) = (sim x, -sim z, sim y)
and export +Y up. Numbers below are in SIM metres; s2b() converts.

Runtime contract (game/court/court_geometry.gd): the empties `Cage` (static),
`Crossbar` (Godot slides it along the rails in x) and `Trolley` (slides along
the crossbar in x AND z) are found by name. The hoop is a separate glb that
Godot places at the sim's hoop pose; the trolley's hanger just meets it.

Animation handles (empties you can keyframe; the glTF exporter turns each NLA
track into one Godot animation named after the track):
  Cage        the whole cage + hall (shake it, tilt it)
  Bulb<side>_<i>  string-light bulbs along the top rails (ArcadeFx twinkles them)
  Crossbar / Trolley  the carriage (Godot drives these at runtime, so leave
                      them un-keyed unless a clip should override the sim)
One sample clip ships in an NLA track:
"CageShake" (played at the buzzer). Copy their pattern for new scenarios.

This script is a CREATOR: it starts from an empty file and never opens
hoop.blend. It REFUSES to overwrite an existing cage.blend unless run with
`-- --force`, so hand edits are safe. After editing in Blender, re-export
from the live file (File > Export > glTF, same settings as save_and_export:
Animation on, mode NLA Tracks, +Y up, Apply Modifiers).
"""
import math
import os
import sys
import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "cage.blend")
GLB_PATH = os.path.join(ROOT, "assets", "arena", "cage", "cage.glb")
TEX = lambda name: os.path.join(ROOT, "assets", "textures", name)

# Must match CourtGeometry.RAIL_Y / CROSSBAR_X_OFF and TimeTrial's sweep.
RAIL_Y = 3.5
CROSSBAR_X = 2.9 + 0.3796 + 0.3     # base pose: board_x + CROSSBAR_X_OFF
CAGE_HALF_W = 1.26           # 10 % slimmer; mirrored by SimGeometry.arcade's wall_z
CAGE_X0, CAGE_X1 = -1.8, 4.4
CAGE_H = 3.9
RAIL_X0, RAIL_X1 = 1.6, 4.3
RAIL_Z = CAGE_HALF_W - 0.08
TUBE = 0.1
DECK_X0 = -0.4
RAMP_X0 = 3.5                       # flat landing zone ends past the far hoop pose (3.4)
RAMP_TOP_Y = 0.9                    # mirrored by SimGeometry.arcade ramp_x0/ramp_h: the ball rolls down it
# Egg-crate foam over the back panel (2026-10-03): a lattice of PAD_CELL
# pyramids standing PAD_DEPTH proud of the panel's face, from the ramp's top to
# the roof tube. The sim's back wall sits at the peaks' x (SimGeometry.arcade
# ARCADE_BACK_X), so the ball bounces off the foam, not the panel behind it.
# Return arrows (DeckArrow%02dL / %02dR): two rows at z ±ARROW_ROW_Z, centres
# along x — three steps on the ramp's slope and six down the deck — each a
# minimal 0.22 x 0.36 m chevron. Decals only (nothing in the sim);
# ArcadeFx.ARROW_STEPS is the step count, two meshes per step.
ARROW_XS = (4.2, 3.9, 3.62, 3.2, 2.75, 2.3, 1.85, 1.4, 0.95)
ARROW_LEN = 0.22
ARROW_HALF_W = 0.18
ARROW_ROW_Z = 0.42
PAD_CELL = 0.12
PAD_DEPTH = 0.07
PAD_FACE_X = CAGE_X1 - 0.02         # the panel box is 4 cm thick, centred on CAGE_X1
HANGER_LEN = 0.71                   # rail (3.5) down to the hoop's arm (2.79)
# String lights along the two top-corner rails, in place of the old marquee sign.
# At CAGE_H they ride the frame tubes; the sim roof is also 3.9, so nothing hangs
# into the lane where the ball would punch through it.
# Runner lights around the TOP OF THE ARCADE HALL (not the cage): a chase runs
# along them. Indexed in one continuous path — left wall front-to-back, across
# the back, then right wall back-to-front — so the runner flows rather than
# jumping between walls.
# Runner lights across the arcade hall, above the cabinet rows.
#
# They were first hung at the hall's CEILING (y 6.2) and were invisible: the
# cage's own solid BackPanel tops out at 3.9 m but sits at x 4.4, only 5.8 m
# from the shooter, so on screen it covers everything on the hall's back wall
# below ~6.9 m. The hall's whole upper wall is behind it. The band that IS
# visible from inside the cage is the one the cabinets already glow in, just
# outboard of the cage's mesh sides — so the lights go there, on the dark upper
# wall (HALL_WALL_SPLIT 2.2) right above the machines.
BULB_Y = 2.5
BULB_SPACING = 0.7
BULB_R = 0.12
BULB_INSET = 0.18            # clear of the wall surface
BULB_RETURN = 4.5            # how far the run turns down each side wall
HALL_X0, HALL_X1 = -8.0, 12.0
HALL_HALF_W = 8.0
HALL_H = 7.0
FPS = 30
HALL_WALL_SPLIT = 2.2               # textured cabinets below (2.2 m tall), dark above
MESH_REPEATS_PER_M = 1.25           # 4 cells per tile -> 20 cm cells (finer shimmers on a phone)


def s2b(p):
    """sim (x, y, z) -> blender (x, -z, y)."""
    return (p[0], -p[2], p[1])


def size2b(s):
    return (s[0], s[2], s[1])


def srgb(rgb):
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1.0)


def mat_flat(name, rgb, roughness=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = srgb(rgb)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = 0.0
    m.diffuse_color = srgb(rgb)
    return m


def mat_tex(name, path, alpha_clip=False, double_sided=False, emissive=False, matte=False):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    b = nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 1.0
    b.inputs["Metallic"].default_value = 0.0
    if matte:
        # No specular lobe at all (foam): KHR_materials_specular on export, and
        # CourtGeometry._matte() repeats it at load for importers that drop it.
        for key in ("Specular IOR Level", "Specular"):
            if key in b.inputs:
                b.inputs[key].default_value = 0.0
                break
    tex = nodes.new("ShaderNodeTexImage")
    tex.name = tex.label = "Skin"
    tex.location = (b.location.x - 420, b.location.y)
    img = bpy.data.images.get(os.path.basename(path)) or bpy.data.images.load(path)
    tex.image = img
    tex.interpolation = "Closest"
    links.new(tex.outputs["Color"], b.inputs["Base Color"])
    if emissive:
        # glTF emissiveTexture: the surface glows on its own (marquee, neon).
        links.new(tex.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = 1.0
    if alpha_clip:
        clip = nodes.new("ShaderNodeMath")
        clip.operation = "GREATER_THAN"
        clip.inputs[1].default_value = 0.5
        clip.location = (b.location.x - 200, b.location.y - 300)
        links.new(tex.outputs["Alpha"], clip.inputs[0])
        links.new(clip.outputs[0], b.inputs["Alpha"])
        for attr, val in (("blend_method", "CLIP"), ("surface_render_method", "DITHERED")):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
    m.use_backface_culling = not double_sided
    return m


def link_obj(obj, coll, parent=None, location=(0, 0, 0)):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    coll.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    obj.location = Vector(location)
    return obj


def add_empty(name, coll, parent, sim_loc):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "PLAIN_AXES"
    e.empty_display_size = 0.2
    link_obj(e, coll, parent, s2b(sim_loc))
    return e


def add_box(name, sim_size, sim_center, mat, coll, parent):
    """Axis-aligned box; size/centre in SIM metres (centre relative to parent)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = o.data.name = name
    o.scale = Vector(size2b(sim_size))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    link_obj(o, coll, parent, s2b(sim_center))
    return o


def add_quad(name, sim_corners, toward, mat, coll, parent, uv_repeat=(1.0, 1.0), origin=(0, 0, 0)):
    """One quad from 4 SIM corners (c0..c3 around the perimeter). u runs c0->c1,
    v runs c0->c3 (times uv_repeat for tiling). The winding is flipped if the
    face normal points away from `toward` (a sim direction), so callers only
    say which way the surface should be seen from. `origin` is the parent
    handle's sim location: corners are stored relative to it so the handle
    can be animated."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    verts = [bm.verts.new(s2b((c[0] - origin[0], c[1] - origin[1], c[2] - origin[2]))) for c in sim_corners]
    f = bm.faces.new(verts)
    bm.normal_update()
    want = Vector(s2b(toward))
    if f.normal.dot(want) < 0.0:
        bmesh.ops.reverse_faces(bm, faces=[f])
    uvs = [(0, 0), (uv_repeat[0], 0), (uv_repeat[0], uv_repeat[1]), (0, uv_repeat[1])]
    for loop in f.loops:
        loop[uv].uv = uvs[verts.index(loop.vert)]
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    link_obj(o, coll, parent, (0, 0, 0))
    return o


def add_pad(name, x_face, depth, y0, y1, z0, z1, cell, mat, coll, parent):
    """Egg-crate foam: a grid of square cells, each a four-sided pyramid whose
    peak stands `depth` toward the shooter (-x) of the valleys at the cell
    corners. Every cell maps to one full tile of the pad texture (peak at the
    tile's centre) and the mesh is flat-shaded, so each pyramid's four faces
    catch the light differently and the lattice reads from the key."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    nz = max(1, int(round((z1 - z0) / cell)))
    ny = max(1, int(round((y1 - y0) / cell)))
    cz = (z1 - z0) / nz
    cy = (y1 - y0) / ny
    corners = {}
    for j in range(ny + 1):
        for i in range(nz + 1):
            corners[(i, j)] = bm.verts.new(s2b((x_face, y0 + j * cy, z0 + i * cz)))
    for j in range(ny):
        for i in range(nz):
            peak = bm.verts.new(s2b((x_face - depth, y0 + (j + 0.5) * cy, z0 + (i + 0.5) * cz)))
            c = [corners[(i, j)], corners[(i + 1, j)], corners[(i + 1, j + 1)], corners[(i, j + 1)]]
            cuv = [(0, 0), (1, 0), (1, 1), (0, 1)]
            for k in range(4):
                a, b = c[k], c[(k + 1) % 4]
                f = bm.faces.new([a, b, peak])
                f.smooth = False
                for loop in f.loops:
                    if loop.vert is peak:
                        loop[uv].uv = (0.5, 0.5)
                    elif loop.vert is a:
                        loop[uv].uv = cuv[k]
                    else:
                        loop[uv].uv = cuv[(k + 1) % 4]
    bm.normal_update()
    # Face the shooter: flip anything whose normal points away from -x.
    want = Vector(s2b((-1, 0, 0)))
    flip = [f for f in bm.faces if f.normal.dot(want) < 0.0]
    if flip:
        bmesh.ops.reverse_faces(bm, faces=flip)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    link_obj(o, coll, parent, (0, 0, 0))
    return o


def to_nla(obj, action, track_name):
    """Push the object's current action into its own NLA track (one Godot clip)."""
    ad = obj.animation_data
    track = ad.nla_tracks.new()
    track.name = track_name
    strip = track.strips.new(track_name, 1, action)
    try:  # Blender 4.4+ slotted actions
        if hasattr(strip, "action_slot") and len(action.slots):
            strip.action_slot = action.slots[0]
    except Exception:
        pass
    ad.action = None


def key_clip(obj, track_name, keys, attr, index=-1):
    """keys: [(time_s, value)] on obj.<attr>[index] -> NLA track `track_name`."""
    for t, v in keys:
        f = 1 + int(round(t * FPS))
        cur = getattr(obj, attr)
        if index < 0:
            setattr(obj, attr, v)
        else:
            cur[index] = v
            setattr(obj, attr, cur)
        obj.keyframe_insert(attr, index=index, frame=f)
    obj.animation_data.action.name = track_name
    to_nla(obj, obj.animation_data.action, track_name)


def sub(parent_coll, name):
    c = bpy.data.collections.new(name)
    parent_coll.children.link(c)
    return c


def _hall_lights(coll, parent, bulb, wire):
    """Runner lights across the hall's back wall, above the cabinets.

    One continuous index path — up the left return, across the back, down the
    right return — so the chase reads as a single runner. ArcadeFx reads the
    ordinal out of the name, so the order here IS the order it runs in.
    """
    zl = HALL_HALF_W - BULB_INSET
    xb = HALL_X1 - BULB_INSET
    x_ret = xb - BULB_RETURN
    pts = []
    n_ret = max(2, int(round(BULB_RETURN / BULB_SPACING)))
    n_back = max(2, int(round((2.0 * zl) / BULB_SPACING)))
    for i in range(n_ret):                       # left side wall, coming back
        pts.append((x_ret + BULB_RETURN * i / (n_ret - 1), -zl))
    for i in range(1, n_back):                   # across the back wall
        pts.append((xb, -zl + (2.0 * zl) * i / (n_back - 1)))
    for i in range(1, n_ret):                    # right side wall, going out
        pts.append((xb - BULB_RETURN * i / (n_ret - 1), zl))
    for i, (x, z) in enumerate(pts):
        sag = 0.04 * math.sin(math.pi * ((i * 0.5) % 1.0))
        add_box("Bulb%03d" % i, (BULB_R, BULB_R, BULB_R), (x, BULB_Y - sag, z), bulb, coll, parent)
    add_box("BulbWire0", (BULB_RETURN, 0.02, 0.02), (x_ret + BULB_RETURN / 2.0, BULB_Y + 0.05, -zl), wire, coll, parent)
    add_box("BulbWire1", (0.02, 0.02, 2.0 * zl), (xb, BULB_Y + 0.05, 0.0), wire, coll, parent)
    add_box("BulbWire2", (BULB_RETURN, 0.02, 0.02), (x_ret + BULB_RETURN / 2.0, BULB_Y + 0.05, zl), wire, coll, parent)
    return len(pts)


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start, scene.frame_end = 1, 1 + int(round(0.6 * FPS))
    scene.unit_settings.system = "METRIC"
    coll = bpy.data.collections.new("Cage")
    scene.collection.children.link(coll)
    c_frame, c_walls, c_deck = sub(coll, "Frame"), sub(coll, "Walls"), sub(coll, "Deck")
    c_lights, c_hall, c_carriage = sub(coll, "Lights"), sub(coll, "Hall"), sub(coll, "Carriage")

    steel = mat_tex("Cage_Tube", TEX("cage_tube.png"))
    mesh = mat_tex("Cage_Mesh", TEX("cage_mesh.png"), alpha_clip=True, double_sided=True)
    deck = mat_tex("Cage_Deck", TEX("cage_deck.png"))
    ramp = mat_tex("Cage_Ramp", TEX("cage_ramp.png"))
    carpet = mat_tex("Hall_Carpet", TEX("cage_carpet.png"))
    hall = mat_tex("Hall_Wall", TEX("cage_hall.png"), emissive=True)
    bulb = mat_flat("Cage_Bulb", (255, 206, 140), roughness=0.4)   # ArcadeFx twinkles these
    dark = mat_flat("Hall_Dark", (12, 10, 10))
    metal_dark = mat_flat("Cage_MetalDark", (30, 28, 28), roughness=0.8)
    accent = mat_flat("Cage_Accent", (206, 62, 34), roughness=0.7)   # red-orange trim (rim family)
    panel = mat_flat("Cage_BackPanel", (34, 30, 30), roughness=1.0)  # solid back, flat colour
    pad = mat_tex("Cage_Pad", TEX("cage_pad.png"), matte=True)       # egg-crate foam over it
    arrow = mat_tex("Cage_Arrow", TEX("cage_arrow.png"), alpha_clip=True, emissive=True)
    lip = accent
    led_off = mat_tex("Cage_LeagueFace", TEX("hoop_led_off.png"), emissive=True)

    # ---- Cage (static) ------------------------------------------------------
    cage = add_empty("Cage", c_frame, None, (0, 0, 0))
    w = CAGE_HALF_W
    xm = (CAGE_X0 + CAGE_X1) / 2.0
    xl = CAGE_X1 - CAGE_X0
    # Corner + mid verticals.
    for i, x in enumerate((CAGE_X0, 1.3, CAGE_X1)):
        for j, z in enumerate((-w, w)):
            add_box("FrameTube_V%d%d" % (i, j), (TUBE, CAGE_H, TUBE), (x, CAGE_H / 2.0, z), steel, c_frame, cage)
    # Top edges along x (both sides) and along z (front/back).
    for j, z in enumerate((-w, w)):
        add_box("FrameTube_TX%d" % j, (xl, TUBE, TUBE), (xm, CAGE_H, z), accent, c_frame, cage)
    for i, x in enumerate((CAGE_X0, CAGE_X1)):
        add_box("FrameTube_TZ%d" % i, (TUBE, TUBE, 2.0 * w + TUBE), (x, CAGE_H, 0.0), steel, c_frame, cage)
    # Mesh walls (double-sided, alpha-scissor): sides, top, back.
    reps_x = xl * MESH_REPEATS_PER_M
    reps_y = CAGE_H * MESH_REPEATS_PER_M
    add_quad("MeshWallL", [(CAGE_X0, 0, -w), (CAGE_X1, 0, -w), (CAGE_X1, CAGE_H, -w), (CAGE_X0, CAGE_H, -w)],
             (0, 0, 1), mesh, c_walls, cage, (reps_x, reps_y))
    add_quad("MeshWallR", [(CAGE_X0, 0, w), (CAGE_X1, 0, w), (CAGE_X1, CAGE_H, w), (CAGE_X0, CAGE_H, w)],
             (0, 0, -1), mesh, c_walls, cage, (reps_x, reps_y))
    add_quad("MeshTop", [(CAGE_X0, CAGE_H, -w), (CAGE_X1, CAGE_H, -w), (CAGE_X1, CAGE_H, w), (CAGE_X0, CAGE_H, w)],
             (0, -1, 0), mesh, c_walls, cage, (reps_x, 2.0 * w * MESH_REPEATS_PER_M))
    add_box("BackPanel", (0.04, CAGE_H, 2.0 * w), (CAGE_X1, CAGE_H / 2.0, 0.0), panel, c_walls, cage)
    # Egg-crate foam over the panel, from just above the ramp's top to just
    # under the roof tube, inboard of the corner posts.
    add_pad("BackPad", PAD_FACE_X, PAD_DEPTH, RAMP_TOP_Y + 0.02, CAGE_H - TUBE,
            -(w - TUBE), w - TUBE, PAD_CELL, pad, c_walls, cage)
    # Side rails the crossbar rides on.
    rl = RAIL_X1 - RAIL_X0
    for j, z in enumerate((-RAIL_Z, RAIL_Z)):
        add_box("Rail%d" % j, (rl, 0.08, 0.08), ((RAIL_X0 + RAIL_X1) / 2.0, RAIL_Y, z), accent, c_frame, cage)
    # Deck + ball-return lip.
    add_quad("Deck", [(DECK_X0, 0, -w), (RAMP_X0, 0, -w), (RAMP_X0, 0, w), (DECK_X0, 0, w)],
             (0, 1, 0), deck, c_deck, cage, ((RAMP_X0 - DECK_X0), 2.0 * w))
    # Ball-return ramp: rises from the landing zone up to the back panel so the
    # ball comes down toward the shooter. The sim has the same plane
    # (SimGeometry.arcade ARCADE_RAMP_X0 / ARCADE_RAMP_H) and the TrayLip below
    # (ARCADE_LIP_X / ARCADE_LIP_H): a miss lands on it and rolls to the lip.
    add_quad("Ramp", [(RAMP_X0, 0, -w), (CAGE_X1, RAMP_TOP_Y, -w), (CAGE_X1, RAMP_TOP_Y, w), (RAMP_X0, 0, w)],
             (-1, 1, 0), ramp, c_deck, cage, (1.0, 2.0 * w))
    for j, z in enumerate((-w + 0.05, w - 0.05)):
        # Low side curbs along the ramp so it reads as a channel.
        rc = add_box("RampCurb%d" % j, (math.hypot(CAGE_X1 - RAMP_X0, RAMP_TOP_Y), 0.08, 0.08),
                     ((RAMP_X0 + CAGE_X1) / 2.0, RAMP_TOP_Y / 2.0 + 0.04, z), accent, c_deck, cage)
        rc.rotation_euler = (0.0, -math.atan2(RAMP_TOP_Y, CAGE_X1 - RAMP_X0), 0.0)
        add_box("DeckCurb%d" % j, (RAMP_X0 - DECK_X0, 0.08, 0.08),
                ((DECK_X0 + RAMP_X0) / 2.0, 0.04, z), accent, c_deck, cage)
    add_box("TrayLip", (0.06, 0.45, 2.0 * w), (DECK_X0, 0.225, 0.0), lip, c_deck, cage)
    # Return arrows down the centre lane (DeckArrow00 at the top of the ramp,
    # numbered toward the shooter): decals a few mm above the surface, the ones
    # on the ramp laid along its slope. ArcadeFx lights them in succession when
    # a game starts — a chase running back to the player.
    def floor_h(x):
        return 0.0 if x <= RAMP_X0 else RAMP_TOP_Y * (x - RAMP_X0) / (CAGE_X1 - RAMP_X0)
    for i, xc in enumerate(ARROW_XS):
        for side, zc in (("L", -ARROW_ROW_Z), ("R", ARROW_ROW_Z)):
            x0, x1 = xc - ARROW_LEN / 2.0, xc + ARROW_LEN / 2.0
            z0, z1 = zc - ARROW_HALF_W, zc + ARROW_HALF_W
            lift = 0.004
            add_quad("DeckArrow%02d%s" % (i, side),
                     [(x0, floor_h(x0) + lift, z0), (x1, floor_h(x1) + lift, z0),
                      (x1, floor_h(x1) + lift, z1), (x0, floor_h(x0) + lift, z1)],
                     (-1, 1, 0), arrow, c_deck, cage, (1.0, 1.0))
    # League ribbon board across the bottom of the back wall (CourtGeometry
    # binds a SECOND LedBoard to it; the name must NOT be "LedFace", which
    # find_child would confuse with the hoop's own scoreboard).
    #
    # 2.36 x 0.393 m is exactly 6:1, matching the 192x32 LED texture with no
    # stretch. It sits 10 mm proud of the panel at x 4.38, above the ball-return
    # ramp (which reaches y 0.9 at the back, curbs to ~0.98) and inboard of the
    # corner posts at |z| 1.21.
    # Sized down from the full 2.36 m wall run, which read as a billboard. The
    # 6:1 aspect is fixed by the 192x32 LED texture, so width and height scale
    # together: 1.30 x 0.217 m, centred, is about half the cage's width.
    # 2026-10-03: full width again, inboard of the corner posts (|z| 1.21) at
    # 2.36 m, and a touch taller at 0.262 m — the league LedBoard now runs 72
    # columns (288x32, 9:1; LedBoard.LEAGUE_COLS) so its LEDs stay square.
    lf_hw, lf_h, lf_cy = 1.18, 2.36 / 9.0, 1.34
    lf_y0, lf_y1, lf_z = lf_cy - lf_h / 2.0, lf_cy + lf_h / 2.0, lf_hw
    # The board now sits ON the foam: a dark housing box standing on the pad
    # peaks (its back buried in the foam) with the LED face 10 mm proud of it.
    lb_d = 0.05
    lb_x = PAD_FACE_X - PAD_DEPTH - lb_d / 2.0
    add_box("LeagueHousing", (lb_d + PAD_DEPTH, lf_h + 0.06, 2.0 * lf_hw + 0.04),
            (lb_x + PAD_DEPTH / 2.0, lf_cy, 0.0), metal_dark, c_deck, cage)
    lf_x = PAD_FACE_X - PAD_DEPTH - lb_d - 0.01
    add_quad("LeagueFace", [(lf_x, lf_y0, -lf_z), (lf_x, lf_y0, lf_z),
                            (lf_x, lf_y1, lf_z), (lf_x, lf_y1, -lf_z)],
             (-1, 0, 0), led_off, c_deck, cage, (1.0, 1.0))
    # ---- Arcade hall around the cage --------------------------------------
    hw = HALL_HALF_W
    _hall_lights(c_lights, cage, bulb, metal_dark)
    add_quad("HallFloor", [(HALL_X0, -0.02, -hw), (HALL_X1, -0.02, -hw), (HALL_X1, -0.02, hw), (HALL_X0, -0.02, hw)],
             (0, 1, 0), carpet, c_hall, cage, ((HALL_X1 - HALL_X0) * 0.6, 2.0 * hw * 0.6))
    ys = HALL_WALL_SPLIT
    add_quad("HallBack", [(HALL_X1, 0, -hw), (HALL_X1, 0, hw), (HALL_X1, ys, hw), (HALL_X1, ys, -hw)],
             (-1, 0, 0), hall, c_hall, cage, (4.0, 1.0))
    add_quad("HallBackUpper", [(HALL_X1, ys, -hw), (HALL_X1, ys, hw), (HALL_X1, HALL_H, hw), (HALL_X1, HALL_H, -hw)],
             (-1, 0, 0), dark, c_hall, cage)
    for j, (z, toward) in enumerate(((-hw, (0, 0, 1)), (hw, (0, 0, -1)))):
        add_quad("HallSide%d" % j, [(HALL_X0, 0, z), (HALL_X1, 0, z), (HALL_X1, ys, z), (HALL_X0, ys, z)],
                 toward, hall, c_hall, cage, (5.0, 1.0))
        add_quad("HallSideUpper%d" % j, [(HALL_X0, ys, z), (HALL_X1, ys, z), (HALL_X1, HALL_H, z), (HALL_X0, HALL_H, z)],
                 toward, dark, c_hall, cage)
    add_quad("HallCeiling", [(HALL_X0, HALL_H, -hw), (HALL_X1, HALL_H, -hw), (HALL_X1, HALL_H, hw), (HALL_X0, HALL_H, hw)],
             (0, -1, 0), dark, c_hall, cage)

    # ---- Arcade cabinets along the BACK wall, either side of the cage. From
    # the shooter's spot the portrait view sees the far wall at z ≈ ±3.4–5.1
    # past the cage's back panel (the side walls are outside the FOV), so the
    # row sits there, fronts toward the cage. Bodies are plain boxes; the
    # `CabScreen%d` / `CabMarquee%d` quads get live shaders in Godot
    # (game/view/arcade_fx.gd): attract-mode screens and chasing bulbs.
    c_cabs = sub(coll, "Cabinets")
    cab_body = mat_flat("Hall_Cab", (30, 26, 32))
    cab_panel = mat_flat("Hall_CabPanel", (70, 62, 72))
    cab_trim = mat_flat("Hall_CabTrim", (160, 60, 40))
    cab_screen = mat_flat("Hall_CabScreen", (200, 160, 60))
    cab_marquee = mat_flat("Hall_CabMarquee", (240, 200, 90))
    CAB_W, CAB_H, CAB_D = 0.7, 1.85, 0.75
    xc = HALL_X1 - 0.05 - CAB_D / 2.0
    xf = xc - CAB_D / 2.0                                # front face plane (toward the cage)
    zs = [1.9 + 0.8 * k for k in range(7)]
    for i, z in enumerate([-z for z in reversed(zs)] + zs):
        add_box("Cabinet%d" % i, (CAB_D, CAB_H, CAB_W), (xc, CAB_H / 2.0, z), cab_body, c_cabs, cage)
        add_box("CabPanel%d" % i, (0.28, 0.05, CAB_W), (xf - 0.12, 0.96, z), cab_panel, c_cabs, cage)
        add_box("CabCoin%d" % i, (0.02, 0.14, 0.18), (xf - 0.01, 0.45, z), cab_panel, c_cabs, cage)
        add_box("CabTrim%d" % i, (0.03, 0.03, CAB_W + 0.02), (xf - 0.015, 1.5, z), cab_trim, c_cabs, cage)
        xq = xf - 0.006
        add_quad("CabScreen%d" % i, [(xq, 1.05, z + 0.25), (xq, 1.05, z - 0.25), (xq, 1.45, z - 0.25), (xq, 1.45, z + 0.25)],
                 (-1, 0, 0), cab_screen, c_cabs, cage)
        add_quad("CabMarquee%d" % i, [(xq, 1.62, z + 0.33), (xq, 1.62, z - 0.33), (xq, 1.8, z - 0.33), (xq, 1.8, z + 0.33)],
                 (-1, 0, 0), cab_marquee, c_cabs, cage)

    # ---- Crossbar (moves in x) + Trolley (moves in x and z) -----------------
    crossbar = add_empty("Crossbar", c_carriage, None, (CROSSBAR_X, RAIL_Y, 0.0))
    add_box("CrossbarTube", (0.08, 0.08, 2.0 * RAIL_Z), (0, 0, 0), accent, c_carriage, crossbar)
    for j, z in enumerate((-RAIL_Z, RAIL_Z)):
        add_box("CrossbarShoe%d" % j, (0.16, 0.12, 0.12), (0, 0, z), metal_dark, c_carriage, crossbar)
    trolley = add_empty("Trolley", c_carriage, None, (CROSSBAR_X, RAIL_Y, 0.0))
    add_box("TrolleyBlock", (0.2, 0.12, 0.2), (0, 0, 0), metal_dark, c_carriage, trolley)
    add_box("Hanger", (0.06, HANGER_LEN, 0.06), (0, -HANGER_LEN / 2.0, 0), metal_dark, c_carriage, trolley)

    # Flat shading everywhere, transforms applied on meshes (not the empties).
    meshes = [o for o in coll.all_objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.shade_flat()
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.select_all(action="DESELECT")

    # ---- Sample clips (one NLA track each = one Godot animation) ------------
    # (The old MarqueePulse clip went with the sign. Heat-up now surges the
    # string lights instead, which ArcadeFx does in a shader — see flare().)
    # CageShake: the whole cage rattles at the buzzer. Tiny lateral + vertical jitter.
    shake = [(0.0, 0, 0), (0.05, 0.02, -0.01), (0.1, -0.02, 0.01), (0.15, 0.015, -0.005),
             (0.2, -0.01, 0.005), (0.28, 0.005, 0.0), (0.4, 0.0, 0.0)]
    for t, dz, dy in shake:
        cage.location = s2b((0.0, dy, dz))
        cage.keyframe_insert("location", frame=1 + int(round(t * FPS)))
    cage.animation_data.action.name = "CageShake"
    to_nla(cage, cage.animation_data.action, "CageShake")
    return coll


def save_and_export(coll):
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    export_glb(coll)


def export_glb(coll=None, path=GLB_PATH):
    """Export the arena. Usable from inside Blender too (MCP / Text Editor):
        exec(open("tools/blender/build_cage.py").read()); export_glb()"""
    coll = coll or bpy.data.collections["Cage"]
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    for o in coll.all_objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_materials="EXPORT", export_image_format="AUTO",
        export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
    )
    bpy.ops.object.select_all(action="DESELECT")
    print("EXPORTED", path, os.path.getsize(path), "bytes")


if __name__ == "__main__" and bpy.app.background:
    if os.path.exists(BLEND_PATH) and "--force" not in sys.argv:
        print("REFUSING: %s exists (hand edits live there). Re-run with `-- --force` to rebuild from scratch,"
              " or open it in Blender and export_glb() from the live file." % BLEND_PATH)
        sys.exit(0)
    c = build()
    save_and_export(c)
    tris = 0
    for o in c.all_objects:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
        d = tuple(round(x, 3) for x in o.dimensions) if o.type == "MESH" else "-"
        print("OBJ %-16s parent=%-9s loc=%s dims=%s" % (
            o.name, o.parent.name if o.parent else "-", tuple(round(x, 3) for x in o.location), d))
    print("TRIS", tris)
    print("SAVED", BLEND_PATH)
    print("EXPORTED", GLB_PATH)
