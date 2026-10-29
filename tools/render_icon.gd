extends SceneTree
## The app icon set from Ross's final icon (design 46b NEON BALL, 2026-10-28:
## the neon basketball on the brick wall, drawn on a 128-cell grid and
## exported at 1024 as assets/icon/icon_1024.png — iOS and the editor take
## that file as is). This writes the Android files beside it:
##   android_192.png      the legacy launcher icon, the 1024 nearest-scaled;
##   adaptive_bg_432.png  a brick wall at 2.7 px per cell, tiled from the
##                        icon's own ball-free border bricks (the wall's
##                        period is 16 cells, the border is 16 cells wide);
##   adaptive_fg_432.png  only the ball and its glow, on transparency, on
##                        the same cell grid so the mortar lines meet.
## 160 cells across the 432 canvas puts the icon's 128 cells 16 in from
## every edge: the tube spans ~243 px, the glow ~259, inside Android's
## 264 px safe circle, with bricks showing all round.
## One-off, after a new icon_1024.png:
##   godot --headless --path . -s tools/render_icon.gd && godot --headless --path . --import

const SRC := "res://assets/icon/icon_1024.png"
const OUT := "res://assets/icon"
const CELLS := 128       # the icon's pixel grid
const CELL_PX := 8       # 1024 / 128
const CANVAS := 432      # Android adaptive layers
const CANVAS_CELLS := 160
const INSET := 16        # (CANVAS_CELLS - CELLS) / 2 — a brick period, so the bond lines up
const PERIOD := 16       # two brick rows: the wall repeats every 16 cells both ways
const GLOW_LO := 16      # the ball + glow live in cells 16..111
const GLOW_HI := 111


func _initialize() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	if src == null or src.get_width() != CELLS * CELL_PX:
		push_error("no %dpx icon at %s" % [CELLS * CELL_PX, SRC])
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)
	# The 128 grid, one colour per cell.
	var grid: Array[Color] = []
	grid.resize(CELLS * CELLS)
	for y in CELLS:
		for x in CELLS:
			grid[y * CELLS + x] = src.get_pixel(x * CELL_PX + CELL_PX / 2, y * CELL_PX + CELL_PX / 2)
	# Legacy launcher: the whole icon, nearest.
	var legacy := src.duplicate()
	legacy.resize(192, 192, Image.INTERPOLATE_NEAREST)
	_save(legacy, "android_192.png")
	# Which cells are the ball or its glow: every colour outside the glow
	# square is a plain brick or mortar; inside it, any cell NOT one of those
	# colours is the tube, its core, or a brick the glow has tinted.
	var brick := {}
	for y in CELLS:
		for x in CELLS:
			if not _in_glow(x, y):
				brick[grid[y * CELLS + x].to_rgba32()] = true
	var bg := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	var fg := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	fg.fill(Color(0, 0, 0, 0))
	# The wall: every 16×16 period tile of the canvas is one of the icon's
	# 28 ball-free border tiles, picked by a fixed hash so the tints vary
	# the way the icon's do.
	var tiles: Array[Vector2i] = []
	for ty in CELLS / PERIOD:
		for tx in CELLS / PERIOD:
			var free := true
			for y in PERIOD:
				for x in PERIOD:
					if _in_glow(tx * PERIOD + x, ty * PERIOD + y):
						free = false
			if free:
				tiles.push_back(Vector2i(tx * PERIOD, ty * PERIOD))
	for cy in CANVAS_CELLS:
		for cx in CANVAS_CELLS:
			var t: Vector2i = tiles[((cx / PERIOD) * 7 + (cy / PERIOD) * 13 + (cx / PERIOD) * (cy / PERIOD)) % tiles.size()]
			_cell(bg, cx, cy, grid[(t.y + cy % PERIOD) * CELLS + t.x + cx % PERIOD])
	# The ball + glow, cell for cell, 16 cells in.
	var lit := 0
	for y in CELLS:
		for x in CELLS:
			var c := grid[y * CELLS + x]
			if _in_glow(x, y) and not brick.has(c.to_rgba32()):
				_cell(fg, x + INSET, y + INSET, c)
				lit += 1
	print("icon: %d wall tiles, %d brick colours, %d lit cells" % [tiles.size(), brick.size(), lit])
	_save(bg, "adaptive_bg_432.png")
	_save(fg, "adaptive_fg_432.png")
	quit()


func _in_glow(x: int, y: int) -> bool:
	return x >= GLOW_LO and x <= GLOW_HI and y >= GLOW_LO and y <= GLOW_HI


## Canvas cell `cx` spans px [floor(cx·2.7), floor((cx+1)·2.7)).
func _cell(img: Image, cx: int, cy: int, c: Color) -> void:
	var x0 := cx * CANVAS / CANVAS_CELLS
	var x1 := (cx + 1) * CANVAS / CANVAS_CELLS
	var y0 := cy * CANVAS / CANVAS_CELLS
	var y1 := (cy + 1) * CANVAS / CANVAS_CELLS
	img.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), c)


func _save(img: Image, name_: String) -> void:
	var path := OUT + "/" + name_
	var err := img.save_png(path)
	print("icon %s %dpx %s" % [path, img.get_width(), "ok" if err == OK else "FAILED %d" % err])
