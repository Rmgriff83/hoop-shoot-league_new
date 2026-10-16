"""Conform the PSX Trees pack (art/third_party/psx_trees, DanglingBat) into
shipped park assets: each model's glb re-exported with ONLY its base-colour
texture (the pack's normal / roughness / AO maps are dropped), the texture
downsampled to 256² and filtered Closest, the leaves' alpha kept as a cut-out,
every material flat-shaded. Writes assets/arena/park/trees/<id>.glb.

  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/conform_psx_trees.py -- --force

The licence (the pack's LICENSE.txt) forbids redistributing the assets on
their own: these copies ship inside the game only.
"""
import os
import sys

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.path.join(ROOT, "art", "third_party", "psx_trees", "models")
OUT = os.path.join(ROOT, "assets", "arena", "park", "trees")
TEX_SIZE = 256
MODELS = [
    "pine_tree_01_a", "pine_tree_01_b", "pine_tree_01_c", "aspen_tree_01", "aspen_tree_02",
    "pine_tree_stump_01", "pine_tree_trunk_01", "fallen_pine_tree_01", "dead_branch_01", "dead_branch_02",
    "rock_01_large", "rock_01_large_mossy", "rock_01_small", "rock_01_small_mossy",
]


def strip_material(m):
    """Keep the Base Color image (and its alpha), drop every other texture.
    Node references go stale when the tree changes, so everything is done
    by name and the base node is re-fetched after the removals."""
    if not m.use_nodes:
        return
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return
    base_name = None
    alpha_linked = False
    for l in links:
        if l.to_node == bsdf and l.to_socket.name == "Base Color" and l.from_node.type == "TEX_IMAGE":
            base_name = l.from_node.name
        if l.to_node == bsdf and l.to_socket.name == "Alpha":
            alpha_linked = True
    doomed = [n.name for n in nodes if (n.type == "TEX_IMAGE" and n.name != base_name)
              or n.type in ("NORMAL_MAP", "SEPARATE_COLOR", "SEPARATE_RGB", "MIX", "MIX_RGB", "DISPLACEMENT", "BUMP")]
    for l in [l for l in links if l.to_node == bsdf and l.to_socket.name not in ("Base Color", "Alpha")]:
        links.remove(l)
    for name in doomed:
        n = nodes.get(name)
        if n is not None:
            nodes.remove(n)
    bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    bsdf.inputs["Roughness"].default_value = 0.95
    bsdf.inputs["Metallic"].default_value = 0.0
    for key in ("Specular IOR Level", "Specular"):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = 0.1
            break
    base = nodes.get(base_name) if base_name else None
    if base is not None:
        base.interpolation = "Closest"
        img = base.image
        if img is not None and (img.size[0] > TEX_SIZE or img.size[1] > TEX_SIZE):
            img.scale(TEX_SIZE, TEX_SIZE)
    # The leaves: a hard cut, never a blend (no sorting on the phone).
    if alpha_linked:
        for attr, val in (("blend_method", "CLIP"), ("surface_render_method", "DITHERED")):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
        m.use_backface_culling = False
        try:
            m.alpha_threshold = 0.45
        except Exception:
            pass


def conform(model_id):
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, model_id + ".glb"))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.shade_flat()
        for slot in o.material_slots:
            if slot.material is not None:
                strip_material(slot.material)
    for img in list(bpy.data.images):
        if img.users == 0:
            bpy.data.images.remove(img)
    bpy.ops.object.select_all(action="SELECT")
    out = os.path.join(OUT, model_id + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=False, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_image_format="AUTO",
                              export_animations=False)
    print("conformed %s -> %s (%d bytes)" % (model_id, out, os.path.getsize(out)))


if __name__ == "__main__" and bpy.app.background:
    os.makedirs(OUT, exist_ok=True)
    if os.listdir(OUT) and "--force" not in sys.argv:
        print("REFUSING: %s has files. Re-run with `-- --force` to rebuild." % OUT)
        sys.exit(0)
    for m in MODELS:
        conform(m)
    print("psx trees: %d models" % len(MODELS))
