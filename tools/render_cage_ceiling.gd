extends SceneTree
## The arcade hall's ceiling (Ross, 2026-11-03): Pizza Doggy's building_ceiling_pt_1
## panel as grain over the ceiling's own near-black, the way the beach's tiles keep
## their colour (tools/render_beach_grain.gd): each pixel is the base × how far the
## panel's brightness sits from its own mean, so the mean colour stays the base's.
## DETAIL runs past 1 because the base is nearly black: at 1 the panel moved the
## screen by a level or two and could not be seen.
## → assets/textures/cage_ceiling_grain.png (build_cage.py)
## godot --headless --path . -s tools/render_cage_ceiling.gd

const SOURCE := "res://art/third_party/pizza_doggy/building_ceiling_pt_1.png"
const OUT := "res://assets/textures/cage_ceiling_grain.png"
const BASE := Color8(12, 10, 10)   # build_cage.py's Hall_Dark
const DETAIL := 2.5


func _initialize() -> void:
	var tile := Image.load_from_file(SOURCE)
	tile.convert(Image.FORMAT_RGB8)
	var w := tile.get_width()
	var h := tile.get_height()
	var mean := 0.0
	for y in h:
		for x in w:
			mean += tile.get_pixel(x, y).get_luminance()
	mean /= float(w * h)
	for y in h:
		for x in w:
			var k := maxf(0.0, 1.0 + DETAIL * (tile.get_pixel(x, y).get_luminance() / mean - 1.0))
			tile.set_pixel(x, y, Color(BASE.r * k, BASE.g * k, BASE.b * k))
	var err := tile.save_png(OUT)
	print("%s → %s (%s)" % [SOURCE.get_file(), OUT.get_file(), error_string(err)])
	quit(1 if err != OK else 0)
