class_name BrickWall
extends Control
## The splash's brick wall (assets/splash/neon_bg.png, 720×1560: Pizza
## Doggy's brick_wall_pt_2 tile at 4x, rendered by tools/render_brick_wall.gd,
## so the image repeats every 1024 px) from the top of the screen and on to
## its foot: on a screen taller than the design (the moto is 1604) the rows
## under 1560 are the image's own, taken from whole tile periods above its
## foot so the bond carries on without a seam (Ross, 2026-10-31: the bricks
## stopped short of the bottom on the splash and the area archive). Used by
## SplashScreen and AreaArchivePage.

const TEX := "res://assets/splash/neon_bg.png"
const DESIGN := Vector2(720, 1560)
const PERIOD := 1024.0


func _init(screen_h: float) -> void:
	name = "Bricks"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(DESIGN.x, maxf(DESIGN.y, screen_h))
	var tex: Texture2D = load(TEX)
	add_child(_rect(tex, Rect2(Vector2.ZERO, DESIGN), Vector2.ZERO))
	var extra := screen_h - DESIGN.y
	if extra > 0.0:
		var n := ceili(extra / PERIOD)
		var from := Rect2(0, DESIGN.y - PERIOD * n, DESIGN.x, PERIOD * n)
		add_child(_rect(tex, from, Vector2(0, DESIGN.y)))


func extended() -> bool:
	return get_child_count() > 1


func _rect(tex: Texture2D, region: Rect2, at: Vector2) -> TextureRect:
	var r := TextureRect.new()
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = region
	r.texture = a
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.position = at
	r.size = region.size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
