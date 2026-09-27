class_name ShadowPanel
extends PanelContainer
## A non-button container in the see-through dithered style (ShadowStyle):
## the element's colour as its edge, tint, dot texture and offset shadow,
## with content margins that keep children clear of the shadow strip. The
## sibling of ShadowCard for panels that only hold content (the opponent
## card, the table, the lists, the shop rows). `tint` is the face's opacity
## (the design's lists sit at 14 %, the pine card at 30 %); `shadow` can
## differ from the edge (a gold upcoming card with the cream shadow).

var color := Color.WHITE
var tint := ShadowStyle.TINT
var shadow := Color.TRANSPARENT


func _init(p_color := Color.WHITE, pad := 20.0, p_tint := ShadowStyle.TINT, pad_h := -1.0) -> void:
	color = p_color
	tint = p_tint
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_theme_stylebox_override("panel", ShadowStyle.margins(pad, pad_h))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := shadow if shadow.a > 0.0 else Color(color, ShadowStyle.SHADOW_ALPHA)
	ShadowStyle.draw_ex(self, size, color, Color(color, ShadowStyle.face_alpha(tint)), Color(color, ShadowStyle.DOT_ALPHA), s, false, false, false)
