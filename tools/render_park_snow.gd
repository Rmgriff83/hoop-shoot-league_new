extends SceneTree
## The park's lying snow (Ross, 2026-11-03): Pizza Doggy's snow_tr_1, cooled and
## lifted a little from its mid grey. Not all the way to the old flat snow's 238:
## the park's sun and ambient take anything near that past white, and the wind
## lines and hollows are lost with it. MEAN is the knob.
## → assets/textures/park_snow_drift.png (build_park.py)
## godot --headless --path . -s tools/render_park_snow.gd

const SOURCE := "res://art/third_party/pizza_doggy/snow_tr_1.png"
const OUT := "res://assets/textures/park_snow_drift.png"
const MEAN := Color8(196, 200, 204)


func _initialize() -> void:
	var tile := Image.load_from_file(SOURCE)
	tile.convert(Image.FORMAT_RGB8)
	var w := tile.get_width()
	var h := tile.get_height()
	var mean := Vector3.ZERO
	for y in h:
		for x in w:
			var c := tile.get_pixel(x, y)
			mean += Vector3(c.r, c.g, c.b)
	mean /= float(w * h)
	var gain := Vector3(MEAN.r, MEAN.g, MEAN.b) / mean
	for y in h:
		for x in w:
			var c := tile.get_pixel(x, y)
			tile.set_pixel(x, y, Color(minf(c.r * gain.x, 1.0), minf(c.g * gain.y, 1.0), minf(c.b * gain.z, 1.0)))
	var err := tile.save_png(OUT)
	print("%s → %s, gain %s (%s)" % [SOURCE.get_file(), OUT.get_file(), gain, error_string(err)])
	quit(1 if err != OK else 0)
