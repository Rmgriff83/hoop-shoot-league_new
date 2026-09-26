"""Build the rim's ice (cold streak) in Blender: a jagged ring of ice sitting on
top of the rim that reaches a little way in toward the centre, split into
shards the game flings apart when the ice breaks, plus a few icicles.

Creator script — refuses to overwrite art/blender/rim_ice.blend (hand edits
live there) unless run with `-- --force`. Exports assets/fx/rim_ice.glb.

  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_rim_ice.py
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_rim_ice.py -- --force
Inside Blender (Text Editor / MCP) with rim_ice.blend open:
  exec(open("tools/blender/build_rim_ice.py").read()); export_glb()

Objects (all in the `RimIce` collection, origin = the rim's centre at the
rim's top plane, +Z up in Blender → +Y up in Godot):
  Shard00..11   wedge pieces of the ring (origin at each shard's centroid)
  Icicle0..3    small icicles hanging under the ring
The game (game/view/rim_ice.gd) shades them with game/court/ice.gdshader,
freezes them in from the outside edge, and shatters them.

Knobs: R_RIM matches SimConstants.R_RIM; LIP is how far the ice reaches in;
JAG the inner-edge roughness; SHARDS the piece count.
"""
import math
import os
import random
import sys
import bpy
import bmesh

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else \
    "/Users/rossgriffus/Documents/projects/godot/hoop_shoot/tools/blender"
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "rim_ice.blend")
GLB_PATH = os.path.join(ROOT, "assets", "fx", "rim_ice.glb")

R_RIM = 0.2286
R_OUT = R_RIM + 0.022      # hugs the outside of the rod
LIP = 0.13                 # how far in the ice reaches: the hole (~10 cm) is smaller than the ball (12 cm)
JAG = 0.03                 # inner-edge roughness (m)
ROCK = 0.014               # top-surface lumpiness (m)
CHUNKS = 3                 # rocky chunks piled on each shard
THICK = 0.02
SHARDS = 12
ICICLES = 4
SEED = 7


def _jag(rng, a):
    """Deterministic bumpy inner radius: a few sine harmonics + noise."""
    return (R_RIM - LIP
            + JAG * (0.5 * math.sin(a * 7.0 + 0.4) + 0.3 * math.sin(a * 13.0 + 2.1)
                     + 0.2 * math.sin(a * 23.0 + 5.0) + (rng.random() - 0.5) * 0.6))


def _rock(rng, a, r):
    """Top-surface height: lumpy, rising a little toward the rim."""
    return ROCK * (0.5 + 0.5 * math.sin(a * 11.0 + r * 90.0) * math.sin(a * 5.0 + 1.3)
                   + (rng.random() - 0.5) * 0.8)


