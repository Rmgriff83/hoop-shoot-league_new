class_name GearButton
extends Button
## A settings cog drawn in code (the pixel faces have no gear glyph, and an
## emoji would fall back to the system font). Eight teeth on a ring, in the
## accent colour; brightens on hover/press.

@export var color := Color(1.0, 0.81, 0.54)
const TEETH := 8


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(72, 72)
	pressed.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) * 0.30
	var col := color.lightened(0.25) if is_hovered() or button_pressed else color
	for i in TEETH:
		var a := TAU * i / TEETH
		var d := Vector2(cos(a), sin(a))
		var p := Vector2(-d.y, d.x) * r * 0.22
		var inner := c + d * r * 0.86
		var outer := c + d * r * 1.32
		draw_colored_polygon(PackedVector2Array([inner - p, outer - p * 0.75, outer + p * 0.75, inner + p]), col)
	draw_arc(c, r * 0.86, 0.0, TAU, 32, col, r * 0.36)
	draw_circle(c, r * 0.36, col.darkened(0.55))
