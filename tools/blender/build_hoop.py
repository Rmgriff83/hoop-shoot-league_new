"""Build the Hoop Shoot hoop assembly in Blender: backboard, LED scoreboard housing
and face, backboard light band, board arm, rim bracket, rim and net.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_hoop.py

Produces  art/blender/hoop.blend  (source, ignored by Godot) and
          assets/models/hoop.glb  (game export, Y-up, transforms applied).

Coordinates: the assembly's origin is the RIM CENTRE. Sim space is x toward the
board, y up, z lateral; Blender is Z-up, so build with
    blender (x, y, z) = (sim x, -sim z, sim y)
and export +Y up (the exporter converts). Everything is a fixed offset from the
rim centre, so Godot positions the whole assembly by moving its root.

Animation-ready: parts are separate objects, RimPivot sits at the rim's mount
hinge (rim + net hang under it), and the net has 4 rings of edge loops.
"""
import math
import os
import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "hoop.blend")
GLB_PATH = os.path.join(ROOT, "assets", "hoops", "classic", "hoop.glb")
TEX = lambda name: os.path.join(ROOT, "assets", "textures", name)

# core/physics/sim_constants.gd + SimGeometry.arcade()
R_RIM = 0.2286
R_TUBE = 0.016
BOARD_OFF = 0.3796      # board face x, from the rim centre
BOARD_BOTTOM = -0.15    # relative to rim height
BOARD_TOP = 0.61
BOARD_HALF_W = 0.61
BOARD_THICK = 0.05
BRACKET_X0 = R_RIM - 0.01
BRACKET_X1 = BOARD_OFF
BRACKET_Y1 = 0.15
BRACKET_HALF_W = 0.2
NET_BOTTOM_R = 0.10
NET_HEIGHT = 0.42
LED_H = 0.24            # housing height above the board top
LED_D = 0.08
LED_FACE_W, LED_FACE_H = 1.14, 0.16
BAND_INSET, BAND_W = 0.03, 0.03
FACE_X = BOARD_OFF - 0.002   # surfaces 2 mm proud of the board face


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


def mat_tex(name, path, alpha_clip=False, double_sided=False):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    b = nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 1.0
    b.inputs["Metallic"].default_value = 0.0
    tex = nodes.new("ShaderNodeTexImage")
    tex.name = tex.label = "Skin"
    tex.location = (b.location.x - 420, b.location.y)
    img = bpy.data.images.get(os.path.basename(path)) or bpy.data.images.load(path)
    tex.image = img
    tex.interpolation = "Closest"
    links.new(tex.outputs["Color"], b.inputs["Base Color"])
    if alpha_clip:
        # glTF alphaMode MASK: exporter recognises a >0.5 threshold on alpha.
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


def add_box(name, size, center, mat, coll, parent):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = o.data.name = name
    o.scale = Vector(size)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    link_obj(o, coll, parent, center)
    return o


