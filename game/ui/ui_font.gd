class_name UiFont
extends RefCounted
## The UI's pixel type, one place: Press Start 2P for display (headlines,
## buttons) and Silkscreen for body (status lines, small labels). Both are
## drawn on an 8 px grid, so sizes that are multiples of GRID stay crisp; the
## imports have antialiasing, hinting and subpixel positioning off and the
## loader re-asserts that so a font never blurs. Also the shared button
## look: a dark translucent panel with a thin accent border.

const DISPLAY := "res://assets/fonts/press_start/PressStart2P-Regular.ttf"
const BODY := "res://assets/fonts/silkscreen/Silkscreen-Regular.ttf"
const BODY_BOLD := "res://assets/fonts/silkscreen/Silkscreen-Bold.ttf"
const GRID := 8

const GOLD := Color(1.0, 0.81, 0.54)
const MUTED := Color(0.62, 0.68, 0.85)
const GREEN := Color(0.42, 0.85, 0.64)
const INK := Color(0.96, 0.95, 0.92)

static var _cache: Dictionary = {}


static func display() -> Font:
	return _font(DISPLAY)


static func body() -> Font:
	return _font(BODY)


static func body_bold() -> Font:
	return _font(BODY_BOLD)


static func _font(path: String) -> Font:
	if _cache.has(path):
		return _cache[path]
	var f: Font = load(path)
	if f is FontFile:
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.generate_mipmaps = false
	_cache[path] = f
	return f


## The nearest size on the pixel grid (never below one cell).
static func snap(size_: int) -> int:
	return maxi(GRID, int(roundf(float(size_) / GRID)) * GRID)


static func label(text: String, size_: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font != null else display())
	l.add_theme_font_size_override("font_size", snap(size_))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A dark translucent panel with a thin accent border: legible over the 3D.
static func panel(fill: Color, border: Color, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	return sb


## Dress a button in the display face and the panel look.
static func style_button(b: Button, size_: int, accent: Color, height := 0.0) -> Button:
	b.add_theme_font_override("font", display())
	b.add_theme_font_size_override("font_size", snap(size_))
	b.focus_mode = Control.FOCUS_NONE
	if height > 0.0:
		b.custom_minimum_size = Vector2(0, height)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.55, 0.6))
	b.add_theme_stylebox_override("normal", panel(Color(0.05, 0.05, 0.08, 0.74), accent))
	b.add_theme_stylebox_override("hover", panel(Color(0.09, 0.08, 0.12, 0.82), accent))
	b.add_theme_stylebox_override("pressed", panel(Color(0.14, 0.09, 0.08, 0.9), accent))
	b.add_theme_stylebox_override("disabled", panel(Color(0.05, 0.05, 0.08, 0.45), accent.darkened(0.5)))
	return b


## A bare text button (no panel) in the display face.
static func flat_button(text: String, size_: int, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", display())
	b.add_theme_font_size_override("font_size", snap(size_))
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", GOLD)
	return b
