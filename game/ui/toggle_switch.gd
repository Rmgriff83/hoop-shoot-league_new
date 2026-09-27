class_name ToggleSwitch
extends Control
## A drawn on/off switch in the retro style (the 30S MODE toggle): a 44×22
## ink well with a 2 px cream border and a 16×14 knob (cream off, orange
## on) with a 2 px ink shadow, sliding to the far side when on. Decorative:
## the row that holds it takes the tap.

const SIZE := Vector2(44, 22)
const KNOB := Vector2(16, 14)

var on := false


func _init(p_on := false) -> void:
	on = p_on
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_on(p_on: bool) -> void:
	on = p_on
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color(RetroTheme.SCENE_OUTLINE, 0.55))
	draw_rect(Rect2(Vector2.ZERO, SIZE), RetroTheme.SCENE_TEXT, false, 2.0)
	var x := SIZE.x - 4.0 - KNOB.x if on else 4.0
	var at := Vector2(x, (SIZE.y - KNOB.y) / 2.0)
	draw_rect(Rect2(at + Vector2(2, 2), KNOB), RetroTheme.SCENE_OUTLINE)
	draw_rect(Rect2(at, KNOB), RetroTheme.LIGHT["orange"] if on else RetroTheme.SCENE_TEXT)
