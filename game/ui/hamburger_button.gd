class_name HamburgerButton
extends Button
## The menu button: three cream bars drawn in code inside a see-through
## dithered-shadow square (ShadowStyle) — the pixel faces have no ☰ and
## system fallback is off. A 72 px face, three 30×5 bars 7 px apart, each
## with a 2 px ink drop (design "Home League Context v2", 2026-10-30).

const SIZE := 72.0 + ShadowStyle.OFFSET
const COLOR := RetroTheme.SCENE_TEXT


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	focus_mode = Control.FOCUS_NONE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	ShadowStyle.draw(self, size, COLOR, button_pressed, is_hovered(), disabled)
	var face := size - Vector2.ONE * ShadowStyle.OFFSET
	var shift := Vector2.ONE * ShadowStyle.OFFSET if button_pressed else Vector2.ZERO
	var w := 30.0
	var h := 5.0
	var gap := 7.0
	var x := roundf((face.x - w) / 2.0)
	var top := roundf((face.y - (3.0 * h + 2.0 * gap)) / 2.0)
	for i in 3:
		var at := Vector2(x, top + i * (h + gap)) + shift
		draw_rect(Rect2(at + Vector2(2, 2), Vector2(w, h)), RetroTheme.SCENE_OUTLINE)
		draw_rect(Rect2(at, Vector2(w, h)), COLOR)
