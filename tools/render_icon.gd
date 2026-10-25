extends SceneTree
## The placeholder app icon (2026-10-24): the game's own 22×22 pixel ball
## (assets/ui/icon_ball.png) nearest-scaled onto the ink, written as every
## size the two presets want under assets/icon/. One-off:
##   godot --headless --path . -s tools/render_icon.gd && godot --headless --path . --import
## Rerun when the real icon lands (or drop the real PNGs over these).

const BALL := "res://assets/ui/icon_ball.png"
const OUT := "res://assets/icon"
const INK := Color("#221C18")   # RetroTheme.SCENE_OUTLINE

## [file, size, background, ball px] — the adaptive foreground keeps the ball
## inside Android's 264 px safe circle on the 432 canvas.
const SIZES := [
	["icon_1024.png", 1024, INK, 22 * 36],
	["android_192.png", 192, INK, 22 * 6],
	["adaptive_fg_432.png", 432, Color(0, 0, 0, 0), 22 * 10],
	["adaptive_bg_432.png", 432, INK, 0],
]


func _initialize() -> void:
	var tex: Texture2D = load(BALL)
	if tex == null:
		push_error("no ball icon at " + BALL)
		quit(1)
		return
	var ball := tex.get_image()
	ball.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for s in SIZES:
		var size_ := int(s[1])
		var img := Image.create(size_, size_, false, Image.FORMAT_RGBA8)
		img.fill(s[2])
		var px := int(s[3])
		if px > 0:
			var b := ball.duplicate()
			b.resize(px, px, Image.INTERPOLATE_NEAREST)
			var at := Vector2i((size_ - px) / 2, (size_ - px) / 2)
			img.blend_rect(b, Rect2i(0, 0, px, px), at)
		var path := OUT + "/" + str(s[0])
		var err := img.save_png(path)
		print("icon %s %dpx %s" % [path, size_, "ok" if err == OK else "FAILED %d" % err])
	quit()
