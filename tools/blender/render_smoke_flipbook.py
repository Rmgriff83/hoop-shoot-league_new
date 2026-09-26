"""Author the rim's smoke puff in Blender and render it to a one-shot flipbook
(game/view/rim_fire.gd + game/court/smoke_puff.gdshader play it once on each
of a few billboards around the ring when the fire goes out).

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/render_smoke_flipbook.py

Output: assets/textures/fx_smoke_sheet.png — 4 x 4 frames of 128 x 128, RGBA,
frame 0 top-left: a small dense puff low in the frame that rises, swells and
thins to nothing by the last frame (not a loop).

Procedural node material: a 4D noise (W advancing with the frame) masked by a
soft disc whose centre rises and whose radius grows with the frame, faded out
toward the end. Tweak SIZE/RISE/DENSITY below and re-run.
"""
import math
import os
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "fx_smoke_sheet.png")
TMP = os.path.join(ROOT, ".godot", "smoke_frames")
FRAMES = 16
COLS, ROWS = 4, 4
FW, FH = 128, 128
SIZE = (0.17, 0.44)     # disc radius at the first / last frame (uv units)
RISE = (0.30, 0.66)     # disc centre height at the first / last frame
DENSITY = 2.0           # noise contrast (wisps + holes)
EDGE = 0.8              # how much the noise breaks the disc's round edge
GAIN = 1.5              # overall opacity


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

    cam_data = bpy.data.cameras.new("SmokeCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.0
    cam = bpy.data.objects.new("SmokeCam", cam_data)
    cam.location = (0.0, -3.0, 0.0)
    cam.rotation_euler = (math.pi / 2, 0.0, 0.0)
    scene.collection.objects.link(cam)
    scene.camera = cam

    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, 0), rotation=(math.pi / 2, 0, 0))
    plane = bpy.context.active_object
    plane.name = "SmokePlane"

    m = bpy.data.materials.new("Smoke")
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

    # p = 0 → 1 over the 16 frames (linear keys).
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
    p = nodes.new("ShaderNodeValue"); p.name = "Progress"; p.label = "Progress"
    p.outputs[0].default_value = 0.0
    p.outputs[0].keyframe_insert("default_value", frame=1)
    p.outputs[0].default_value = 1.0
    p.outputs[0].keyframe_insert("default_value", frame=FRAMES)

    def lerp_node(a, b):
        n = nodes.new("ShaderNodeMath"); n.operation = "MULTIPLY_ADD"
        links.new(p.outputs[0], n.inputs[0])
        n.inputs[1].default_value = b - a
        n.inputs[2].default_value = a
        return n

    radius = lerp_node(*SIZE)
    cy = lerp_node(*RISE)
    center = nodes.new("ShaderNodeCombineXYZ")
    center.inputs["X"].default_value = 0.5
    links.new(cy.outputs[0], center.inputs["Y"])
    dist = nodes.new("ShaderNodeVectorMath"); dist.operation = "DISTANCE"
    links.new(coord.outputs["UV"], dist.inputs[0]); links.new(center.outputs[0], dist.inputs[1])
    d = nodes.new("ShaderNodeMath"); d.operation = "DIVIDE"
    links.new(dist.outputs["Value"], d.inputs[0]); links.new(radius.outputs[0], d.inputs[1])
    # Break the round edge with a coarse noise: d += (noise - 0.5) * EDGE
    en = nodes.new("ShaderNodeTexNoise")
    en.noise_dimensions = "4D"
    en.inputs["Scale"].default_value = 2.0
    en.inputs["Detail"].default_value = 2.0
    links.new(coord.outputs["UV"], en.inputs["Vector"])
    eshift = nodes.new("ShaderNodeMath"); eshift.operation = "MULTIPLY_ADD"
    links.new(en.outputs["Fac"], eshift.inputs[0])
    eshift.inputs[1].default_value = EDGE; eshift.inputs[2].default_value = -0.5 * EDGE
    dd = nodes.new("ShaderNodeMath"); dd.operation = "ADD"
    links.new(d.outputs[0], dd.inputs[0]); links.new(eshift.outputs[0], dd.inputs[1])
    d2 = nodes.new("ShaderNodeMath"); d2.operation = "MULTIPLY"
    links.new(dd.outputs[0], d2.inputs[0]); links.new(dd.outputs[0], d2.inputs[1])
    disc = nodes.new("ShaderNodeMath"); disc.operation = "SUBTRACT"; disc.use_clamp = True
    disc.inputs[0].default_value = 1.0
    links.new(d2.outputs[0], disc.inputs[1])          # 1 - (d/r)^2, clamped

    # Wispy noise that rolls upward with the frame.
    w = nodes.new("ShaderNodeMath"); w.operation = "MULTIPLY"; w.inputs[1].default_value = 1.6
    links.new(p.outputs[0], w.inputs[0])
    nz = nodes.new("ShaderNodeTexNoise")
    nz.noise_dimensions = "4D"
    nz.inputs["Scale"].default_value = 5.0
    nz.inputs["Detail"].default_value = 5.0
    nz.inputs["Roughness"].default_value = 0.6
    links.new(coord.outputs["UV"], nz.inputs["Vector"])
    links.new(w.outputs[0], nz.inputs["W"])
    links.new(w.outputs[0], en.inputs["W"])
    con = nodes.new("ShaderNodeMath"); con.operation = "MULTIPLY_ADD"
    links.new(nz.outputs["Fac"], con.inputs[0])
    con.inputs[1].default_value = DENSITY; con.inputs[2].default_value = -0.55
    dens = nodes.new("ShaderNodeMath"); dens.operation = "MULTIPLY"; dens.use_clamp = True
    links.new(con.outputs[0], dens.inputs[0]); links.new(disc.outputs[0], dens.inputs[1])
    # Fade: (1 - p)^1.3, plus a quick bloom-in over the first frame.
    inv = nodes.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
    links.new(p.outputs[0], inv.inputs[1])
    fade = nodes.new("ShaderNodeMath"); fade.operation = "POWER"; fade.inputs[1].default_value = 1.3
    links.new(inv.outputs[0], fade.inputs[0])
    alpha0 = nodes.new("ShaderNodeMath"); alpha0.operation = "MULTIPLY"
    links.new(dens.outputs[0], alpha0.inputs[0]); links.new(fade.outputs[0], alpha0.inputs[1])
    alpha = nodes.new("ShaderNodeMath"); alpha.operation = "MULTIPLY"; alpha.use_clamp = True
    links.new(alpha0.outputs[0], alpha.inputs[0]); alpha.inputs[1].default_value = GAIN

    # Colour: mid grey, a little lighter where dense (lit from above).
    ramp = nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0; cr.elements[0].color = (0.26, 0.26, 0.3, 1.0)
    cr.elements[1].position = 1.0; cr.elements[1].color = (0.5, 0.5, 0.55, 1.0)
    links.new(dens.outputs[0], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], emit.inputs["Color"])
    links.new(transp.outputs[0], mix.inputs[1])
    links.new(emit.outputs[0], mix.inputs[2])
    links.new(alpha.outputs[0], mix.inputs["Fac"])
    links.new(mix.outputs[0], out.inputs["Surface"])
    plane.data.materials.append(m)
    return scene


def render_frames(scene):
    os.makedirs(TMP, exist_ok=True)
    paths = []
    for f in range(1, FRAMES + 1):
        scene.frame_set(f)
        pth = os.path.join(TMP, "smoke_%02d.png" % f)
        scene.render.filepath = pth
        bpy.ops.render.render(write_still=True)
        paths.append(pth)
    return paths


def compose(paths):
    sheet = bpy.data.images.new("SmokeSheet", COLS * FW, ROWS * FH, alpha=True)
    W = COLS * FW
    px = [0.0] * (W * ROWS * FH * 4)
    for i, pth in enumerate(paths):
        img = bpy.data.images.load(pth)
        fp = list(img.pixels)
        col, row = i % COLS, i // COLS
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
    except Exception as e:
        print("EEVEE failed (%s); falling back to Cycles" % e)
        sc.render.engine = "CYCLES"
        sc.cycles.samples = 16
        frames = render_frames(sc)
    compose(frames)
