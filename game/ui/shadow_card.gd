class_name ShadowCard
extends Button
## A button in the see-through, dithered-shadow style (ShadowStyle): the
## label stack goes in as children (ModeCards); the stylebox is empty and
## everything is drawn. One colour by default; `fill` / `dot` / `shadow`
## override the parts (a solid cream face with an orange shadow — the active
## tab), `tint` the face's opacity.

const OFFSET := ShadowStyle.OFFSET

var color := Color.WHITE
var tint := ShadowStyle.TINT
var fill := Color.TRANSPARENT
var dot := Color.TRANSPARENT
var shadow := Color.TRANSPARENT


func _init(p_color := Color.WHITE) -> void:
	color = p_color
	focus_mode = Control.FOCUS_NONE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	pressed.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


## A solid face (the active tab): `face` opaque, `p_dot` its texture, `p_shadow` the strip.
static func solid(face: Color, p_dot: Color, p_shadow: Color) -> ShadowCard:
	var b := ShadowCard.new(face)
	b.fill = face
	b.dot = p_dot
	b.shadow = Color(p_shadow, ShadowStyle.SHADOW_ALPHA)
	return b


func _draw() -> void:
	var f := fill if fill.a > 0.0 else Color(color, tint)
	var d := dot if dot.a > 0.0 else Color(color, ShadowStyle.DOT_ALPHA)
	var s := shadow if shadow.a > 0.0 else Color(color, ShadowStyle.SHADOW_ALPHA)
	ShadowStyle.draw_ex(self, size, color, f, d, s, button_pressed, is_hovered(), disabled)
