extends SceneTree
## The beach's sand with Pizza Doggy's `dirt_pt_5` grain in it (Ross, 2026-11-02):
## our beach_sand.png keeps the colour, the dirt only says lighter or darker. Each
## pixel is the sand's × (1 + DETAIL × how far the dirt's brightness sits from its
## own mean), then scaled so the tile's mean colour stays the sand's exactly.
## 512 px; the 256 px sand doubles, so its tile still repeats whole.
## → assets/textures/beach_sand_dirt.png (build_beach.py, the Sand quad).
## godot --headless --path . -s tools/render_beach_sand.gd

const SAND := "res://assets/textures/beach_sand.png"
const DIRT := "res://art/third_party/pizza_doggy/dirt_pt_5.png"
const OUT := "res://assets/textures/beach_sand_dirt.png"
const DETAIL := 0.8


func _initialize() -> void:
	var sand := Image.load_from_file(SAND)
	var dirt := Image.load_from_file(DIRT)
	sand.convert(Image.FORMAT_RGB8)
	dirt.convert(Image.FORMAT_RGB8)
	var size := dirt.get_width()
	sand.resize(size, size, Image.INTERPOLATE_NEAREST)
	var dirt_mean := 0.0
	for y in size:
		for x in size:
			dirt_mean += dirt.get_pixel(x, y).get_luminance()
	dirt_mean /= float(size * size)
	var sum_in := Vector3.ZERO
	var sum_out := Vector3.ZERO
	var raw: Array[Vector3] = []
	raw.resize(size * size)
	for y in size:
		for x in size:
			var s := sand.get_pixel(x, y)
			var k := 1.0 + DETAIL * (dirt.get_pixel(x, y).get_luminance() / dirt_mean - 1.0)
			var v := Vector3(s.r, s.g, s.b) * k
			raw[y * size + x] = v
			sum_in += Vector3(s.r, s.g, s.b)
			sum_out += v
	var fix := sum_in / sum_out
	var out := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v: Vector3 = raw[y * size + x] * fix
			out.set_pixel(x, y, Color(v.x, v.y, v.z))
	var err := out.save_png(OUT)
	print("%s + %s → %s (%s)" % [SAND, DIRT, OUT, error_string(err)])
	quit(0 if err == OK else 1)
