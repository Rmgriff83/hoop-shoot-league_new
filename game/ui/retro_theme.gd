class_name RetroTheme
extends RefCounted
## The home screen's look, one place: flat, sharp-cornered panels in the pixel
## faces over the live court, with a hard offset drop shadow in ink (the
## "comic" style — no border, no blur). Two palettes over one layout;
## App.dark_mode picks. Text drawn straight on the 3D (the area name, the
## chevrons, the card labels) uses `on_scene`: a fixed cream face with an ink
## outline. The mode cards are ShadowCard (transparent, their colour as the
## shadow). See docs/HOME.md.

const LIGHT := {
	"bg": Color("#F1E8D0"), "ink": Color("#221C18"), "text": Color("#221C18"),
	"card_text": Color("#221C18"), "panel": Color("#F7F0DC"), "muted": Color("#5A514A"),
	"shadow": Color("#221C18"), "orange": Color("#E8703A"), "gold": Color("#F0B84A"),
	"teal": Color("#3F8C7A"), "blue": Color("#7FAEC6"),
}
const DARK := {
	"bg": Color("#1B1815"), "ink": Color("#F1E8D0"), "text": Color("#F1E8D0"),
	"card_text": Color("#1B1815"), "panel": Color("#2A2622"), "muted": Color("#B8AE9E"),
	"shadow": Color("#000000"), "orange": Color("#D16534"), "gold": Color("#D8A643"),
	"teal": Color("#397E6E"), "blue": Color("#729DB2"),
}
const TOKENS := ["bg", "ink", "text", "card_text", "panel", "muted", "shadow", "orange", "gold", "teal", "blue"]

## Sharp corners, no border (Ross, 2026-09-25): the shape is the hard shadow.
const RADIUS := 0
const BORDER := 0
## The flat offset drop shadow, and where a pressed face lands.
const SHADOW := Vector2(6, 6)
const PRESSED_SHADOW := Vector2(1, 1)
## A strip's edge line (the ticker), since strips carry no shadow.
const RULE := 3
## Text over the court: cream with an ink outline, the same in both palettes.
const SCENE_TEXT := Color("#F1E8D0")
const SCENE_OUTLINE := Color("#221C18")
const OUTLINE := 3


static func current() -> Dictionary:
	var app = Engine.get_main_loop().root.get_node_or_null("App") if Engine.get_main_loop() is SceneTree else null
	return DARK if app != null and bool(app.get("dark_mode")) else LIGHT


static func c(token: String) -> Color:
	return current()[token]


## A panel face: fill, no border, a hard offset shadow in ink.
static func face(fill: Color, radius := RADIUS, margin := 20.0) -> StyleBoxFlat:
	var t := current()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = t["shadow"]
	sb.shadow_size = 1
	sb.shadow_offset = SHADOW
	sb.set_content_margin_all(margin)
	return sb


## The same face pressed: it drops onto its shadow.
static func pressed(fill: Color, radius := RADIUS, margin := 20.0) -> StyleBoxFlat:
	var sb := face(fill.darkened(0.1), radius, margin)
	sb.shadow_offset = PRESSED_SHADOW
	var d := SHADOW.x - PRESSED_SHADOW.x
	sb.expand_margin_left = -d
	sb.expand_margin_top = -d
	sb.expand_margin_right = d
	sb.expand_margin_bottom = d
	return sb


## A flat strip: fill and an ink rule top and bottom, no shadow (the ticker).
static func flat(fill: Color, radius := RADIUS, margin := 12.0) -> StyleBoxFlat:
	var sb := face(fill, radius, margin)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2.ZERO
	sb.border_color = current()["ink"]
	sb.border_width_top = RULE
	sb.border_width_bottom = RULE
	return sb


## Dress a Button as an opaque panel: face / pressed / hover, ink text in the display face.
static func card_button(b: Button, fill: Color, radius := RADIUS, margin := 20.0) -> Button:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", face(fill, radius, margin))
	b.add_theme_stylebox_override("hover", face(fill.lightened(0.05), radius, margin))
	b.add_theme_stylebox_override("pressed", pressed(fill, radius, margin))
	var dis := face(fill.darkened(0.3), radius, margin)
	dis.shadow_size = 0
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", UiFont.display())
	b.add_theme_color_override("font_color", c("card_text"))
	b.add_theme_color_override("font_hover_color", c("card_text"))
	b.add_theme_color_override("font_pressed_color", c("card_text"))
	b.add_theme_color_override("font_disabled_color", c("card_text").lerp(fill, 0.5))
	return b


## Small caps in the body face.
static func caps(text: String, size_ := 16, color := Color.TRANSPARENT) -> Label:
	return UiFont.label(text, size_, c("text") if color == Color.TRANSPARENT else color, UiFont.body_bold())


## A headline in the display face.
static func display(text: String, size_ := 24, color := Color.TRANSPARENT) -> Label:
	return UiFont.label(text, size_, c("text") if color == Color.TRANSPARENT else color, UiFont.display())


## Cream face + ink outline on a Label or Button drawn over the court.
static func on_scene(node: Control) -> Control:
	node.add_theme_color_override("font_color", SCENE_TEXT)
	node.add_theme_color_override("font_outline_color", SCENE_OUTLINE)
	node.add_theme_constant_override("outline_size", OUTLINE)
	if node is Button:
		node.add_theme_color_override("font_hover_color", LIGHT["gold"])
		node.add_theme_color_override("font_pressed_color", LIGHT["orange"])
	return node


## 1240 → "1,240".
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var i := s.length()
	while i > 3:
		out = "," + s.substr(i - 3, 3) + out
		i -= 3
	out = s.substr(0, i) + out
	return ("-" if n < 0 else "") + out
