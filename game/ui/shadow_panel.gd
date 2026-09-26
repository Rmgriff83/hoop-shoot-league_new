class_name ShadowPanel
extends PanelContainer
## A non-button container in the see-through dithered style (ShadowStyle):
## the element's colour as its edge, tint, dot texture and offset shadow,
## with content margins that keep children clear of the shadow strip. The
## sibling of ShadowCard for panels that only hold content (the opponent
## card, shop rows).

var color := Color.WHITE


func _init(p_color := Color.WHITE, pad := 20.0) -> void:
	color = p_color
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_theme_stylebox_override("panel", ShadowStyle.margins(pad))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	ShadowStyle.draw(self, size, color, false, false, false)
