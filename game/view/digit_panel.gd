class_name DigitPanel
extends RefCounted
## A row of seven-segment digits drawn into an image — the city scoreboard's
## HOME / VISITOR / PER windows (Scoreboard). Lit segments in `color`, unlit
## ones a faint ghost like real LED glass, on black; one unshaded emissive
## StandardMaterial3D for the quad that shows it. Pure Image work + flush(),
## so it is testable headless.

const DIGIT_W := 16
const DIGIT_H := 28
const GAP := 4
const SEG := 3   # segment thickness, px
const BG := Color8(10, 10, 12)
## Segments per glyph: a top, b upper-right, c lower-right, d bottom,
## e lower-left, f upper-left, g middle.
const SEGMENTS := {
	"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
	"6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", " ": "",
}

var digits: int
var color: Color
var material: StandardMaterial3D
var _img: Image
var _tex: ImageTexture
var _text := ""
var _ghost: Color
var _dirty := true


func _init(p_digits: int, p_color: Color) -> void:
	digits = maxi(1, p_digits)
	color = p_color
	_ghost = Color(color.r * 0.16, color.g * 0.16, color.b * 0.16)
	_img = Image.create(width(), DIGIT_H, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	material = StandardMaterial3D.new()
	material.albedo_texture = _tex
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission_texture = _tex
	material.emission_energy_multiplier = 0.6
	_text = " ".repeat(digits)
	flush()


func width() -> int:
	return digits * DIGIT_W + (digits - 1) * GAP


## Right-aligned, leading blanks; too many digits keep the low ones.
func set_number(n: int) -> void:
	set_text(str(n))


func set_text(t: String) -> void:
	var s := t
	if s.length() > digits:
		s = s.substr(s.length() - digits)
	s = s.lpad(digits, " ")
	if s == _text:
		return
	_text = s
	_dirty = true


func text() -> String:
	return _text


## Redraw if anything changed (Scoreboard.advance calls it every frame).
func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	_img.fill(BG)
	for i in digits:
		var x0 := i * (DIGIT_W + GAP)
		var lit: String = SEGMENTS.get(_text[i], "")
		for seg in ["a", "b", "c", "d", "e", "f", "g"]:
			_segment(x0, seg, color if lit.contains(seg) else _ghost)
	_tex.update(_img)


## Lit pixels (in `color`), for tests.
func lit_count() -> int:
	var n := 0
	for y in DIGIT_H:
		for x in _img.get_width():
			if _img.get_pixel(x, y).is_equal_approx(color):
				n += 1
	return n


func _segment(x0: int, seg: String, c: Color) -> void:
	var w := DIGIT_W
	var h := DIGIT_H
	var t := SEG
	var mid := h / 2
	# Bars with a one-pixel gap at every corner, like real seven-segment glass.
	match seg:
		"a": _rect(x0 + t, 0, x0 + w - t - 1, t - 1, c)
		"g": _rect(x0 + t, mid - 1, x0 + w - t - 1, mid + 1, c)
		"d": _rect(x0 + t, h - t, x0 + w - t - 1, h - 1, c)
		"b": _rect(x0 + w - t, t, x0 + w - 1, mid - 3, c)
		"c": _rect(x0 + w - t, mid + 3, x0 + w - 1, h - t - 1, c)
		"f": _rect(x0, t, x0 + t - 1, mid - 3, c)
		"e": _rect(x0, mid + 3, x0 + t - 1, h - t - 1, c)


func _rect(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	_img.fill_rect(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1), c)