def add_quads_facing_minus_x(name, quads, mat, coll, parent, uv_along=None):
    """quads: list of (x, y0, y1, z0, z1). Faces point toward -x (the shooter).
    UVs: u increases toward screen-right (= -y), v up; uv_along overrides u as
    distance along the strip (metres × repeats/m) for tiling textures."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    for (x, y0, y1, z0, z1, *extra) in quads:
        v0 = bm.verts.new((x, y0, z0))
        v1 = bm.verts.new((x, y0, z1))
        v2 = bm.verts.new((x, y1, z1))
        v3 = bm.verts.new((x, y1, z0))
        f = bm.faces.new((v0, v1, v2, v3))   # winding chosen so the normal is -x
        for loop in f.loops:
            y, z = loop.vert.co.y, loop.vert.co.z
            if uv_along is None:
                u = (y1 - y) / (y1 - y0)
                v = (z - z0) / (z1 - z0)
            else:
                horizontal, repeats = extra[0], uv_along
                if horizontal:
                    u = (y1 - y) * repeats
                    v = (z - z0) / (z1 - z0)
                else:
                    u = (z - z0) * repeats
                    v = (y - y0) / (y1 - y0)
            loop[uv].uv = (u, v)
    bm.normal_update()
    for f in bm.faces:
        if f.normal.x > 0:
            f.normal_flip()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    link_obj(o, coll, parent, (0, 0, 0))
    return o


def build():
    for name in ("Cube",):
        if bpy.data.objects.get(name):
            bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
    for o in [o for o in bpy.data.objects if o.name.startswith(("Hoop", "Backboard", "Led", "Board", "Bracket", "Rim", "Net"))]:
        bpy.data.objects.remove(o, do_unlink=True)
    coll = bpy.data.collections.get("Hoop") or bpy.data.collections.new("Hoop")
    if coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)

    root = bpy.data.objects.new("HoopRoot", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.15
    link_obj(root, coll)

    # Materials
    board_body = mat_flat("Board_Body", (200, 205, 215))
    board_face = mat_tex("Board_Face", TEX("hoop_board.png"))
    dark = mat_flat("Housing_Dark", (30, 30, 36))
    metal = mat_flat("Bracket_Metal", (60, 64, 72))
    rim_mat = mat_tex("Rim", TEX("hoop_rim.png"))
    net_mat = mat_tex("Net", TEX("hoop_net.png"), alpha_clip=True, double_sided=True)
    led_mat = mat_tex("Led_Off", TEX("hoop_led_off.png"))
    band_mat = mat_tex("Band_Off", TEX("hoop_band.png"))
    band_mat.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 0.0

    # Backboard: body gray, front face textured (slot 1) with custom UVs.
    h = BOARD_TOP - BOARD_BOTTOM
    board = add_box("Backboard", (BOARD_THICK, BOARD_HALF_W * 2, h),
                    (BOARD_OFF + BOARD_THICK / 2, 0, (BOARD_TOP + BOARD_BOTTOM) / 2), board_body, coll, root)
    board.data.materials.append(board_face)
    bm = bmesh.new()
    bm.from_mesh(board.data)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        if f.normal.x < -0.5:  # the front face (toward the shooter)
            f.material_index = 1
            for loop in f.loops:
                y, z = loop.vert.co.y, loop.vert.co.z
                loop[uv].uv = ((BOARD_HALF_W - y) / (2 * BOARD_HALF_W), (z + h / 2) / h)
    bm.to_mesh(board.data)
    bm.free()

    # LED scoreboard housing on top of the board, front bezel flush with the face.
    add_box("LedHousing", (LED_D, BOARD_HALF_W * 2, LED_H),
            (BOARD_OFF + LED_D / 2, 0, BOARD_TOP + LED_H / 2), dark, coll, root)
    zc = BOARD_TOP + LED_H / 2
    add_quads_facing_minus_x("LedFace", [(FACE_X, -LED_FACE_W / 2, LED_FACE_W / 2,
                                          zc - LED_FACE_H / 2, zc + LED_FACE_H / 2)], led_mat, coll, root)

    # Backboard light band: a frame just inside the trim, tiled along its length.
    yo, yi = BOARD_HALF_W - BAND_INSET, BOARD_HALF_W - BAND_INSET - BAND_W
    zb0, zb1 = BOARD_BOTTOM + BAND_INSET, BOARD_TOP - BAND_INSET
    rep = 10.0  # texture repeats per metre (64 px = 8 segments per 10 cm)
    add_quads_facing_minus_x("BoardBand", [
        (FACE_X, -yo, yo, zb1 - BAND_W, zb1, True),      # top run
        (FACE_X, -yo, yo, zb0, zb0 + BAND_W, True),      # bottom run
        (FACE_X, -yo, -yi, zb0 + BAND_W, zb1 - BAND_W, False),  # side (+z sim / -y blender)
        (FACE_X, yi, yo, zb0 + BAND_W, zb1 - BAND_W, False),    # side
    ], band_mat, coll, root, uv_along=rep)

    # Arm from the board's back to the pole line (pole = board face + 0.3 m).
    add_box("BoardArm", (0.25, 0.10, 0.06), (BOARD_OFF + BOARD_THICK + 0.125, 0, 0.35), metal, coll, root)

    # Rim bracket: sloped plate from the back of the rim up to the board face.
    dx, dz = BRACKET_X1 - BRACKET_X0, BRACKET_Y1
    length = math.hypot(dx, dz)
    br = add_box("Bracket", (length, BRACKET_HALF_W * 2, 0.03),
                 ((BRACKET_X0 + BRACKET_X1) / 2, 0, dz / 2), metal, coll, root)
    br.rotation_euler = (0, -math.atan2(dz, dx), 0)

    # Rim pivot (mount hinge) at the back edge of the rim; rim + net hang under it.
    pivot = bpy.data.objects.new("RimPivot", None)
    pivot.empty_display_type = "SPHERE"
    pivot.empty_display_size = 0.05
    link_obj(pivot, coll, root, (R_RIM, 0, 0))

    bpy.ops.mesh.primitive_torus_add(major_radius=R_RIM, minor_radius=R_TUBE,
                                     major_segments=20, minor_segments=6, location=(0, 0, 0))
    rim = bpy.context.active_object
    rim.name = rim.data.name = "Rim"
    rim.data.materials.append(rim_mat)
    link_obj(rim, coll, pivot, (-R_RIM, 0, 0))

    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=R_RIM, depth=NET_HEIGHT,
                                        end_fill_type="NOTHING", location=(0, 0, 0))
    net = bpy.context.active_object
    net.name = net.data.name = "Net"
    bm = bmesh.new()
    bm.from_mesh(net.data)
    # 4 rings of edge loops so the net can deform later (shape keys / bones).
    vertical = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 1e-6]
    bmesh.ops.subdivide_edges(bm, edges=vertical, cuts=3, use_grid_fill=True)
    # Taper: radius shrinks linearly from R_RIM at the top to NET_BOTTOM_R at the bottom.
    for v in bm.verts:
        t = (NET_HEIGHT / 2 - v.co.z) / NET_HEIGHT     # 0 at top, 1 at bottom
        r = R_RIM + (NET_BOTTOM_R - R_RIM) * t
        ang = math.atan2(v.co.y, v.co.x)
        v.co.x, v.co.y = r * math.cos(ang), r * math.sin(ang)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for loop in f.loops:
            u, vv = loop[uv].uv
            loop[uv].uv = (u * 3.0, vv)   # tile the lattice 3× around
    bm.to_mesh(net.data)
    bm.free()
    net.data.materials.append(net_mat)
    link_obj(net, coll, pivot, (-R_RIM, 0, -NET_HEIGHT / 2))

    # Flat shading everywhere, transforms applied on meshes (not the empties).
    meshes = [o for o in coll.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.shade_flat()
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return coll


def save_and_export(coll):
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bpy.ops.object.select_all(action="DESELECT")
    for o in coll.objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH, export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_materials="EXPORT", export_image_format="AUTO",
        export_animations=False,
    )


if __name__ == "__main__":
    c = build()
    save_and_export(c)
    for o in c.objects:
        d = tuple(round(x, 3) for x in o.dimensions) if o.type == "MESH" else "-"
        print("OBJ %-12s parent=%-9s loc=%s dims=%s" % (
            o.name, o.parent.name if o.parent else "-", tuple(round(x, 3) for x in o.location), d))
    print("SAVED", BLEND_PATH)
    print("EXPORTED", GLB_PATH)
