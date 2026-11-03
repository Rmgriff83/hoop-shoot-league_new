extends SceneTree
## The arcade cage's fences and gate (Ross, 2026-11-02): the chain-link's 16 px
## diamonds wearing Pizza Doggy's `asphalt_old_tr_1` (art/third_party/pizza_doggy)
## instead of a flat colour. The light upper edge and dark lower edge stay, as
## multiples of the asphalt (the old slate wire's ratios). 512 px, so the grain
## does not repeat every 40 cm;
## → assets/textures/cage_fence_asphalt.png (build_cage.py tiles it every 6.4 m,
## the gate's finer wire every 1.92 m).
## godot --headless --path . -s tools/render_cage_fence.gd

const SRC := "res://art/third_party/pizza_doggy/asphalt_old_tr_1.png"
const OUT := "res://assets/textures/cage_fence_asphalt.png"
const DIAMOND := 16
const EDGE_HI := 1.35
const EDGE_LO := 0.65


func _initialize() -> void:
	var src := Image.load_from_file(SRC)
	src.convert(Image.FORMAT_RGBA8)
	var out := Image.create_empty(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	for y in src.get_height():
		for x in src.get_width():
			var u := posmod(x + y, DIAMOND)
			var v := posmod(x - y, DIAMOND)
			if u > 1 and v > 1:
				continue   # a hole
			var c := src.get_pixel(x, y)
			var k := EDGE_HI if u == 0 or v == 0 else (EDGE_LO if u == 1 and v == 1 else 1.0)
			out.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, 1.0))
	var err := out.save_png(OUT)
	print("%s → %s (%s)" % [SRC, OUT, error_string(err)])
	quit(0 if err == OK else 1)
