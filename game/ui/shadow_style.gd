class_name ShadowStyle
extends RefCounted
## The home page's see-through element look, drawn in code: a transparent
## face over the court with a faint tint, a thin edge in the element's
## colour, a subtle dotted texture across the face, and that colour cast as
## a hard offset drop shadow — DITHERED, a 3 px checkerboard, so it reads as
## ink on paper rather than a flat block. The edge stays flat.
## Only the L-shaped strip past the face is painted, so the face stays
## transparent. Pressing drops the face onto its shadow. Used by ShadowCard
## (the mode cards) and the top-bar elements.

const OFFSET := 6.0
const EDGE := 2.0
const TINT := 0.22
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


## Draw the style into `ci` (which must have texture_repeat enabled).
static func draw(ci: CanvasItem, size: Vector2, color: Color, pressed: bool, hovered: bool, disabled: bool) -> void:
	var w := size.x - OFFSET
	var h := size.y - OFFSET
	var col := color if not disabled else color.darkened(0.45)
	var tex := dither_tex()
	if pressed:
		var face := Rect2(Vector2(OFFSET, OFFSET), Vector2(w, h))
		_face(ci, face, col, TINT * 2.5)
		return
	var sh := Color(col, SHADOW_ALPHA)
	ci.draw_texture_rect(tex, Rect2(Vector2(w, OFFSET), Vector2(OFFSET, h)), true, sh)
	ci.draw_texture_rect(tex, Rect2(Vector2(OFFSET, h), Vector2(w - OFFSET, OFFSET)), true, sh)
	_face(ci, Rect2(Vector2.ZERO, Vector2(w, h)), col, TINT * (1.5 if hovered else 1.0))


## The face: a faint tint, a subtle dotted texture over it, a flat solid edge.
static func _face(ci: CanvasItem, face: Rect2, col: Color, tint: float) -> void:
	ci.draw_rect(face, Color(col, tint))
	ci.draw_texture_rect(dot_tex(), face, true, Color(col, DOT_ALPHA))
	ci.draw_rect(face, col, false, EDGE)


## Content margins that keep children inside the face, clear of the shadow.
static func margins(pad: float) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = pad
	sb.content_margin_top = pad
	sb.content_margin_right = pad + OFFSET
	sb.content_margin_bottom = pad + OFFSET
	return sb
