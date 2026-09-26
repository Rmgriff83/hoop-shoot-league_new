class_name ShadowCard
extends Button
## A mode card in the see-through, dithered-shadow style (ShadowStyle): the
## label stack goes in as children (ModeCards); the stylebox is empty and
## everything is drawn.

const OFFSET := ShadowStyle.OFFSET

var color := Color.WHITE


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


func _draw() -> void:
	ShadowStyle.draw(self, size, color, button_pressed, is_hovered(), disabled)
