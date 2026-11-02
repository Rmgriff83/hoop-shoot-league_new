extends SceneTree
## The app icon set (design 46b NEON BALL, 2026-10-28; the wall swapped
## 2026-11-02): the neon basketball from Ross's final icon — kept as
## art/icon/icon_1024_design46b.png, drawn on a 128-cell grid over the old
## pixel brick — lifted off that brick (the ball and its glow as an additive
## layer, the old wall estimated from the icon's own ball-free border tiles,
## period 16 cells) and laid on the splash's wall: Pizza Doggy's
## `brick_wall_pt_2` (tools/render_brick_wall.gd) at one tile pixel per cell,
## so its pixels match the ball's, darkened like the splash. Writes:
##   icon_1024.png        iOS and the editor take it as is (8 px per cell);
##   android_192.png      the legacy launcher icon, nearest-scaled;
##   adaptive_bg_432.png  the wall alone at 2.7 px per cell;
##   adaptive_fg_432.png  the ball and its glow on transparency, on the same
##                        cell grid, 16 cells in (the tube ~243 px, the glow
##                        ~259, inside Android's 264 px safe circle).
## One-off, after a change here or to the sources:
##   godot --headless --path . -s tools/render_icon.gd && godot --headless --path . --import
## Previews (nothing in assets/ touched):
##   godot --headless --path . -s tools/render_icon.gd -- --preview=/tmp/x.png --dark=0.5 --offset=64,32

const DESIGN := "res://art/icon/icon_1024_design46b.png"
const WALL := "res://art/third_party/pizza_doggy/brick_wall_pt_2.png"
const OUT := "res://assets/icon"
const CELLS := 128       # the icon's pixel grid
const CELL_PX := 8       # 1024 / 128
const CANVAS := 432      # Android adaptive layers
const CANVAS_CELLS := 160
const INSET := 16        # (CANVAS_CELLS - CELLS) / 2
const PERIOD := 16       # the OLD wall repeats every 16 cells both ways (for the lift)
const GLOW_LO := 16      # the ball + glow live in cells 16..111
const GLOW_HI := 111
## The wall's darkening — the splash's (render_brick_wall.gd DARK 0.36).
const WALL_DARK := 0.36
## Which window of the 256-px tile sits under the icon's top-left cell.
const WALL_OFFSET := Vector2i(0, 0)
## The lift leaves the old wall's own brick tints as a lattice in the
## glow, so only the tube is kept from the lift (cells at least this bright,
## max channel); the glow is remade as two Gaussian blurs of the tube
## (sigmas in cells), each channel fitted by least squares to what the lift
## measured, so its colour and reach match the design's.
const TUBE_LEVEL := 0.5
const GLOW_SIGMAS := [2.0, 7.0]

