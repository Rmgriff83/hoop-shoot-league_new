extends SceneTree
## Pizza Doggy's tiles as grain in the beach's own colours (Ross, 2026-11-02): the
## base keeps its colour, the dirt only says lighter or darker. Each pixel is the
## base's × (1 + detail × how far the dirt's brightness sits from its own mean),
## then scaled so the mean colour stays the base's (clipping loses a little).
##   sand   beach_sand.png + dirt_pt_5, doubled to 512, the tile whole.
##   court  beach_court.png + dirt_pt_10, doubled to 960×1024 (67.6 px/m), the
##          dirt every 3 m, on the grey asphalt only.
##   board  street_board.png + dirt_pt_10 (210 px/m), the dirt every metre, on the
##          graphite only.
##   water  beach_water.png + water_2 (Ross, 2026-11-03), doubled to 256, the tile
##          whole. ocean.gdshader averages two drifting layers, which halves the
##          grain again, so this one runs at full strength.
## "Grey only" (Ross): the white lines, sand patches, pale frame and orange square
## stay as they were, told apart by saturation and brightness.
## → assets/textures/*_grain.png + beach_sand_dirt.png (build_beach.py,
## build_street_hoop.py).
## godot --headless --path . -s tools/render_beach_grain.gd

const TEXTURES := "res://assets/textures/"
const PIZZA := "res://art/third_party/pizza_doggy/"
## base, dirt, out, base scale, dirt tile in output pixels, detail, grey only
const JOBS := [
	["beach_sand.png", PIZZA + "dirt_pt_5.png", "beach_sand_dirt.png", 2, 512, 0.8, false],
	["beach_court.png", PIZZA + "dirt_pt_10.png", "beach_court_grain.png", 2, 203, 0.25, true],
	["street_board.png", PIZZA + "dirt_pt_10.png", "street_board_grain.png", 1, 210, 0.25, true],
	["beach_water.png", PIZZA + "water_2.png", "beach_water_grain.png", 2, 256, 1.0, false],
]
## Grey fades out across these (the board's graphite is a cool 0.16 saturated).
const GREY_SAT := Vector2(0.20, 0.30)
const GREY_VAL := Vector2(0.55, 0.68)


func _initialize() -> void:
	var failed := false
	for job in JOBS:
		var err := _render(job[0], job[1], job[2], job[3], job[4], job[5], job[6])
		print("%s + %s → %s (%s)" % [job[0], str(job[1]).get_file(), job[2], error_string(err)])
		failed = failed or err != OK
	quit(1 if failed else 0)


## 1 on grey, 0 on anything coloured or pale.
static func _grey(c: Color) -> float:
	return (1.0 - smoothstep(GREY_SAT.x, GREY_SAT.y, c.s)) * (1.0 - smoothstep(GREY_VAL.x, GREY_VAL.y, c.v))


func _render(base_name: String, dirt_name: String, out_name: String, base_scale: int, tile: int, detail: float, grey_only: bool) -> int:
	var base := Image.load_from_file(TEXTURES + base_name)
	var dirt := Image.load_from_file(dirt_name)
	base.convert(Image.FORMAT_RGB8)
	dirt.convert(Image.FORMAT_RGB8)
	var w := base.get_width() * base_scale
	var h := base.get_height() * base_scale
	base.resize(w, h, Image.INTERPOLATE_NEAREST)
	if dirt.get_width() != tile:
		dirt.resize(tile, tile, Image.INTERPOLATE_LANCZOS)
	var dirt_mean := 0.0
	for y in tile:
		for x in tile:
			dirt_mean += dirt.get_pixel(x, y).get_luminance()
	dirt_mean /= float(tile * tile)
	var sum_in := Vector3.ZERO
	var sum_out := Vector3.ZERO
	var raw: Array[Vector3] = []
	raw.resize(w * h)
	var masks := PackedFloat32Array()
	masks.resize(w * h)
	for y in h:
		for x in w:
			var s := base.get_pixel(x, y)
			var mask := _grey(s) if grey_only else 1.0
			masks[y * w + x] = mask
			var k := 1.0 + mask * detail * (dirt.get_pixel(x % tile, y % tile).get_luminance() / dirt_mean - 1.0)
			var v := Vector3(s.r, s.g, s.b) * k
			raw[y * w + x] = v
			sum_in += Vector3(s.r, s.g, s.b)
			sum_out += v
	var fix := sum_in / sum_out
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var v: Vector3 = raw[y * w + x] * Vector3.ONE.lerp(fix, masks[y * w + x])
			out.set_pixel(x, y, Color(v.x, v.y, v.z))
	return out.save_png(TEXTURES + out_name)
