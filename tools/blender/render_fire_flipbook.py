"""Author the rim's flames in Blender and render them to a looping flipbook
(sprite sheet) the game wraps around the ring (game/view/rim_fire.gd +
game/court/fire_ribbon.gdshader).

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/render_fire_flipbook.py

Output: assets/textures/fx_fire_sheet.png — 8 x 4 frames of 128 x 64, RGBA.

The fire is a procedural node material on a plane (no simulation): two 4D
noise textures whose evolution runs around a circle in (Z, W) space so frame
33 == frame 1 (a perfect loop), shaped by a vertical gradient into tongues, and
coloured by a ramp (white-yellow → orange → red → clear). Horizontally the
noise is mirrored at the edges so the frame tiles around the ring.

Blender's Mantaflow "Quick Fire" can't be exported live, but a sim rendered
the same way (same camera, frame count and sheet layout) drops in as a
replacement sheet if you want to try it from the editor.
"""
import math
import os
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "fx_fire_sheet.png")
TMP = os.path.join(ROOT, ".godot", "fire_frames")
FRAMES = 32
COLS, ROWS = 8, 4
FW, FH = 128, 64
LOOP_R = 1.1         # radius of the evolution circle in noise space (bigger = livelier flicker)


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    scene = bpy.context.scene
    scene.render.resolution_x = FW
    scene.render.resolution_y = FH
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.frame_start, scene.frame_end = 1, FRAMES
    scene.view_settings.view_transform = "Standard"
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            continue
    try:
        scene.eevee.taa_render_samples = 8
    except Exception:
        pass

    # Camera: orthographic, looking along +y at a plane in the XZ plane.
    cam_data = bpy.data.cameras.new("FireCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.0
    cam = bpy.data.objects.new("FireCam", cam_data)
    cam.location = (0.0, -3.0, 0.0)
    cam.rotation_euler = (math.pi / 2, 0.0, 0.0)
    scene.collection.objects.link(cam)
    scene.camera = cam

    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, 0), rotation=(math.pi / 2, 0, 0))
    plane = bpy.context.active_object
    plane.name = "FirePlane"
    plane.scale = (2.0, 1.0, 1.0)     # 2 wide x 1 tall (matches the 128 x 64 frame)

    m = bpy.data.materials.new("Fire")
    m.use_nodes = True
    for attr, val in (("blend_method", "BLEND"), ("surface_render_method", "BLENDED")):
        try:
            setattr(m, attr, val)
        except Exception:
            pass
    nt = m.node_tree
    nodes, links = nt.nodes, nt.links
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    transp = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    coord = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["UV"], sep.inputs[0])

    # Mirror u at the edges so the frame tiles: u' = 1 - |2u - 1|
    u2 = nodes.new("ShaderNodeMath"); u2.operation = "MULTIPLY_ADD"
    u2.inputs[1].default_value = 2.0; u2.inputs[2].default_value = -1.0
    links.new(sep.outputs["X"], u2.inputs[0])
    uabs = nodes.new("ShaderNodeMath"); uabs.operation = "ABSOLUTE"
    links.new(u2.outputs[0], uabs.inputs[0])
    umir = nodes.new("ShaderNodeMath"); umir.operation = "SUBTRACT"
    umir.inputs[0].default_value = 1.0
    links.new(uabs.outputs[0], umir.inputs[1])

    # Evolution around a circle: theta keyed 0 -> 2π over the loop.
    theta = nodes.new("ShaderNodeValue"); theta.name = "Theta"; theta.label = "Theta"
    # Linear keys so the loop runs at a constant speed (Blender 5.2 layered
    # actions: set the new-key interpolation preference instead of poking fcurves).
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
    theta.outputs[0].default_value = 0.0
    theta.outputs[0].keyframe_insert("default_value", frame=1)
    theta.outputs[0].default_value = 2 * math.pi
    theta.outputs[0].keyframe_insert("default_value", frame=FRAMES + 1)
    zc = nodes.new("ShaderNodeMath"); zc.operation = "SINE"
    links.new(theta.outputs[0], zc.inputs[0])
    zs = nodes.new("ShaderNodeMath"); zs.operation = "MULTIPLY"; zs.inputs[1].default_value = LOOP_R
    links.new(zc.outputs[0], zs.inputs[0])
    wc = nodes.new("ShaderNodeMath"); wc.operation = "COSINE"
    links.new(theta.outputs[0], wc.inputs[0])
    ws = nodes.new("ShaderNodeMath"); ws.operation = "MULTIPLY"; ws.inputs[1].default_value = LOOP_R
    links.new(wc.outputs[0], ws.inputs[0])

    def noise(scale, detail, ux, vy):
        comb = nodes.new("ShaderNodeCombineXYZ")
        mx = nodes.new("ShaderNodeMath"); mx.operation = "MULTIPLY"; mx.inputs[1].default_value = ux
        links.new(umir.outputs[0], mx.inputs[0])
        my = nodes.new("ShaderNodeMath"); my.operation = "MULTIPLY"; my.inputs[1].default_value = vy
        links.new(sep.outputs["Y"], my.inputs[0])
        links.new(mx.outputs[0], comb.inputs["X"])
        links.new(my.outputs[0], comb.inputs["Y"])
        links.new(zs.outputs[0], comb.inputs["Z"])
        nz = nodes.new("ShaderNodeTexNoise")
        nz.noise_dimensions = "4D"
        nz.inputs["Scale"].default_value = scale
        nz.inputs["Detail"].default_value = detail
        nz.inputs["Roughness"].default_value = 0.55
        links.new(comb.outputs[0], nz.inputs["Vector"])
        links.new(ws.outputs[0], nz.inputs["W"])
        return nz

    n1 = noise(1.5, 3.0, 2.0, 0.8)   # big tongues (stretched tall)
    n2 = noise(5.0, 2.0, 2.0, 0.9)   # small flicker
    mixn = nodes.new("ShaderNodeMath"); mixn.operation = "MULTIPLY_ADD"
    links.new(n1.outputs["Fac"], mixn.inputs[0]); mixn.inputs[1].default_value = 0.7
    links.new(n2.outputs["Fac"], mixn.inputs[2])
    # scale n2 contribution: (n1*0.7 + n2) then *0.75 → ~0..1.3
    scl = nodes.new("ShaderNodeMath"); scl.operation = "MULTIPLY"; scl.inputs[1].default_value = 0.95
    links.new(mixn.outputs[0], scl.inputs[0])
    # Vertical shaping: bright solid base, tongues thin out toward the top.
    inv = nodes.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.15
    links.new(sep.outputs["Y"], inv.inputs[1])            # 1.15 - v
    shp = nodes.new("ShaderNodeMath"); shp.operation = "MULTIPLY"
    links.new(scl.outputs[0], shp.inputs[0]); links.new(inv.outputs[0], shp.inputs[1])
    base = nodes.new("ShaderNodeMath"); base.operation = "MULTIPLY_ADD"
    links.new(inv.outputs[0], base.inputs[0]); base.inputs[1].default_value = 0.30; base.inputs[2].default_value = -0.14
    fire = nodes.new("ShaderNodeMath"); fire.operation = "ADD"
    links.new(shp.outputs[0], fire.inputs[0]); links.new(base.outputs[0], fire.inputs[1])

    ramp = nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.30; cr.elements[0].color = (0.25, 0.02, 0.0, 0.0)
    cr.elements[1].position = 0.42; cr.elements[1].color = (0.85, 0.12, 0.02, 0.85)
    e = cr.elements.new(0.58); e.color = (1.0, 0.45, 0.06, 1.0)
    e = cr.elements.new(0.75); e.color = (1.0, 0.85, 0.25, 1.0)
    e = cr.elements.new(0.92); e.color = (1.0, 0.98, 0.85, 1.0)
    links.new(fire.outputs[0], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], emit.inputs["Color"])
    emit.inputs["Strength"].default_value = 1.0
    links.new(transp.outputs[0], mix.inputs[1])
    links.new(emit.outputs[0], mix.inputs[2])
    links.new(ramp.outputs["Alpha"], mix.inputs["Fac"])
    links.new(mix.outputs[0], out.inputs["Surface"])
    plane.data.materials.append(m)
    return scene


