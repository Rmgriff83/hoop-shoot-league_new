"""Capture Blender UI screenshots of basketball.blend for docs/BLENDER_101.md.

Run (GUI mode, window pops up for a few seconds then closes):
  /Applications/Blender.app/Contents/MacOS/Blender -p 0 0 1600 1000 \
      art/blender/basketball.blend --python tools/blender/ui_screenshots.py
"""
import os
import traceback
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "docs", "img", "blender")
os.makedirs(OUT, exist_ok=True)

STEP = {"i": 0}


def ctx_bits():
    wm = bpy.context.window_manager
    win = wm.windows[0]
    screen = win.screen
    v3d = next(a for a in screen.areas if a.type == "VIEW_3D")
    region = next(r for r in v3d.regions if r.type == "WINDOW")
    props = next((a for a in screen.areas if a.type == "PROPERTIES"), None)
    return win, screen, v3d, region, props


def shot(name):
    win, screen, v3d, region, props = ctx_bits()
    with bpy.context.temp_override(window=win, screen=screen, area=v3d, region=region):
        bpy.ops.screen.screenshot(filepath=os.path.join(OUT, name))
    print("SHOT", name)


def select_ball():
    ball = bpy.data.objects["Basketball"]
    bpy.ops.object.select_all(action="DESELECT")
    ball.select_set(True)
    bpy.context.view_layer.objects.active = ball
    return ball


def frame():
    win, screen, v3d, region, props = ctx_bits()
    with bpy.context.temp_override(window=win, screen=screen, area=v3d, region=region):
        bpy.ops.view3d.view_selected()


def set_props_tab(tab):
    win, screen, v3d, region, props = ctx_bits()
    if props:
        try:
            props.spaces[0].context = tab
        except TypeError as e:
            print("props tab", tab, e)


def steps():
    win, screen, v3d, region, props = ctx_bits()
    space = v3d.spaces[0]
    i = STEP["i"]
    win, screen, v3d, region, props = ctx_bits()
    with bpy.context.temp_override(window=win, screen=screen, area=v3d, region=region):
        if i == 0:
            select_ball()
            space.shading.type = "MATERIAL"
            space.show_region_ui = True       # N sidebar
            space.show_region_toolbar = True  # T toolbar
            set_props_tab("OBJECT")
            frame()
        elif i == 1:
            shot("01_layout_overview.png")
            set_props_tab("MATERIAL")
        elif i == 2:
            shot("02_material_tab.png")
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_mode(type="FACE")
            bpy.ops.mesh.select_all(action="SELECT")
        elif i == 3:
            shot("03_edit_mode_faces.png")
            space.shading.type = "WIREFRAME"
            bpy.ops.mesh.select_all(action="DESELECT")
            bpy.ops.mesh.select_mode(type="VERT")
        elif i == 4:
            shot("04_edit_mode_wireframe.png")
            bpy.ops.object.mode_set(mode="OBJECT")
            space.shading.type = "SOLID"
            set_props_tab("DATA")
        elif i == 5:
            shot("05_object_mode_solid.png")
            win.workspace = bpy.data.workspaces["UV Editing"]
        elif i == 6:
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_mode(type="FACE")
            bpy.ops.mesh.select_all(action="SELECT")
            img = bpy.data.images.get("ball_wrap.png")
            for a in win.screen.areas:
                if a.type == "IMAGE_EDITOR" and img:
                    a.spaces[0].image = img
                if a.type == "VIEW_3D":
                    a.spaces[0].shading.type = "MATERIAL"
        elif i == 7:
            # Frame both panes now that the workspace has drawn once.
            for a in win.screen.areas:
                r = next((r for r in a.regions if r.type == "WINDOW"), None)
                if a.type == "IMAGE_EDITOR":
                    with bpy.context.temp_override(window=win, screen=win.screen, area=a, region=r):
                        bpy.ops.image.view_all(fit_view=True)
                if a.type == "VIEW_3D":
                    with bpy.context.temp_override(window=win, screen=win.screen, area=a, region=r):
                        bpy.ops.view3d.view_selected()
        elif i == 8:
            shot("06_uv_editing.png")
        elif i == 9:
            os._exit(0)  # hard exit: skips the "save changes?" prompt
    STEP["i"] += 1
    return 0.8


def safe_steps():
    try:
        return steps()
    except Exception:
        with open(os.path.join(OUT, "_error.log"), "a") as f:
            f.write(f"step {STEP['i']}\n" + traceback.format_exc())
        os._exit(1)


bpy.app.timers.register(safe_steps, first_interval=2.0)
