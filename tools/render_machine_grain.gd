extends SceneTree
## The grain on the cage's machine row (Ross, 2026-11-03: "the surfaces are too
## smooth"): Pizza Doggy's dirt_pt_10 as a small grey tile, its mean at mid grey.
## machine_body.gdshader reads it as lighter or darker over the atlas's colours,
## so the machines keep the design's paint. 128 px, sampled nearest, about 1:1
## on screen from the shooter's spot.
## → assets/textures/cage_machine_grain.png
## godot --headless --path . -s tools/render_machine_grain.gd

const SOURCE := "res://art/third_party/pizza_doggy/dirt_pt_10.png"
const OUT := "res://assets/textures/cage_machine_grain.png"
const TILE := 128


func _initialize() -> void:
	var dirt := Image.load_from_file(SOURCE)
	dirt.convert(Image.FORMAT_RGB8)
	dirt.resize(TILE, TILE, Image.INTERPOLATE_LANCZOS)
	var mean := 0.0
	for y in TILE:
		for x in TILE:
			mean += dirt.get_pixel(x, y).get_luminance()
	mean /= float(TILE * TILE)
	var out := Image.create_empty(TILE, TILE, false, Image.FORMAT_L8)
	for y in TILE:
		for x in TILE:
			var v := clampf(dirt.get_pixel(x, y).get_luminance() / mean * 0.5, 0.0, 1.0)
			out.set_pixel(x, y, Color(v, v, v))
	var err := out.save_png(OUT)
	print("%s → %s (%s)" % [SOURCE.get_file(), OUT.get_file(), error_string(err)])
	quit(1 if err != OK else 0)