var _dark := WALL_DARK
var _offset := WALL_OFFSET
var _preview := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dark="):
			_dark = float(a.trim_prefix("--dark="))
		elif a.begins_with("--offset="):
			var p := a.trim_prefix("--offset=").split(",")
			_offset = Vector2i(int(p[0]), int(p[1] if p.size() > 1 else p[0]))
		elif a.begins_with("--preview="):
			_preview = a.trim_prefix("--preview=")
	var src := Image.load_from_file(ProjectSettings.globalize_path(DESIGN))
	if src == null or src.get_width() != CELLS * CELL_PX:
		push_error("no %dpx icon at %s" % [CELLS * CELL_PX, DESIGN])
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)
	var tile := Image.load_from_file(ProjectSettings.globalize_path(WALL))
	if tile == null:
		push_error("no wall tile at " + WALL)
		quit(1)
		return
	tile.convert(Image.FORMAT_RGB8)
	# The 128 grid, one colour per cell.
	var grid: Array[Color] = []
	grid.resize(CELLS * CELLS)
	for y in CELLS:
		for x in CELLS:
			grid[y * CELLS + x] = src.get_pixel(x * CELL_PX + CELL_PX / 2, y * CELL_PX + CELL_PX / 2)
	# The old wall under the ball, estimated: each cell's mean over the
	# icon's ball-free 16×16 border tiles at the same position in the period.
	var est: Array[Color] = []
	est.resize(PERIOD * PERIOD)
	est.fill(Color(0, 0, 0, 0))
	var free_tiles := 0
	for ty in CELLS / PERIOD:
		for tx in CELLS / PERIOD:
			var free := true
			for y in PERIOD:
				for x in PERIOD:
					if _in_glow(tx * PERIOD + x, ty * PERIOD + y):
						free = false
			if not free:
				continue
			free_tiles += 1
			for y in PERIOD:
				for x in PERIOD:
					est[y * PERIOD + x] += grid[(ty * PERIOD + y) * CELLS + tx * PERIOD + x]
	for i in est.size():
		est[i] = est[i] / float(free_tiles)
	# The ball + glow as what it ADDS over the wall (never below zero).
	var add: Array[Color] = []
	add.resize(CELLS * CELLS)
	var lit := 0
	for y in CELLS:
		for x in CELLS:
			var c := Color(0, 0, 0, 1)
			if _in_glow(x, y):
				var e := est[(y % PERIOD) * PERIOD + x % PERIOD]
				var g := grid[y * CELLS + x]
				c = Color(maxf(g.r - e.r, 0.0), maxf(g.g - e.g, 0.0), maxf(g.b - e.b, 0.0), 1.0)
				if c.r + c.g + c.b > 0.02:
					lit += 1
			add[y * CELLS + x] = c
	# The tube stays as lifted; the glow is remade from it.
	var tube: Array[bool] = []
	tube.resize(CELLS * CELLS)
	for i in CELLS * CELLS:
		var a := add[i]
		tube[i] = maxf(a.r, maxf(a.g, a.b)) >= TUBE_LEVEL
	var mask: Array[float] = []
	mask.resize(CELLS * CELLS)
	for i in CELLS * CELLS:
		mask[i] = 1.0 if tube[i] else 0.0
	var bases: Array = []
	for sg in GLOW_SIGMAS:
		bases.push_back(_blur(mask, float(sg)))
	# Per channel: add ≈ k0·b0 + k1·b1 over the non-tube glow cells (normal equations).
	var remade: Array[Color] = add.duplicate()
	for ch in 3:
		var a00 := 0.0
		var a01 := 0.0
		var a11 := 0.0
		var r0 := 0.0
		var r1 := 0.0
		for y in CELLS:
			for x in CELLS:
				var i := y * CELLS + x
				if tube[i] or not _in_glow(x, y):
					continue
				var v: float = add[i][ch]
				var b0: float = bases[0][i]
				var b1: float = bases[1][i]
				a00 += b0 * b0
				a01 += b0 * b1
				a11 += b1 * b1
				r0 += b0 * v
				r1 += b1 * v
		var det := a00 * a11 - a01 * a01
		var k0 := (r0 * a11 - r1 * a01) / det if det != 0.0 else 0.0
		var k1 := (a00 * r1 - a01 * r0) / det if det != 0.0 else 0.0
		print("glow channel %d: k = %.3f, %.3f" % [ch, k0, k1])
		for i in CELLS * CELLS:
			if tube[i]:
				continue
			remade[i][ch] = clampf(k0 * bases[0][i] + k1 * bases[1][i], 0.0, 1.0)
	add = remade
	# The icon: the new wall cell by cell, the glow added on top.
	var icon := Image.create(CELLS * CELL_PX, CELLS * CELL_PX, false, Image.FORMAT_RGB8)
	var sum := 0.0
	for y in CELLS:
		for x in CELLS:
			var w := _wall(tile, x, y)
			var a := add[y * CELLS + x]
			var c := Color(minf(w.r + a.r, 1.0), minf(w.g + a.g, 1.0), minf(w.b + a.b, 1.0), 1.0)
			icon.fill_rect(Rect2i(x * CELL_PX, y * CELL_PX, CELL_PX, CELL_PX), c)
			if not _in_glow(x, y):
				sum += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	print("icon: %d free tiles, %d lit cells, wall border mean %.1f/255 (dark %.2f, offset %s)" % [free_tiles, lit, sum / (CELLS * CELLS - (GLOW_HI - GLOW_LO + 1) * (GLOW_HI - GLOW_LO + 1)) * 255.0, _dark, _offset])
	if _preview != "":
		print("preview ", icon.save_png(_preview), " ", _preview)
		quit()
		return
	_save(icon, "icon_1024.png")
	# Legacy launcher: the whole icon, nearest.
	var legacy := icon.duplicate()
	legacy.resize(192, 192, Image.INTERPOLATE_NEAREST)
	_save(legacy, "android_192.png")
	# Adaptive: the wall alone, continuing the icon's own window 16 cells
	# out on every side; the ball as an alpha layer whose blend over that
	# wall gives back the additive glow.
	var bg := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	var fg := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	fg.fill(Color(0, 0, 0, 0))
	for cy in CANVAS_CELLS:
		for cx in CANVAS_CELLS:
			_cell(bg, cx, cy, _wall(tile, cx - INSET, cy - INSET))
	for y in CELLS:
		for x in CELLS:
			var a := add[y * CELLS + x]
			var k := maxf(a.r, maxf(a.g, a.b))
			if k <= 0.0:
				continue
			_cell(fg, x + INSET, y + INSET, Color(a.r / k, a.g / k, a.b / k, k))
	_save(bg, "adaptive_bg_432.png")
	_save(fg, "adaptive_fg_432.png")
	quit()


## A separable Gaussian blur of a cell field (edges clamped).
func _blur(field: Array[float], sigma: float) -> Array[float]:
	var r := int(ceil(sigma * 3.0))
	var k: Array[float] = []
	var ksum := 0.0
	for d in range(-r, r + 1):
		var w := exp(-0.5 * (d * d) / (sigma * sigma))
		k.push_back(w)
		ksum += w
	for i in k.size():
		k[i] /= ksum
	var tmp: Array[float] = []
	tmp.resize(CELLS * CELLS)
	for y in CELLS:
		for x in CELLS:
			var acc := 0.0
			for d in range(-r, r + 1):
				acc += field[y * CELLS + clampi(x + d, 0, CELLS - 1)] * k[d + r]
			tmp[y * CELLS + x] = acc
	var out: Array[float] = []
	out.resize(CELLS * CELLS)
	for y in CELLS:
		for x in CELLS:
			var acc := 0.0
			for d in range(-r, r + 1):
				acc += tmp[clampi(y + d, 0, CELLS - 1) * CELLS + x] * k[d + r]
			out[y * CELLS + x] = acc
	return out


## The new wall's colour at icon cell (x, y): one tile pixel per cell.
func _wall(tile: Image, x: int, y: int) -> Color:
	var c := tile.get_pixel(posmod(x + _offset.x, tile.get_width()), posmod(y + _offset.y, tile.get_height())) * _dark
	c.a = 1.0
	return c


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