def render_frames(scene):
    os.makedirs(TMP, exist_ok=True)
    paths = []
    for f in range(1, FRAMES + 1):
        scene.frame_set(f)
        p = os.path.join(TMP, "fire_%02d.png" % f)
        scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        paths.append(p)
    return paths


def compose(paths):
    sheet = bpy.data.images.new("FireSheet", COLS * FW, ROWS * FH, alpha=True)
    W = COLS * FW
    px = [0.0] * (W * ROWS * FH * 4)
    for i, p in enumerate(paths):
        img = bpy.data.images.load(p)
        fp = list(img.pixels)     # bottom-up rows
        col, row = i % COLS, i // COLS
        # sheet rows are bottom-up too; put frame 0 at the TOP-left (row 0 = top).
        sheet_row0 = (ROWS - 1 - row) * FH
        for y in range(FH):
            src = (y * FW) * 4
            dst = ((sheet_row0 + y) * W + col * FW) * 4
            px[dst:dst + FW * 4] = fp[src:src + FW * 4]
        bpy.data.images.remove(img)
    sheet.pixels = px
    sheet.filepath_raw = OUT
    sheet.file_format = "PNG"
    sheet.save()
    print("SHEET", OUT, COLS * FW, "x", ROWS * FH)


if __name__ == "__main__" and bpy.app.background:
    sc = build()
    try:
        frames = render_frames(sc)
    except Exception as e:  # Eevee refused in background: fall back to Cycles
        print("EEVEE failed (%s); falling back to Cycles" % e)
        sc.render.engine = "CYCLES"
        sc.cycles.samples = 16
        frames = render_frames(sc)
    compose(frames)