def _placeholder_material():
    m = bpy.data.materials.get("IcePlaceholder")
    if m is None:
        m = bpy.data.materials.new("IcePlaceholder")
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (0.78, 0.9, 1.0, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.15
            try:
                bsdf.inputs["Alpha"].default_value = 0.6
            except KeyError:
                pass
    return m


def _shard(coll, idx, a0, a1, rng):
    """One wedge of the ring between angles a0..a1 (irregular seam offsets baked in)."""
    steps = 8
    bm = bmesh.new()
    top, bot = [], []
    for i in range(steps + 1):
        a = a0 + (a1 - a0) * i / steps
        ri = _jag(rng, a)
        ro = R_OUT + (rng.random() - 0.5) * 0.006
        vo_t = bm.verts.new((ro * math.cos(a), ro * math.sin(a), _rock(rng, a, ro)))
        vi_t = bm.verts.new((ri * math.cos(a), ri * math.sin(a), _rock(rng, a, ri) * 0.6))
        vo_b = bm.verts.new((ro * math.cos(a), ro * math.sin(a), -THICK))
        vi_b = bm.verts.new((ri * math.cos(a), ri * math.sin(a), -THICK))
        top.append((vo_t, vi_t))
        bot.append((vo_b, vi_b))
    for i in range(steps):
        (o0, i0), (o1, i1) = top[i], top[i + 1]
        (bo0, bi0), (bo1, bi1) = bot[i], bot[i + 1]
        bm.faces.new((o0, o1, i1, i0))          # top
        bm.faces.new((bi0, bi1, bo1, bo0))      # bottom
        bm.faces.new((o0, bo0, bo1, o1))        # outer wall
        bm.faces.new((i1, bi1, bi0, i0))        # inner (jagged) wall
    # end caps
    bm.faces.new((top[0][0], top[0][1], bot[0][1], bot[0][0]))
    bm.faces.new((top[-1][1], top[-1][0], bot[-1][0], bot[-1][1]))
    # Rocky chunks piled on top: small tumbled boxes fused into the shard.
    for c in range(CHUNKS):
        a = a0 + (a1 - a0) * (0.2 + 0.6 * rng.random())
        r = R_RIM - LIP * (0.15 + 0.7 * rng.random())
        size = 0.012 + rng.random() * 0.016
        mat = (bpy.mathutils_Matrix if False else None)
        import mathutils
        m = (mathutils.Matrix.Translation((r * math.cos(a), r * math.sin(a), size * 0.35))
             @ mathutils.Euler((rng.random() * 1.2, rng.random() * 1.2, rng.random() * 3.1)).to_matrix().to_4x4()
             @ mathutils.Matrix.Diagonal((size, size * (0.6 + rng.random() * 0.6), size * 0.7, 1.0)))
        bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Shard%02d" % idx)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Shard%02d" % idx, me)
    coll.objects.link(ob)
    ob.data.materials.append(_placeholder_material())
    # Origin at the shard's centroid so the game can spin it about itself.
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="MEDIAN")
    ob.select_set(False)
    return ob


def _icicle(coll, idx, a, rng):
    length = 0.035 + rng.random() * 0.03
    r0 = 0.006 + rng.random() * 0.003
    rad = R_RIM - LIP * 0.35
    bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=r0, radius2=0.0, depth=length,
                                    location=(rad * math.cos(a), rad * math.sin(a), -THICK - length / 2.0),
                                    rotation=(math.pi, 0.0, 0.0))
    ob = bpy.context.active_object
    ob.name = "Icicle%d" % idx
    ob.data.name = "Icicle%d" % idx
    ob.data.materials.append(_placeholder_material())
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    coll.objects.link(ob)
    ob.select_set(False)
    return ob


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    rng = random.Random(SEED)
    coll = bpy.data.collections.new("RimIce")
    bpy.context.scene.collection.children.link(coll)
    # Irregular seams: nudge each boundary angle a little.
    seams = [2 * math.pi * i / SHARDS + (rng.random() - 0.5) * (2 * math.pi / SHARDS) * 0.35 for i in range(SHARDS)]
    seams.append(seams[0] + 2 * math.pi)
    for i in range(SHARDS):
        _shard(coll, i, seams[i], seams[i + 1], rng)
    for i in range(ICICLES):
        a = 2 * math.pi * (i + 0.5) / ICICLES + (rng.random() - 0.5) * 0.5
        _icicle(coll, i, a, rng)
    bpy.context.scene.frame_set(1)
    return coll


def export_glb(path=GLB_PATH):
    coll = bpy.data.collections["RimIce"]
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    for o in coll.all_objects:
        o.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_materials="EXPORT", export_animations=False,
    )
    bpy.ops.object.select_all(action="DESELECT")
    print("EXPORTED", path)


if __name__ == "__main__" and bpy.app.background:
    if os.path.exists(BLEND_PATH) and "--force" not in sys.argv:
        print("REFUSING: %s exists (hand edits live there). Re-run with `-- --force` to rebuild from scratch,"
              " or open it in Blender and export_glb() from the live file." % BLEND_PATH)
        sys.exit(2)
    build()
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("SAVED", BLEND_PATH)
    export_glb()
