class_name ShadowStyle
extends RefCounted
## The home page's see-through element look, drawn in code: a transparent
## face over the court with a faint tint, a thin edge in the element's
## colour, a subtle dotted texture across the face, and that colour cast as
## a hard offset drop shadow — DITHERED, a 3 px checkerboard, so it reads as
## ink on paper rather than a flat block. The edge stays flat.
## Only the L-shaped strip past the face is painted, so the face stays
## transparent. Pressing drops the face onto its shadow. Used by ShadowCard
## (the mode cards), ShadowPanel and the top-bar elements. `draw` is the
## one-colour form; `draw_ex` takes the edge, fill, dot and shadow colours
## apart (a solid cream tab with an orange shadow, a pine card at 30 %).

## The shadow strip's offset and width (the design's 6; Ross, 2026-09-26: a
## touch tighter).
const OFFSET := 5.0
const EDGE := 2.0
## The face's tint from the design, and the gain every face gets on top so
## they read less transparent over the court (Ross, 2026-09-26).
const TINT := 0.22
const FACE_GAIN := 1.5
## How much more opaque a pressed face gets.
const PRESSED_GAIN := 3.2
## Dither cell, in design px (about 1.5 device px on the phone).
const CELL := 3

## The face's dotted texture: one DOT-px dot per DOT_CELL-px cell, at DOT_ALPHA.
const DOT_CELL := 6
const DOT := 2
const DOT_ALPHA := 0.30
## The dithered shadow's opacity (its checker is already half coverage).
const SHADOW_ALPHA := 0.6

static var _tex: ImageTexture
static var _dots: ImageTexture


## A sparse dot grid tile, white where painted.
static func dot_tex() -> ImageTexture:
	if _dots == null:
		var img := Image.create(DOT_CELL, DOT_CELL, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0))
		for y in DOT:
			for x in DOT:
				img.set_pixel(x, y, Color.WHITE)
		_dots = ImageTexture.create_from_image(img)
	return _dots


## A 2×2-cell checkerboard (CELL px per cell), white where painted.
static func dither_tex() -> ImageTexture:
	if _tex == null:
		var img := Image.create(CELL * 2, CELL * 2, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0))
		for y in CELL * 2:
			for x in CELL * 2:
				if (x / CELL + y / CELL) % 2 == 0:
					img.set_pixel(x, y, Color.WHITE)
		_tex = ImageTexture.create_from_image(img)
	return _tex


## Draw the one-colour style into `ci` (which must have texture_repeat enabled).
static func draw(ci: CanvasItem, size: Vector2, color: Color, pressed: bool, hovered: bool, disabled: bool) -> void:
	draw_ex(ci, size, color, Color(color, face_alpha(TINT)), Color(color, DOT_ALPHA), Color(color, SHADOW_ALPHA), pressed, hovered, disabled)


## A design tint with the face gain applied (solid faces stay solid).
static func face_alpha(tint: float) -> float:
	return minf(1.0, tint * FACE_GAIN)


## The style with its colours apart: `edge` (the flat line), `fill` (the
## face, alpha = the tint), `dot` (the face texture) and `shadow` (the
## dithered L strip). The face is size − OFFSET; the strip fills the rest.
static func draw_ex(ci: CanvasItem, size: Vector2, edge: Color, fill: Color, dot: Color, shadow: Color,
		pressed: bool, hovered: bool, disabled: bool) -> void:
	var w := size.x - OFFSET
	var h := size.y - OFFSET
	if disabled:
		edge = edge.darkened(0.45)
		fill = fill.darkened(0.45)
		dot = dot.darkened(0.45)
		shadow = shadow.darkened(0.45)
	if pressed:
		# Dropped onto its shadow, and a touch more opaque (Ross, 2026-09-26).
		_face(ci, Rect2(Vector2(OFFSET, OFFSET), Vector2(w, h)), edge, Color(fill, minf(1.0, fill.a * PRESSED_GAIN)), dot)
		return
	var tex := dither_tex()
	ci.draw_texture_rect(tex, Rect2(Vector2(w, OFFSET), Vector2(OFFSET, h)), true, shadow)
	ci.draw_texture_rect(tex, Rect2(Vector2(OFFSET, h), Vector2(w - OFFSET, OFFSET)), true, shadow)
	_face(ci, Rect2(Vector2.ZERO, Vector2(w, h)), edge, Color(fill, minf(1.0, fill.a * (1.5 if hovered else 1.0))), dot)


## The face: the fill, the dotted texture over it, a flat solid edge.
static func _face(ci: CanvasItem, face: Rect2, edge: Color, fill: Color, dot: Color) -> void:
	ci.draw_rect(face, fill)
	ci.draw_texture_rect(dot_tex(), face, true, dot)
	ci.draw_rect(face, edge, false, EDGE)


## An ink wash fading downward from `alpha` at the top to nothing at `h`:
## what a bright sky needs behind the chrome at the top of the screen
## (ArenaSet.top_wash). Added by the caller.
const TOP_WASH_H := 300.0


static func top_wash(alpha: float, h := TOP_WASH_H) -> TextureRect:
	var wash := TextureRect.new()
	wash.name = "TopWash"
	var grad := Gradient.new()
	grad.set_color(0, Color(RetroTheme.SCENE_OUTLINE, alpha))
	grad.set_color(1, Color(RetroTheme.SCENE_OUTLINE, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	wash.texture = gt
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.position = Vector2.ZERO
	wash.size = Vector2(720, h)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return wash


## Content margins that keep children inside the face, clear of the shadow.
static func margins(pad: float, pad_h := -1.0) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	var ph := pad if pad_h < 0.0 else pad_h
	sb.content_margin_left = ph
	sb.content_margin_top = pad
	sb.content_margin_right = ph + OFFSET
	sb.content_margin_bottom = pad + OFFSET
	return sb
