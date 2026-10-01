"""Every ball in the game, lined up in one file to look at.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_ball_lineup.py
  ...add --render to also write art/renders/balls/lineup.png
  ...add --thumbs to write assets/textures/balls/thumbs/<id>.png (96 px, RGBA):
     the shaded thumbnails the locker's BALLS tab and prize card show

Produces  art/blender/ball_lineup.blend   (source, hand-editable, ignored by Godot)

This is a REVIEW artifact, not a shipped asset: it exists so the whole roster can
be judged side by side. The balls the game actually loads are one shared glb
(assets/balls/classic/basketball.glb) plus a per-set skin, so nothing here is
exported.

The roster comes from assets/balls/ball_manifest.json, which
tools/aseprite/gen_ball_wrap.lua writes from its STYLE table. That table is the
single source of truth -- ids, names and rarities included -- so this script never
needs editing when a ball is added. The grid runs rarity by rarity (common,
rare, epic, legend) so the tiers read as rows.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")) \
    if "__file__" in globals() else "/Users/rossgriffus/Documents/projects/godot/hoop_shoot"
BLEND_PATH = os.path.join(ROOT, "art", "blender", "ball_lineup.blend")
RENDER_DIR = os.path.join(ROOT, "art", "renders", "balls")
THUMB_DIR = os.path.join(ROOT, "assets", "textures", "balls", "thumbs")
THUMB_PX = 96
RARITIES = ("common", "rare", "epic", "legend")
MANIFEST = os.path.join(ROOT, "assets", "balls", "ball_manifest.json")

R_BALL = 0.121          # core/physics/sim_constants.gd
SEGMENTS, RINGS = 32, 25
COLS = 7
GAP = 0.36              # centre to centre; the ball is 0.242 across, and the
                        # two-line label needs clear space beneath it


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def res_path(p):
    """res://foo -> an absolute path."""
    return os.path.join(ROOT, p[len("res://"):]) if p.startswith("res://") else p


def ball_material(name, skin):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    # Look the shader up by TYPE: node names are localised on a non-English UI.
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.82
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.name = tex.label = "Skin"
    tex.location = (bsdf.location.x - 420, bsdf.location.y)
    img = bpy.data.images.get(os.path.basename(skin)) or bpy.data.images.load(skin)
    img.filepath = skin
    tex.image = img
    tex.interpolation = "Linear"        # the ball is the smooth exception
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mat.diffuse_color = (*[srgb_to_linear(c) for c in (226, 118, 47)], 1.0)
    return mat


def label(text, at, coll):
    cu = bpy.data.curves.new(text, type="FONT")
    cu.body = text
    cu.size = 0.030
    cu.align_x = "CENTER"
    o = bpy.data.objects.new("Label_" + text, cu)
    o.location = at
    # Text lies in the XY plane facing +Z by default; the camera looks along +Y,
    # so without this every label renders edge-on and vanishes.
    o.rotation_euler = (math.radians(90), 0.0, 0.0)
    coll.objects.link(o)
    mat = bpy.data.materials.get("LabelInk") or bpy.data.materials.new("LabelInk")
    mat.use_nodes = True
    b = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (0.86, 0.88, 0.94, 1.0)
    b.inputs["Roughness"].default_value = 1.0
    o.data.materials.append(mat)
    return o


def build(balls):
    bpy.ops.wm.read_homefile(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    coll = bpy.data.collections.new("Lineup")
    scene.collection.children.link(coll)

    balls = sorted(balls, key=lambda b: RARITIES.index(b.get("rarity", "common")))
    rows = (len(balls) + COLS - 1) // COLS
    for i, b in enumerate(balls):
        cx = (i % COLS - (COLS - 1) / 2.0) * GAP
        cz = ((rows - 1) / 2.0 - i // COLS) * GAP
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=SEGMENTS, ring_count=RINGS, radius=R_BALL, location=(cx, 0.0, cz))
        o = bpy.context.active_object
        o.name = "Ball_" + b["id"]
        o.data.name = o.name
        bpy.ops.object.shade_smooth()
        # Tilt so a little of the pole shows. Face-on, anything living at a pole
        # is invisible -- the 8-ball's disc being the obvious case.
        o.rotation_euler = (math.radians(24.0), 0.0, math.radians(14.0))
        o.data.materials.append(ball_material("Ball_" + b["id"], res_path(b["skin"])))
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
        # Two lines: a long name plus a price on one line overruns the cell and
        # collides with the neighbour.
        label("%s\n%s" % (b["name"], b.get("rarity", "").upper()),
              (cx, -0.02, cz - GAP * 0.46), coll)
        o["cell"] = (cx, cz)

    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = 3.4
    sun = bpy.data.objects.new("Sun", sun_data)
    coll.objects.link(sun)
    sun.rotation_euler = (math.radians(58), 0.0, math.radians(-36))

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    next(n for n in world.node_tree.nodes if n.type == "BACKGROUND") \
        .inputs["Color"].default_value = (0.055, 0.062, 0.095, 1.0)
    scene.world = world

    cam_data = bpy.data.cameras.new("LineupCam")
    cam_data.type = "ORTHO"                 # no perspective skew across the grid
    cam_data.ortho_scale = COLS * GAP + 0.12
    cam = bpy.data.objects.new("LineupCam", cam_data)
    coll.objects.link(cam)
    cam.location = Vector((0.0, -2.0, 0.0))
    cam.rotation_euler = (math.radians(90), 0.0, 0.0)
    scene.camera = cam
    scene.render.resolution_x = 1680
    scene.render.resolution_y = int(1680 * (rows * GAP + 0.12) / (COLS * GAP + 0.12))
    return scene


def save_and_render(scene, do_render):
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("SAVED", BLEND_PATH)
    if not do_render:
        return
    os.makedirs(RENDER_DIR, exist_ok=True)
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        pass                                # whatever engine is current is valid
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = os.path.join(RENDER_DIR, "lineup.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)


def render_thumbs(scene):
    """One 96 px RGBA render per ball, the camera parked over each cell."""
    os.makedirs(THUMB_DIR, exist_ok=True)
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        pass
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.resolution_x = scene.render.resolution_y = THUMB_PX
    scene.render.resolution_percentage = 100
    cam = scene.camera
    cam.data.ortho_scale = R_BALL * 2.0 * 1.08
    for o in scene.objects:
        if o.type == "FONT":
            o.hide_render = True
    for o in scene.objects:
        if not o.name.startswith("Ball_"):
            continue
        cx, cz = o["cell"]
        cam.location = Vector((cx, -2.0, cz))
        scene.render.filepath = os.path.join(THUMB_DIR, o.name[len("Ball_"):] + ".png")
        bpy.ops.render.render(write_still=True)
    print("THUMBS", THUMB_DIR)


if __name__ == "__main__" and bpy.app.background:
    with open(MANIFEST) as f:
        balls = json.load(f)
    sc = build(balls)
    save_and_render(sc, "--render" in sys.argv)
    if "--thumbs" in sys.argv:
        render_thumbs(sc)
    print("LINEUP %d balls" % len(balls))
