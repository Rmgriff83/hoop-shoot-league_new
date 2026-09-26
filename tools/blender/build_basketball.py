"""Build the Hoop Shoot low-poly basketball in Blender.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_basketball.py

Or paste into Blender's Scripting workspace and hit Run. Produces:
  art/blender/basketball.blend   (source file, ignored by Godot via art/.gdignore)
  assets/models/basketball.glb   (game-ready export, Y-up, transforms applied)

Style: N64-era blocky. 16 segments x 9 rings (144 faces), flat shading, no
modifiers. Radius matches SimConstants.R_BALL (0.121 m); 1 Blender unit = 1 m.

Seams come from a pixel-art skin (SEAMS = "texture", the default): the UV
sphere's built-in equirectangular UV map wraps assets/textures/ball_wrap.png
once around the ball, sampled with Closest (nearest) interpolation. Regenerate
the skin with tools/aseprite/gen_ball_wrap.lua. SEAMS = "faces" instead paints
whole faces with a second material slot (chunky, one face wide).
"""
import math
import os
import sys
import bmesh
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "basketball.blend")
GLB_PATH = os.path.join(ROOT, "assets", "balls", "classic", "basketball.glb")

R_BALL = 0.121          # core/physics/sim_constants.gd
SEGMENTS = 32           # columns around the equator; sets the SILHOUETTE
# Rows pole to pole. MUST STAY ODD: the comment below and assign_seam_faces()'s
# `on_equator` test both rely on one face row being centred on lat 0, and an even
# count silently loses the SEAMS="faces" equator.
RINGS = 25
ORANGE = (255, 138, 61) # tools/aseprite/gen_placeholders.lua palette
SEAM = (40, 24, 16)
SEAMS = "texture"       # "texture" | "faces"
TEXTURE_PATH = os.path.join(ROOT, "assets", "textures", "ball_wrap.png")
RENDER_DIR = os.path.join(ROOT, "art", "renders", "ball")


def _opt(flag, default=None):
    """--flag VALUE from the args after `--`."""
    if flag in sys.argv:
        i = sys.argv.index(flag)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return default


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def make_material(name, rgb, roughness):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*[srgb_to_linear(c) for c in rgb], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    mat.diffuse_color = bsdf.inputs["Base Color"].default_value  # solid-view color too
    return mat


def make_textured_material(name, image_path, roughness):
    """Principled BSDF fed by an Image Texture.

    The ball is the ONE asset that is smooth-shaded; every other prop in the game
    stays flat-shaded pixel art. Its albedo is therefore linear-filtered rather
    than Closest — crisp texels would fight the smooth lighting and put
    stair-steps back on the seams.

    The pebbling is PAINTED into that albedo, not a normal map. It was a normal
    map briefly; lighting the dots as real bumps read as too heavy-handed at the
    size the ball occupies on screen.
    """
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nodes.get("Ball Skin") or nodes.new("ShaderNodeTexImage")
    tex.name = tex.label = "Ball Skin"
    tex.location = (bsdf.location.x - 400, bsdf.location.y)
    img = bpy.data.images.get(os.path.basename(image_path)) or bpy.data.images.load(image_path)
    img.filepath = image_path
    tex.image = img
    tex.interpolation = "Linear"
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mat.diffuse_color = (*[srgb_to_linear(c) for c in ORANGE], 1.0)
    return mat


def clear_default_scene():
    for name in ("Cube",):
        obj = bpy.data.objects.get(name)
        if obj:
            bpy.data.objects.remove(obj, do_unlink=True)


