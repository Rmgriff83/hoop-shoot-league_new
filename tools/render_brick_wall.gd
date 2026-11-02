extends SceneTree
## The splash's brick wall (Ross, 2026-11-01): Pizza Doggy's `brick_wall_pt_2`
## (art/third_party/pizza_doggy, PSX Textures II) at 4x nearest — bricks about
## 96×38 px, the tile's period 1024 both ways — tiled from the top-left into
## the 720×1560 design and darkened near the old wall's mood (a mean brightness
## of ~24/255 — Ross, 2026-11-01: a touch brighter than the old 18 — the hue kept) → assets/splash/neon_bg.png. Row y equals row
## y − 1024, which BrickWall's extension on tall screens relies on. Re-run
## tools/make_boot_splash.gd after this: the boot splash is built from it.
## godot --headless --path . -s tools/render_brick_wall.gd

const SRC := "res://art/third_party/pizza_doggy/brick_wall_pt_2.png"
const OUT := "res://assets/splash/neon_bg.png"
const SCALE := 4
const DESIGN := Vector2i(720, 1560)
const DARK := 0.36


func _initialize() -> void:
	var tile := Image.load_from_file(SRC)
	tile.convert(Image.FORMAT_RGB8)
	var period := tile.get_width() * SCALE
	tile.resize(period, tile.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	var wall := Image.create_empty(DESIGN.x, DESIGN.y, false, Image.FORMAT_RGB8)
	var sum := 0.0
	var edge := Color(0, 0, 0)
	var n_edge := 0
	for y in DESIGN.y:
		for x in DESIGN.x:
			var c := tile.get_pixel(x % period, y % period) * DARK
			c.a = 1.0
			wall.set_pixel(x, y, c)
			sum += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			if y < 300 or y >= DESIGN.y - 300:
				edge += c
				n_edge += 1
	print("period ", period, " mean ", snappedf(sum / (DESIGN.x * DESIGN.y) * 255.0, 0.1), "/255")
	print("edge avg ", Color(edge.r / n_edge, edge.g / n_edge, edge.b / n_edge).to_html(false))
	print("save ", wall.save_png(OUT), " ", wall.get_size())
	quit()
