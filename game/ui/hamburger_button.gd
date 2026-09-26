class_name HamburgerButton
extends Button
## The menu button: three cream bars drawn in code inside a see-through
## dithered-shadow square (ShadowStyle) — the pixel faces have no ☰ and
## system fallback is off.

const SIZE := 56.0
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
	var w := 24.0
	var h := 4.0
	var x := (face.x - w) / 2.0
	for i in 3:
		var y := face.y / 2.0 - 10.0 + i * 8.0
		draw_rect(Rect2(Vector2(x, y) + shift, Vector2(w, h)), COLOR)
