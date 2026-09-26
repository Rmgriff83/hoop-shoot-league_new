class_name IconButton
extends Button
## A square see-through button (ShadowStyle) with a glyph drawn in code (the
## pixel faces have none of these): "locker" — an orange square; "ranks" —
## three bars; "shop" — a gold square. 56 px.

const SIZE := 56.0
const COLOR := RetroTheme.SCENE_TEXT

var kind := "locker"


func _init(p_kind := "locker") -> void:
	kind = p_kind
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
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
	var c := (size - Vector2.ONE * ShadowStyle.OFFSET) / 2.0
	if button_pressed:
		c += Vector2.ONE * ShadowStyle.OFFSET
	match kind:
		"ranks":
			for i in 3:
				var h: float = [12.0, 24.0, 17.0][i]
				draw_rect(Rect2(Vector2(c.x - 14 + i * 10, c.y + 12 - h), Vector2(6, h)), COLOR)
		"shop":
			draw_rect(Rect2(c - Vector2(11, 11), Vector2(22, 22)), COLOR)
			draw_rect(Rect2(c - Vector2(8, 8), Vector2(16, 16)), RetroTheme.LIGHT["gold"])
		_:
			draw_rect(Rect2(c - Vector2(11, 11), Vector2(22, 22)), COLOR)
			draw_rect(Rect2(c - Vector2(8, 8), Vector2(16, 16)), RetroTheme.LIGHT["orange"])
