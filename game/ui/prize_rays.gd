class_name PrizeRays
extends Control
## The epic-pull backdrop (docs/LOCKER.md): a repeating conic of rays in the
## tier's colour turning slowly behind the win card. Pure _draw, no textures.

const WEDGES := 18
const WEDGE_DEG := 7.0
const SPEED_DEG := 20.0
const RADIUS := 1100.0

var color := Color("#E8703A")
var _angle := 0.0


func _init(p_color := Color("#E8703A")) -> void:
	name = "PrizeRays"
	color = p_color
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_angle += deg_to_rad(SPEED_DEG) * delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var pitch := TAU / WEDGES
	var half := deg_to_rad(WEDGE_DEG) * 0.5
	for i in WEDGES:
		var a := _angle + i * pitch
		var pts := PackedVector2Array([c, c + Vector2(cos(a - half), sin(a - half)) * RADIUS,
			c + Vector2(cos(a + half), sin(a + half)) * RADIUS])
		draw_colored_polygon(pts, Color(color, 0.35))


func angle() -> float:
	return _angle
