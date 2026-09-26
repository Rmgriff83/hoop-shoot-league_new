class_name IconButton
extends Button
## A square see-through button (ShadowStyle) with a glyph: "locker" — the
## pixel ball (icon_ball, 22 px: set your ball); "ranks" — three bars, drawn;
## "multi" — the two-player icon (icon_multiplayer, 30×23 with an ink drop
## shadow); "shop" — a gold square, drawn. 50 px face + the 6 px shadow.

const SIZE := 56.0
const COLOR := RetroTheme.SCENE_TEXT

var kind := "locker"


func _init(p_kind := "locker") -> void:
	kind = p_kind
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	focus_mode = Control.FOCUS_NONE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
		"multi":
			_icon("icon_multiplayer", c, Vector2(30, 23), 2.0)
		_:
			_icon("icon_ball", c, Vector2(22, 22), 0.0)


func _icon(name_: String, c: Vector2, px: Vector2, shadow: float) -> void:
	var t := PixelIcon.tex(name_)
	if t == null:
		draw_rect(Rect2(c - px / 2.0, px), COLOR)
		return
	var at := (c - px / 2.0).round()
	if shadow > 0.0:
		draw_texture_rect(t, Rect2(at + Vector2.ONE * shadow, px), false, RetroTheme.SCENE_OUTLINE)
	draw_texture_rect(t, Rect2(at, px), false)