def build():
    clear_default_scene()

    # Collection to keep the asset tidy in the Outliner.
    coll = bpy.data.collections.get("Basketball") or bpy.data.collections.new("Basketball")
    if coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)

    old = bpy.data.objects.get("Basketball")
    if old:
        bpy.data.objects.remove(old, do_unlink=True)

    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=SEGMENTS, ring_count=RINGS, radius=R_BALL, location=(0, 0, 0)
    )
    obj = bpy.context.active_object
    obj.name = "Basketball"
    obj.data.name = "Basketball"
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    coll.objects.link(obj)

    # The exception to the house style: the ball is smooth-shaded. Everything
    # else in the game keeps its facets (docs/BLENDER_101.md section 7).
    bpy.ops.object.shade_smooth()

    obj.data.materials.clear()
    if SEAMS == "texture":
        obj.data.materials.append(make_textured_material("Ball_Skin", TEXTURE_PATH, 0.82))
    else:
        obj.data.materials.append(make_material("Ball_Orange", ORANGE, 0.9))
        obj.data.materials.append(make_material("Ball_Seam", SEAM, 1.0))
        assign_seam_faces(obj)

    # Apply transforms so the export carries scale 1 / rotation 0.
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def assign_seam_faces(obj):
    # Assign seam faces. A UV sphere's faces come out in a predictable order:
    # top cap (SEGMENTS tris), then (RINGS-2) rows of SEGMENTS quads, then bottom cap.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    seam_cols = {0, SEGMENTS // 4, SEGMENTS // 2, 3 * SEGMENTS // 4}  # 4 meridians
    for f in bm.faces:
        # Classify by geometry rather than index so it's robust.
        cz = f.calc_center_median().z
        cx, cy = f.calc_center_median().x, f.calc_center_median().y
        lat = math.degrees(math.asin(max(-1.0, min(1.0, cz / R_BALL))))   # -90..90
        lon = (math.degrees(math.atan2(cy, cx)) + 360.0) % 360.0            # 0..360
        row_height = 180.0 / RINGS
        col_width = 360.0 / SEGMENTS
        on_equator = abs(lat) < row_height / 2.0    # the single row centred on the equator
        col = int(lon // col_width) % SEGMENTS
        on_meridian = col in seam_cols and abs(lat) < 90.0 - row_height  # skip pole caps
        f.material_index = 1 if (on_equator or on_meridian) else 0
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def save_and_export(obj):
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_animations=False,
    )


## Three views to judge the ball by. FRONT is the one that matters most for the
## side seams: it looks straight down the loops' axis, the angle at which a flat
## circle collapses to a line. POLE proves the cap fix.
VIEWS = [
    ("front", (0.0, -0.46, 0.0)),
    ("quarter", (0.33, -0.33, 0.14)),
    ("pole", (0.0, -0.02, 0.46)),
]


def render_views(tag=""):
    os.makedirs(RENDER_DIR, exist_ok=True)
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        pass                                  # whatever engine is current is valid
    scene.render.film_transparent = False
    scene.render.filter_size = 0.5            # crisp, pixel-art friendly
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_x = scene.render.resolution_y = 420

    sun = bpy.data.objects.get("BallSun")
    if sun is None:
        sun_data = bpy.data.lights.new("BallSun", type="SUN")
        sun_data.energy = 3.6
        sun = bpy.data.objects.new("BallSun", sun_data)
        bpy.context.scene.collection.objects.link(sun)
        sun.rotation_euler = (math.radians(54), 0.0, math.radians(-38))
    world = bpy.data.worlds.get("BallWorld") or bpy.data.worlds.new("BallWorld")
    world.use_nodes = True
    next(n for n in world.node_tree.nodes if n.type == "BACKGROUND") \
        .inputs["Color"].default_value = (0.055, 0.065, 0.10, 1.0)
    scene.world = world

    cam_data = bpy.data.cameras.get("BallCam") or bpy.data.cameras.new("BallCam")
    cam_data.lens = 70
    cam = bpy.data.objects.get("BallCam")
    if cam is None:
        cam = bpy.data.objects.new("BallCam", cam_data)
        bpy.context.scene.collection.objects.link(cam)
    scene.camera = cam
    for name, loc in VIEWS:
        cam.location = loc
        direction = -bpy.data.objects["BallCam"].location
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(
            RENDER_DIR, "%s%s.png" % (name, ("_" + tag) if tag else ""))
        bpy.ops.render.render(write_still=True)
    print("RENDERED %d views to %s" % (len(VIEWS), RENDER_DIR))


if __name__ == "__main__":
    tex = _opt("--tex")
    if tex:
        TEXTURE_PATH = tex
    ball = build()
    if "--no-save" not in sys.argv:
        save_and_export(ball)
    n_seam = sum(1 for p in ball.data.polygons if p.material_index == 1)
    print(f"BUILT Basketball: {len(ball.data.polygons)} faces, {n_seam} seam faces, "
          f"dims={tuple(round(d, 4) for d in ball.dimensions)}")
    if "--no-save" not in sys.argv:
        print(f"SAVED {BLEND_PATH}")
        print(f"EXPORTED {GLB_PATH}")
    if "--render" in sys.argv:
        render_views(_opt("--tag", ""))
